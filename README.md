# Voice Transcriber

A small app that turns voice messages into English text. You drag an audio file onto a web page and get the text back in a few seconds.

Everything runs on your own computer. Your audio is never uploaded anywhere. The internet is only used once, to download a model the first time you use it.

It's handy for long WhatsApp voice messages that you'd rather read than listen to.

## What it does

- Drag one or more audio files onto the page (.ogg, .opus, .m4a, .mp3, .wav and more).
- Pick one of three models: fast, balanced or best.
- Run on your graphics card (GPU) or on the processor (CPU).
- See every transcript in a numbered list. You can collapse items, remove them, copy the text or save it as a .txt file.
- Play the audio right inside the list. The text follows along as it plays.
- Each result shows how long it took, so you can compare models and GPU vs CPU.

## Listening along

Every transcript has its own small player. Press play and the app highlights the sentence you are hearing, and the word inside it a bit stronger. If the text is long, the page scrolls with it.

- Click any word to jump to that spot in the audio.
- Drag the slider to move around.
- Press `Space` to play or pause the last recording you used.
- Only one recording plays at a time. Starting another one pauses the first.

This works because the model also tells us when each word starts and ends. The timing is usually very close, but it can be a little off on fast or unclear speech.

## What you need

- Linux (tested on CachyOS with KDE) or macOS. On a Mac it always runs on the CPU.
- Python 3.10 or newer
- `ffmpeg`
- Optional: an NVIDIA graphics card. Without one, it still works on the CPU, just slower.

You don't have to install Python or ffmpeg yourself. If they're missing, `./start.sh` tells you what it will install and asks first. It uses Homebrew on macOS (and offers to install Homebrew too), and pacman, apt, dnf or zypper on Linux.

## Getting started

```bash
git clone git@github.com:ozardali/voice-transcriber.git
cd voice-transcriber
./start.sh
```

The first start takes a few minutes. It creates a `.venv` folder and installs everything there. If it finds an NVIDIA card, it also installs the CUDA libraries (about 2 GB). After that, the app opens in its own window. Close the window to stop it.

If the window can't open (for example, a library is missing on Linux), the app opens in your browser at http://127.0.0.1:7860 instead. Then press `Ctrl+C` in the terminal to stop it.

### Start it with one click

```bash
./install-shortcut.sh
```

This adds a **Voice Transcriber** icon to your app menu and your desktop. On macOS it creates `~/Applications/Voice Transcriber.app`, which you can find with Spotlight or Launchpad, or drag to the Dock. Click it and the app opens in its own window, with its own icon in the Dock or taskbar. If it's already running, the icon brings the window to the front.

If Python or ffmpeg is still missing, the icon opens a terminal instead and runs `./start.sh` there, so it can ask before installing anything.

To stop it, close the window (or press `Cmd+Q` on a Mac). The app writes its log to `app.log`.

If you move the folder, run `./install-shortcut.sh` again.

## The models

All three models only understand English.

| Option | Model | Download size | Good for |
|---|---|---|---|
| Fast | `base.en` | about 140 MB | Quick checks. Sometimes it gets a word wrong. |
| Balanced | `small.en` | about 480 MB | Much better, still quick. |
| Best | `distil-large-v3` | about 1.5 GB | The most accurate. Slow on the CPU. |

A model downloads the first time you use it. The page shows "ready" next to the models you already have. They are saved in `~/.cache/huggingface/hub`.

## GPU or CPU?

Use the **Run on** switch to choose. Here is how long a 1 minute 53 second voice message took on my computer (RTX 3060 Ti and a 12 thread CPU):

| Model | GPU | CPU |
|---|---|---|
| Fast | 0.9 s | 3.6 s |
| Balanced | 1.5 s | 10.4 s |
| Best | 1.6 s | 18.9 s |

With a GPU, all three are about the same speed, so just use **Best**. On the CPU, **Balanced** is a good middle ground.

If you pick GPU but it doesn't work, the app uses the CPU instead and tells you in the result.

### Adding GPU support later

If you installed the app before you had an NVIDIA card (or the GPU option is greyed out), run:

```bash
.venv/bin/pip install -r requirements-gpu.txt
```

The CUDA libraries go into `.venv` only. You don't need to install CUDA on your system, just the normal NVIDIA driver.

## Files

| File | What it is |
|---|---|
| `app.py` | The server. It decodes the audio and runs the model. |
| `static/index.html` | The web page (plain HTML, CSS and JavaScript). |
| `start.sh` | Installs on the first run, then starts the app in the terminal. |
| `launch.sh` | Starts the app in the background. The desktop icon uses this. |
| `install-shortcut.sh` | Adds the icon to your app menu and desktop. |
| `assets/` | The app icon. `AppIcon.icon` is the layered macOS version (light, dark, tinted and clear), `icon.svg` is for Linux. After changing the design, run `assets/build-icons.sh` (macOS with Xcode) to rebuild `Assets.car` and `icon.icns`. |
| `requirements.txt` | Python packages. |
| `requirements-gpu.txt` | Extra packages for NVIDIA GPUs. |

## Settings

You can change these when you start the app:

```bash
PORT=8000 ./start.sh        # use another port
NO_WINDOW=1 ./start.sh      # use the browser instead of an app window
NO_BROWSER=1 ./start.sh     # only run the server, open nothing
```

## Good to know

- The app only listens on `127.0.0.1`, so other devices on your network can't use it.
- It transcribes one file at a time. If you drop several, they wait in a queue.
- Audio is decoded with `ffmpeg`. The decoder that comes with faster-whisper didn't work with the newest PyAV version, so the app doesn't use it.

## Built with

- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for speech to text
- [Flask](https://flask.palletsprojects.com/) for the small web server
