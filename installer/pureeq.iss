; Inno Setup script for the PureEQ Windows installer.
;
; Build the app first, then compile this script:
;   flutter build windows --release
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\pureeq.iss
; Output: dist\PureEQ-Setup-<version>.exe
;
; The version can be overridden from the command line: ISCC /DAppVersion=1.2.0 ...

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "PureEQ"
#define AppExe "PureEQ.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6E3C1F4A-8B2D-4C7E-9A51-2F0D8C3B7E19}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=PureEQ
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=..\dist
OutputBaseFilename=PureEQ-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs per-user without admin rights; the user may choose "all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole Release folder: exe, flutter_windows.dll, plugin DLLs and data\.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; In-app update: PureEQ runs this installer with /SILENT /UPDATE=1 and quits;
; reopen it on the new version when the install finishes.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: IsInAppUpdate

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

{ In-app update: PureEQ starts this installer with /WAITPID=<its pid> and
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
