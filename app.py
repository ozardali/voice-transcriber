"""Local voice message transcriber (faster-whisper + Flask)."""

import os
import subprocess
import sys
import sysconfig
import tempfile
import threading
import time
import webbrowser
from pathlib import Path


def _use_bundled_cuda_libs():
    # CTranslate2 needs the pip-installed cuBLAS/cuDNN on LD_LIBRARY_PATH,
    # which is only read at startup, so re-exec once if they're missing.
    nvidia = Path(sysconfig.get_paths()["purelib"]) / "nvidia"
    dirs = [str(d) for d in sorted(nvidia.glob("*/lib")) if d.is_dir()]
    current = os.environ.get("LD_LIBRARY_PATH", "")
    missing = [d for d in dirs if d not in current.split(os.pathsep)]
    if missing:
        os.environ["LD_LIBRARY_PATH"] = os.pathsep.join(missing + ([current] if current else []))
        os.execv(sys.executable, [sys.executable, *sys.argv])


_use_bundled_cuda_libs()

import numpy as np  # noqa: E402
from faster_whisper import WhisperModel  # noqa: E402
from flask import Flask, jsonify, request, send_from_directory  # noqa: E402

HOST = "127.0.0.1"
PORT = int(os.environ.get("PORT", "7860"))
SAMPLE_RATE = 16000

MODELS = {
    "fast": {
        "name": "Fast",
        "model": "base.en",
        "repo": "Systran/faster-whisper-base.en",
        "size": "~140 MB",
        "note": "Done in seconds. Occasionally mishears a word.",
    },
    "balanced": {
        "name": "Balanced",
        "model": "small.en",
        "repo": "Systran/faster-whisper-small.en",
        "size": "~480 MB",
        "note": "Noticeably more accurate, a little slower.",
    },
    "best": {
        "name": "Best",
        "model": "distil-large-v3",
        "repo": "Systran/faster-distil-whisper-large-v3",
        "size": "~1.5 GB",
        "note": "Most accurate. Slow without a GPU.",
    },
}
DEFAULT_MODEL = "fast"

app = Flask(__name__, static_folder="static")

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

        return isinstance(try_to_load_from_cache(repo, "model.bin"), str)
    except Exception:
        return False


def load_audio(path: str) -> np.ndarray:
    # faster-whisper's PyAV decoder breaks on recent PyAV, use ffmpeg instead
    raw = subprocess.run(
        ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", path,
         "-f", "f32le", "-ac", "1", "-ar", str(SAMPLE_RATE), "-"],
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(raw, np.float32)


def get_model(key: str, device: str) -> tuple[WhisperModel, float]:
    cache_key = f"{key}:{device}"
    if cache_key in _models:
        return _models[cache_key], 0.0
    started = time.time()
    compute = "float16" if device == "cuda" else "int8"
    _models[cache_key] = WhisperModel(MODELS[key]["model"], device=device, compute_type=compute)
    return _models[cache_key], time.time() - started


def transcribe(audio: np.ndarray, key: str, want: str):
    devices = ["cuda", "cpu"] if want == "gpu" and _gpu["works"] is not False else ["cpu"]
    last_error = None
    for device in devices:
        try:
            model, load_s = get_model(key, device)
            started = time.time()
            segments, _ = model.transcribe(
                audio, language="en", beam_size=5, vad_filter=True, word_timestamps=True
            )
            segments = list(segments)
            if device == "cuda":
                _gpu["works"] = True
            return segments, device, load_s, time.time() - started
        except Exception as e:  # noqa: BLE001
            last_error = e
            _models.pop(f"{key}:{device}", None)
            if device == "cuda":
                _gpu["works"] = False
    raise last_error


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.get("/api/models")
def models():
    return jsonify({
        "default": DEFAULT_MODEL,
        "gpu": gpu_available(),
        "models": [
            {"id": k, **{f: v[f] for f in ("name", "model", "size", "note")},
             "downloaded": is_downloaded(v["repo"])}
            for k, v in MODELS.items()
        ],
    })


@app.post("/api/transcribe")
def api_transcribe():
    # custom header forces a CORS preflight, so other sites can't send files here
    if request.headers.get("X-Voice-Transcriber") != "1":
        return jsonify({"error": "Forbidden"}), 403
    upload = request.files.get("file")
    key = request.form.get("model", DEFAULT_MODEL)
    want = request.form.get("device", "gpu")
    if upload is None or not upload.filename:
        return jsonify({"error": "No file received."}), 400
    if key not in MODELS:
        return jsonify({"error": f"Unknown model: {key}"}), 400
    if want not in ("gpu", "cpu"):
        return jsonify({"error": f"Unknown device: {want}"}), 400

    suffix = Path(upload.filename).suffix or ".audio"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        upload.save(tmp)
        tmp_path = tmp.name
    try:
        try:
            audio = load_audio(tmp_path)
        except subprocess.CalledProcessError:
            return jsonify({"error": "This file could not be read as audio."}), 400
        if audio.size == 0:
            return jsonify({"error": "The file contains no audio."}), 400

        with _lock:
            segments, device, load_s, run_s = transcribe(audio, key, want)
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
            "model": MODELS[key]["model"],
        })
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": f"Transcription failed: {e}"}), 500
    finally:
        os.unlink(tmp_path)


_window = {"win": None}


@app.post("/api/show")
def api_show():
    # used by "start.sh --launch" when the app is already running
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
        webview.start(icon=str(Path(__file__).parent / "assets" / "icon.svg"))
    except Exception as e:  # e.g. missing GUI libraries on Linux
        print(f"App window failed ({e}), using the browser instead.")
        _window["win"] = None
        return False
    return True


if __name__ == "__main__":
    url = f"http://{HOST}:{PORT}"
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
