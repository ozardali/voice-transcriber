"""Local voice message transcriber (faster-whisper + Flask)."""

from __future__ import annotations

import os
import subprocess
import sys
import sysconfig
import tempfile
import threading
import time
import webbrowser
from pathlib import Path

# FROZEN: running from the packaged app (PyInstaller), not from the source folder
FROZEN = getattr(sys, "frozen", False)
RESOURCES = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))


def data_dir() -> Path:
    """Where models and the log go: next to the code, or the usual per-user folder."""
    if not FROZEN:
        return Path(__file__).parent
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Voice Transcriber"
    if sys.platform == "win32":
        return Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local") / "Voice Transcriber"
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "voice-transcriber"


DATA = data_dir()


def _use_bundled_cuda_libs():
    # CTranslate2 needs the pip-installed cuBLAS/cuDNN libraries.
    nvidia = (RESOURCES if FROZEN else Path(sysconfig.get_paths()["purelib"])) / "nvidia"
    if sys.platform == "win32":
        # Windows looks for DLLs on PATH and in registered directories
        for d in sorted(nvidia.glob("*/bin")):
            os.add_dll_directory(str(d))
            os.environ["PATH"] = str(d) + os.pathsep + os.environ.get("PATH", "")
        return
    if sys.platform != "linux":
        return
    # Linux reads LD_LIBRARY_PATH only at startup, so re-exec once if they're missing
    dirs = [str(d) for d in sorted(nvidia.glob("*/lib")) if d.is_dir()]
    current = os.environ.get("LD_LIBRARY_PATH", "")
    missing = [d for d in dirs if d not in current.split(os.pathsep)]
    if missing:
        os.environ["LD_LIBRARY_PATH"] = os.pathsep.join(missing + ([current] if current else []))
        os.execv(sys.executable, [sys.executable, *sys.argv])


_use_bundled_cuda_libs()

import av  # noqa: E402
import numpy as np  # noqa: E402
from faster_whisper import WhisperModel  # noqa: E402
from faster_whisper.tokenizer import _LANGUAGE_CODES  # noqa: E402
from flask import Flask, jsonify, request, send_from_directory  # noqa: E402

HOST = "127.0.0.1"
# from source: next to the code, so deleting the folder removes everything
MODELS_DIR = DATA / "models"
PORT = int(os.environ.get("PORT", "7860"))
SAMPLE_RATE = 16000

# Same three choices for every language. English has its own models, which are
# more accurate for English; every other language uses the multilingual ones.
MODELS = {
    "en": {
        "fast": {
            "model": "base.en", "repo": "Systran/faster-whisper-base.en", "size": "~140 MB",
            "note": "Quickest. May mishear a word now and then.",
        },
        "balanced": {
            "model": "small.en", "repo": "Systran/faster-whisper-small.en", "size": "~480 MB",
            "note": "Noticeably more accurate, still quick.",
        },
        "best": {
            "model": "distil-large-v3", "repo": "Systran/faster-distil-whisper-large-v3", "size": "~1.5 GB",
            "note": "Most accurate. Slow on the CPU.",
        },
    },
    "multi": {
        "fast": {
            "model": "base", "repo": "Systran/faster-whisper-base", "size": "~145 MB",
            "note": "Quickest, but rough in most languages.",
        },
        "balanced": {
            "model": "small", "repo": "Systran/faster-whisper-small", "size": "~485 MB",
            "note": "Good for common languages like Turkish or German.",
        },
        "best": {
            "model": "large-v3-turbo", "repo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
            "size": "~1.6 GB",
            "note": "Most accurate, in many languages. A bit slower on the CPU.",
        },
    },
}
TIER_NAMES = {"fast": "Fast", "balanced": "Balanced", "best": "Best"}
DEFAULT_MODEL = "fast"
DEFAULT_LANGUAGE = "en"
LANGUAGES = list(_LANGUAGE_CODES)


def pick_model(tier: str, language: str) -> dict:
    return MODELS["en" if language == "en" else "multi"][tier]

app = Flask(__name__, static_folder=str(RESOURCES / "static"))

_models: dict[str, WhisperModel] = {}
_lock = threading.Lock()
_gpu = {"works": None}


def gpu_available() -> bool:
    if _gpu["works"] is False:
        return False
    try:
        import ctranslate2

        return ctranslate2.get_cuda_device_count() > 0
    except Exception:
        return False


def is_downloaded(repo: str) -> bool:
    try:
        from huggingface_hub import try_to_load_from_cache

        return isinstance(try_to_load_from_cache(repo, "model.bin", cache_dir=MODELS_DIR), str)
    except Exception:
        return False


def load_audio(path: str) -> np.ndarray:
    """Decode any audio (or video) file to 16 kHz mono float32.

    PyAV ships its own FFmpeg libraries, so no separate ffmpeg install is needed.
    (faster-whisper's own PyAV decoder breaks on recent PyAV, hence this one.)
    """
    try:
        with av.open(path) as container:
            stream = next((s for s in container.streams if s.type == "audio"), None)
            if stream is None:
                raise ValueError("no audio stream")
            resampler = av.AudioResampler(format="flt", layout="mono", rate=SAMPLE_RATE)
            chunks = []
            for frame in container.decode(stream):
                chunks += [f.to_ndarray().reshape(-1) for f in resampler.resample(frame)]
            chunks += [f.to_ndarray().reshape(-1) for f in resampler.resample(None)]
    except (av.FFmpegError, EOFError, ValueError) as e:
        raise ValueError(f"not readable as audio: {e}") from e
    return np.concatenate(chunks) if chunks else np.zeros(0, np.float32)


def get_model(name: str, device: str) -> tuple[WhisperModel, float]:
    cache_key = f"{name}:{device}"
    if cache_key in _models:
        return _models[cache_key], 0.0
    started = time.time()
    compute = "float16" if device == "cuda" else "int8"
    _models[cache_key] = WhisperModel(
        name, device=device, compute_type=compute, download_root=str(MODELS_DIR))
    return _models[cache_key], time.time() - started


def transcribe(audio: np.ndarray, name: str, language: str | None, want: str, fast: bool):
    devices = ["cuda", "cpu"] if want == "gpu" and _gpu["works"] is not False else ["cpu"]
    last_error = None
    for device in devices:
        try:
            model, load_s = get_model(name, device)
            started = time.time()
            segments, info = model.transcribe(
                audio, language=language, vad_filter=True, word_timestamps=True,
                # speed boost: keep only the most likely word at each step instead of
                # comparing 5 options. ~1.5x faster on the CPU, about the same accuracy
                beam_size=1 if fast else 5,
            )
            segments = list(segments)
            if device == "cuda":
                _gpu["works"] = True
            return segments, info, device, load_s, time.time() - started
        except Exception as e:  # noqa: BLE001
            last_error = e
            _models.pop(f"{name}:{device}", None)
            if device == "cuda":
                _gpu["works"] = False
    raise last_error


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


def storage() -> dict:
    """How many models are downloaded and how much space they take."""
    count = size = 0
    if MODELS_DIR.is_dir():
        count = len(list(MODELS_DIR.glob("models--*/snapshots/*/model.bin")))
        # the snapshots are symlinks to blobs, so only count real files
        size = sum(f.stat().st_size for f in MODELS_DIR.rglob("*") if f.is_file() and not f.is_symlink())
    return {"count": count, "bytes": size}


@app.get("/api/models")
def models():
    return jsonify({
        "default": DEFAULT_MODEL,
        "default_language": DEFAULT_LANGUAGE,
        "languages": LANGUAGES,
        "gpu": gpu_available(),
        "storage": storage(),
        "models": {
            group: [
                {"id": tier, "name": TIER_NAMES[tier], **{f: m[f] for f in ("model", "repo", "size", "note")},
                 "downloaded": is_downloaded(m["repo"])}
                for tier, m in tiers.items()
            ]
            for group, tiers in MODELS.items()
        },
    })


@app.post("/api/transcribe")
def api_transcribe():
    # custom header forces a CORS preflight, so other sites can't send files here
    if request.headers.get("X-Voice-Transcriber") != "1":
        return jsonify({"error": "Forbidden"}), 403
    upload = request.files.get("file")
    tier = request.form.get("model", DEFAULT_MODEL)
    language = request.form.get("language", DEFAULT_LANGUAGE)
    want = request.form.get("device", "gpu")
    fast = request.form.get("fast") == "1"
    if upload is None or not upload.filename:
        return jsonify({"error": "No file received."}), 400
    if tier not in TIER_NAMES:
        return jsonify({"error": f"Unknown model: {tier}"}), 400
    if language != "auto" and language not in LANGUAGES:
        return jsonify({"error": f"Unknown language: {language}"}), 400
    name = pick_model(tier, language)["model"]
    if want not in ("gpu", "cpu"):
        return jsonify({"error": f"Unknown device: {want}"}), 400

    suffix = Path(upload.filename).suffix or ".audio"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        upload.save(tmp)
        tmp_path = tmp.name
    try:
        try:
            audio = load_audio(tmp_path)
        except ValueError:
            return jsonify({"error": "This file could not be read as audio."}), 400
        if audio.size == 0:
            return jsonify({"error": "The file contains no audio."}), 400

        with _lock:
            segments, info, device, load_s, run_s = transcribe(
                audio, name, None if language == "auto" else language, want, fast)
        return jsonify({
            "text": " ".join(s.text.strip() for s in segments),
            "segments": [
                {
                    "start": round(s.start, 2),
                    "end": round(s.end, 2),
                    "words": [
                        {"start": round(w.start, 2), "end": round(w.end, 2), "word": w.word}
                        for w in (s.words or [])
                    ],
                }
                for s in segments
            ],
            "duration": round(audio.size / SAMPLE_RATE, 1),
            "elapsed": round(run_s, 1),
            "load": round(load_s, 1),
            "device": device,
            "model": name,
            "fast": fast,
            "language": info.language,
            "detected": language == "auto",
            "language_probability": round(info.language_probability, 2),
        })
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": f"Transcription failed: {e}"}), 500
    finally:
        os.unlink(tmp_path)


_window = {"win": None}


@app.post("/api/show")
def api_show():
    # used when the app is started a second time: bring the window up instead
    if request.headers.get("X-Voice-Transcriber") != "1":
        return jsonify({"error": "Forbidden"}), 403
    win = _window["win"]
    if win is None:
        return jsonify({"error": "No app window"}), 409
    win.restore()
    win.show()
    if sys.platform == "darwin":
        from AppKit import NSApp
        from PyObjCTools import AppHelper
        AppHelper.callAfter(lambda: NSApp.activateIgnoringOtherApps_(True))
    return jsonify({"ok": True})


@app.post("/api/open-models")
def api_open_models():
    # show the models folder in Finder or the file manager
    if request.headers.get("X-Voice-Transcriber") != "1":
        return jsonify({"error": "Forbidden"}), 403
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    if sys.platform == "win32":
        os.startfile(MODELS_DIR)  # noqa: S606 - opens Explorer
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(MODELS_DIR)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return jsonify({"ok": True})


@app.post("/api/quit")
def api_quit():
    # custom header forces a CORS preflight, so other sites can't call this
    if request.headers.get("X-Voice-Transcriber") != "1":
        return jsonify({"error": "Forbidden"}), 403
    threading.Timer(0.3, lambda: os._exit(0)).start()
    return jsonify({"ok": True})


def wait_for_server(url: str, timeout: float = 15) -> None:
    import urllib.request
    end = time.time() + timeout
    while time.time() < end:
        try:
            urllib.request.urlopen(f"{url}/api/models", timeout=1)
            return
        except OSError:
            time.sleep(0.1)


def run_window(url: str) -> bool:
    """Show the page in its own app window. Returns False if that isn't possible."""
    try:
        import webview
    except ImportError as e:
        print(f"No app window ({e}), using the browser instead.")
        return False
    wait_for_server(url)
    _window["win"] = webview.create_window(
        "Voice Transcriber", url, width=1180, height=820, min_size=(720, 520))
    try:
        webview.start(icon=str(RESOURCES / "assets" / "icon.svg"))
    except Exception as e:  # e.g. missing GUI libraries on Linux
        print(f"App window failed ({e}), using the browser instead.")
        _window["win"] = None
        return False
    return True


def hand_over_to_running(url: str) -> bool:
    """If the app is already running, bring it to the front and return True."""
    import urllib.error
    import urllib.request

    try:
        urllib.request.urlopen(f"{url}/api/models", timeout=1)
    except OSError:
        return False  # nothing running
    show = urllib.request.Request(f"{url}/api/show", method="POST",
                                  headers={"X-Voice-Transcriber": "1"})
    try:
        urllib.request.urlopen(show, timeout=3)
        return True  # its window came to the front
    except urllib.error.HTTPError as e:
        if e.code == 409:  # running without a window: open it in the browser
            webbrowser.open(url)
            return True
    except OSError:
        pass
    return False


if __name__ == "__main__":
    url = f"http://{HOST}:{PORT}"
    if hand_over_to_running(url):
        sys.exit()
    if FROZEN:
        # a packaged app has no terminal, so keep the output in a log file.
        # Only now: a second copy that just hands over must not wipe the log.
        DATA.mkdir(parents=True, exist_ok=True)
        sys.stdout = sys.stderr = open(DATA / "app.log", "w", buffering=1, encoding="utf-8")
    print(f"Voice Transcriber: {url}")
    if os.environ.get("NO_BROWSER") == "1":  # server only
        app.run(host=HOST, port=PORT, threaded=True)
        sys.exit()

    threading.Thread(
        target=lambda: app.run(host=HOST, port=PORT, threaded=True, use_reloader=False),
        daemon=True).start()
    if os.environ.get("NO_WINDOW") != "1" and run_window(url):
        os._exit(0)  # window closed: quit the app
    webbrowser.open(url)
    threading.Event().wait()  # keep serving until Quit or Ctrl+C
