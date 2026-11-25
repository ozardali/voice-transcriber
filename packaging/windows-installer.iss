; Inno Setup script for the Windows installer. Built by packaging/build-windows.ps1.
; Installs for the current user only, so no administrator rights are needed.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1C2B8E-4D7A-4B53-9C1E-2A7E5D0B9F41}
AppName=Voice Transcriber
AppVersion={#AppVersion}
AppPublisher=Voice Transcriber
DefaultDirName={localappdata}\Programs\Voice Transcriber
DefaultGroupName=Voice Transcriber
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Voice-Transcriber-{#AppVersion}-windows-x64-setup
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\Voice Transcriber.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"

[Files]
Source: "..\dist\Voice Transcriber\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Voice Transcriber"; Filename: "{app}\Voice Transcriber.exe"
Name: "{userdesktop}\Voice Transcriber"; Filename: "{app}\Voice Transcriber.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Voice Transcriber.exe"; Description: "Start Voice Transcriber"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; stop the app if it's still running, so its files can be removed
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM ""Voice Transcriber.exe"""; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
; downloaded models and the log (can be several GB)
Type: filesandordirs; Name: "{localappdata}\Voice Transcriber"
