; Chithram for Windows: Inno Setup script. The release workflow builds the app
; (flutter build windows) and compiles this with
;   iscc /DAppVersion=0.2.0 windows\installer\chithram.iss
; Installs for the current user by default (no admin prompt); the installer
; offers an all-users install too.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6E0B9C1E-3D4A-4F57-9B1E-7A5C2D8F0A61}
AppName=Chithram
AppVersion={#AppVersion}
AppVerName=Chithram {#AppVersion}
AppPublisher=Rajeev Sudharamachandran
AppPublisherURL=https://github.com/sudharamachandranrajeev/chithram
AppSupportURL=https://github.com/sudharamachandranrajeev/chithram/issues
AppUpdatesURL=https://github.com/sudharamachandranrajeev/chithram/releases
DefaultDirName={autopf}\Chithram
DefaultGroupName=Chithram
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
OutputDir=..\..\build\installer
OutputBaseFilename=Chithram-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\chithram.exe
UninstallDisplayName=Chithram
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
; Windows 10 1809 or later (and Windows 11)
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Chithram"; Filename: "{app}\chithram.exe"; Comment: "Malayalam & Tamil music"
Name: "{autodesktop}\Chithram"; Filename: "{app}\chithram.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chithram.exe"; Description: "{cm:LaunchProgram,Chithram}"; Flags: nowait postinstall skipifsilent
