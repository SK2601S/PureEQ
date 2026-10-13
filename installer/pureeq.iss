; Inno Setup script for the SK EQ Windows installer.
;
; Build the app first, then compile this script:
;   flutter build windows --release
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\pureeq.iss
; Output: dist\SK-EQ-Setup-<version>.exe
;
; The version can be overridden from the command line: ISCC /DAppVersion=1.2.0 ...

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "SK EQ"
#define AppExe "SKEQ.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; Never change AppId: it is how an update finds and replaces the existing
; install (including installs from when the app was called PureEQ).
AppId={{6E3C1F4A-8B2D-4C7E-9A51-2F0D8C3B7E19}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=SK EQ
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=..\dist
OutputBaseFilename=SK-EQ-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs per-user without admin rights; the user may choose "all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Close running copies before replacing files. "force": if a copy does not
; close when asked (it hides to the tray instead), end it — otherwise its
; files stay in use and a silent update fails. Settings are saved within
; half a second of any change, so nothing is lost.
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Leftovers from when the app was called PureEQ (old exe name and shortcuts).
Type: files; Name: "{app}\PureEQ.exe"
Type: files; Name: "{autoprograms}\PureEQ.lnk"
Type: files; Name: "{autodesktop}\PureEQ.lnk"

[Files]
; The whole Release folder: exe, flutter_windows.dll, plugin DLLs and data\.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; In-app update: the app runs this installer with /SILENT /UPDATE=1 and quits;
; reopen it on the new version when the install finishes. runasoriginaluser:
; an all-users update runs elevated, but the app must reopen as the normal
; user, not as administrator.
Filename: "{app}\{#AppExe}"; Flags: nowait runasoriginaluser; Check: IsInAppUpdate

[Code]
const
  SYNCHRONIZE = $00100000;

function OpenProcess(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwProcessId: DWORD): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(hObject: THandle): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';

function IsInAppUpdate: Boolean;
begin
  Result := ExpandConstant('{param:UPDATE|0}') = '1';
end;

{ In-app update: the app starts this installer with /WAITPID=<its pid> and
  then quits. Wait (up to 60 s) for it to be gone before touching any files,
  so the update never races the app's shutdown. }
function InitializeSetup: Boolean;
var
  Pid: Integer;
  Handle: THandle;
begin
  Result := True;
  Pid := StrToIntDef(ExpandConstant('{param:WAITPID|0}'), 0);
  if Pid > 0 then
  begin
    Handle := OpenProcess(SYNCHRONIZE, False, Pid);
    if Handle <> 0 then
    begin
      WaitForSingleObject(Handle, 60000);
      CloseHandle(Handle);
    end;
  end;
end;
