# Build the Windows app and its installer (64-bit).
#   powershell -ExecutionPolicy Bypass -File packaging\build-windows.ps1
# Needs Python 3.12 (py launcher) and Inno Setup 6 (iscc.exe) for the installer.
# Output: dist\Voice-Transcriber-<version>-windows-x64-setup.exe
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$name = "Voice Transcriber"
$version = (Select-String -Path packaging\voice-transcriber.spec -Pattern '^VERSION = "(.*)"').Matches[0].Groups[1].Value
$venv = ".build\venv"

if (-not (Test-Path "$venv\Scripts\python.exe")) {
    py -3.12 -m venv $venv
}
& "$venv\Scripts\python.exe" -m pip install -q --upgrade pip
& "$venv\Scripts\python.exe" -m pip install -q -r requirements.txt "pyinstaller>=6.10,<7"

Remove-Item -Recurse -Force "dist\$name" -ErrorAction SilentlyContinue
& "$venv\Scripts\pyinstaller.exe" --noconfirm --clean --log-level WARN `
    --workpath .build\pyinstaller --distpath dist packaging\voice-transcriber.spec
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

$iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $candidate = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $candidate) { $iscc = $candidate }
}
if (-not $iscc) {
    Write-Host "Inno Setup not found: skipping the installer. The app is in dist\$name."
    exit 0
}
& $iscc "/DAppVersion=$version" /Q packaging\windows-installer.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
Write-Host "Built dist\Voice-Transcriber-$version-windows-x64-setup.exe"
