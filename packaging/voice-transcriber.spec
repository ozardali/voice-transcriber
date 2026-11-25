# PyInstaller recipe for the packaged app. Run it through packaging/build-mac.sh
# or packaging/build-windows.ps1 rather than by hand.
#   macOS:   dist/Voice Transcriber.app
#   Windows: dist/Voice Transcriber/Voice Transcriber.exe
import sys
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs

ROOT = Path(SPECPATH).parent
VERSION = "1.0.0"
NAME = "Voice Transcriber"

datas = [
    (str(ROOT / "static"), "static"),
    (str(ROOT / "assets" / "icon.svg"), "assets"),
]
datas += collect_data_files("faster_whisper")  # the voice detection (VAD) model
binaries = collect_dynamic_libs("ctranslate2")

if sys.platform == "darwin":
    # layered icon for macOS 26+ (light, dark, tinted, clear)
    datas.append((str(ROOT / "assets" / "Assets.car"), "."))

a = Analysis(
    [str(ROOT / "app.py")],
    pathex=[str(ROOT)],
    datas=datas,
    binaries=binaries,
    # big optional packages that get picked up through other libraries but aren't used
    excludes=["tkinter", "matplotlib", "IPython", "PyQt5", "PyQt6", "PySide2", "PySide6", "qtpy", "torch"],
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=NAME,
    console=False,  # no terminal window
    icon=str(ROOT / "assets" / ("icon.icns" if sys.platform == "darwin" else "icon.ico")),
)
coll = COLLECT(exe, a.binaries, a.datas, name=NAME)

if sys.platform == "darwin":
    app = BUNDLE(
        coll,
        name=f"{NAME}.app",
        icon=str(ROOT / "assets" / "icon.icns"),
        bundle_identifier="local.voice-transcriber",
        version=VERSION,
        info_plist={
            "CFBundleName": NAME,
            "CFBundleDisplayName": NAME,
            "CFBundleShortVersionString": VERSION,
            "CFBundleVersion": VERSION,
            "CFBundleIconName": "AppIcon",  # use Assets.car on macOS 26+
            "LSApplicationCategoryType": "public.app-category.productivity",
            "LSMinimumSystemVersion": "12.0",
            "NSHighResolutionCapable": True,
        },
    )
