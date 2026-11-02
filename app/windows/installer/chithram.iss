; Chithram for Windows: Inno Setup script. The release workflow builds the app
; (flutter build windows) and compiles this with
;   iscc /DAppVersion=0.2.0 windows\installer\chithram.iss
; Installs for the current user by default (no admin prompt); the installer
; offers an all-users install too.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define Release "..\..\build\windows\x64\runner\Release"

; Up to 0.2.1 this script reused Paattu's AppId. Setup then treated Chithram
; as Paattu: it installed into Paattu's folder, both apps shared one data\
; folder (data\app.so is the whole app), and opening one ran the other.
; The [Code] section below cleans up those installs. Never share this AppId.
#define OldSharedAppId "{6E0B9C1E-3D4A-4F57-9B1E-7A5C2D8F0A61}"

[Setup]
AppId={{0A13D487-F502-40BC-84E4-9F69588F5B02}
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
Name: "{autoprograms}\Chithram"; Filename: "{app}\chithram.exe"; Comment: "Bring-your-own-sources video"
Name: "{autodesktop}\Chithram"; Filename: "{app}\chithram.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chithram.exe"; Description: "{cm:LaunchProgram,Chithram}"; Flags: nowait postinstall skipifsilent

[Code]
const
  OldSharedKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#OldSharedAppId}_is1';

var
  PaattuNeedsRepair: Boolean;

{ The first .exe in Dir that is not Chithram's or an Inno uninstaller, or ''. }
function ForeignExe(Dir: String): String;
var
  FindRec: TFindRec;
  Name: String;
begin
  Result := '';
  if FindFirst(AddBackslash(Dir) + '*.exe', FindRec) then
  try
    repeat
      Name := Lowercase(FindRec.Name);
      if (Name <> 'chithram.exe') and (Copy(Name, 1, 5) <> 'unins') then
        Result := FindRec.Name;
    until (Result <> '') or not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ Folder of an install made under the old shared AppId, or ''. }
function OldSharedDir(): String;
begin
  if not RegQueryStringValue(HKCU, OldSharedKey, 'Inno Setup: App Path', Result) then
    if not RegQueryStringValue(HKLM, OldSharedKey, 'Inno Setup: App Path', Result) then
      Result := '';
end;

{ Removes a Chithram-only install made under the old shared AppId. Inno's
  uninstaller re-launches itself from %TEMP%, so wait for its exe to go. }
procedure UninstallOldChithram(Dir: String);
var
  Uninst: String;
  Code, Waited: Integer;
begin
  Uninst := AddBackslash(Dir) + 'unins000.exe';
  if not FileExists(Uninst) then
    Exit;
  Exec(Uninst, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE,
    ewWaitUntilTerminated, Code);
  Waited := 0;
  while FileExists(Uninst) and (Waited < 60000) do
  begin
    Sleep(250);
    Waited := Waited + 250;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  App, Exe, Dir: String;
begin
  Result := '';
  App := ExpandConstant('{app}');

  { Never install next to another app: they would share data\. }
  Exe := ForeignExe(App);
  if Exe <> '' then
  begin
    Result := App + ' belongs to another app (' + Exe + '). ' +
      'Chithram must have its own folder. Go back and choose another one.';
    Exit;
  end;

  Dir := OldSharedDir();
  if (Dir = '') or not FileExists(AddBackslash(Dir) + 'chithram.exe') then
    Exit;
  if FileExists(AddBackslash(Dir) + 'paattu.exe') then
  begin
    { Chithram was put inside Paattu's folder. Take only chithram.exe and its
      desktop shortcut out; everything else there is Paattu's. }
    DeleteFile(AddBackslash(Dir) + 'chithram.exe');
    DeleteFile(ExpandConstant('{autodesktop}\Chithram.lnk'));
    PaattuNeedsRepair := True;
  end
  else
    UninstallOldChithram(Dir);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and PaattuNeedsRepair then
    SuppressibleMsgBox('Older Chithram versions were installed inside the Paattu folder, ' +
      'so Paattu may open Chithram. Chithram now has its own folder. ' +
      'Reinstall Paattu to repair it.', mbInformation, MB_OK, IDOK);
end;
