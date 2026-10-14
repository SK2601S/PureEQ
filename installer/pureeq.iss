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
; All users by default (one UAC prompt): the bundled Equalizer APO is a
; system audio driver and needs admin rights anyway. Older per-user installs
; can still be updated in place (/CURRENTUSER on the command line).
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline dialog
; Close running copies before replacing files. "force": if a copy does not
; close when asked (it hides to the tray instead), end it — otherwise its
; files stay in use and a silent update fails. Settings are saved within
; half a second of any change, so nothing is lost.
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Only offered when Equalizer APO is not installed yet (ticked by default).
Name: "eqapo"; Description: "Install Equalizer APO (free) - needed so SK EQ can change the real sound"; GroupDescription: "Sound engine:"; Check: NeedsEqualizerApo
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Leftovers from when the app was called PureEQ (old exe name and shortcuts).
Type: files; Name: "{app}\PureEQ.exe"
Type: files; Name: "{autoprograms}\PureEQ.lnk"
Type: files; Name: "{autodesktop}\PureEQ.lnk"

[Files]
; The whole Release folder: exe, flutter_windows.dll, plugin DLLs and data\.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundled Equalizer APO (unmodified, GPL v2) + its license and notice.
Source: "redist\EqualizerAPO-x64-1.4.2.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Tasks: eqapo
Source: "redist\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\EqualizerAPO-LICENSE-GPL-2.0.txt"; DestDir: "{app}"; Flags: ignoreversion

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

var
  ApoInstalledNow: Boolean;

function IsInAppUpdate: Boolean;
begin
  Result := ExpandConstant('{param:UPDATE|0}') = '1';
end;

function ApoDll: String;
begin
  Result := ExpandConstant('{commonpf64}\EqualizerAPO\EqualizerAPO.dll');
end;

{ Task check: offer Equalizer APO only if it is not installed. }
function NeedsEqualizerApo: Boolean;
begin
  Result := not FileExists(ApoDll);
end;

{ True while Equalizer APO's Device Selector window is open. }
function DeviceSelectorRunning: Boolean;
var
  Code: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq DeviceSelector.exe" | find /I "DeviceSelector.exe"',
    '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;

{ After SK EQ's files are copied: install Equalizer APO silently, then let
  the user tick their playback devices (Equalizer APO has no automatic way
  to choose devices; doing it by hand-editing the audio registry is risky). }
procedure InstallEqualizerApo;
var
  Code, I: Integer;
  Selector: String;
begin
  WizardForm.StatusLabel.Caption := 'Installing Equalizer APO (sound engine)...';
  if not ShellExec('runas', ExpandConstant('{tmp}\EqualizerAPO-x64-1.4.2.exe'), '/S', '',
                   SW_SHOW, ewWaitUntilTerminated, Code) then
  begin
    if not WizardSilent then
      MsgBox('Equalizer APO could not be installed (' + SysErrorMessage(Code) + ').' + #13#10 +
             'SK EQ will work as a preview; you can install Equalizer APO later from SK EQ.',
             mbError, MB_OK);
    Exit;
  end;
  ApoInstalledNow := FileExists(ApoDll);
  if not ApoInstalledNow then Exit;

  // Its own installer may already have opened the Device Selector.
  Sleep(1500);
  if not DeviceSelectorRunning then
  begin
    Selector := ExpandConstant('{commonpf64}\EqualizerAPO\DeviceSelector.exe');
    if not FileExists(Selector) then
      Selector := ExpandConstant('{commonpf64}\EqualizerAPO\Configurator.exe');
    if not WizardSilent then
      MsgBox('Almost done!' + #13#10#13#10 +
             'In the next window, tick your headphones and speakers, then click OK.' + #13#10 +
             'After that, restart your PC so the sound engine can start.',
             mbInformation, MB_OK);
    ShellExec('runas', Selector, '', '', SW_SHOW, ewWaitUntilTerminated, Code);
  end
  else
  begin
    WizardForm.StatusLabel.Caption := 'Tick your headphones and speakers, then click OK...';
    for I := 1 to 1200 do  { up to 10 minutes }
    begin
      if not DeviceSelectorRunning then Break;
      Sleep(500);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('eqapo') then
    InstallEqualizerApo;
end;

{ Equalizer APO starts working after a restart. }
function NeedRestart: Boolean;
begin
  Result := ApoInstalledNow;
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
