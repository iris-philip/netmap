#ifndef AppVersion
  #define AppVersion "1.2.3"
#endif
[Setup]
AppId={{907486D3-9EB0-4565-A364-C49002BDA6E3}
AppName=NetMap
AppVersion={#AppVersion}
AppPublisher=IRIS ELECTRONICS
DefaultDirName={localappdata}\Programs\NetMap
DefaultGroupName=NetMap
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=NetMap-{#AppVersion}-Windows-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\netmap.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
UsePreviousTasks=no
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "runtime\*.dll"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\NetMap"; Filename: "{app}\netmap.exe"
Name: "{autodesktop}\NetMap"; Filename: "{app}\netmap.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\netmap.exe"; Description: "Launch NetMap"; Flags: nowait postinstall skipifsilent
