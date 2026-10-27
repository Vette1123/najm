#define AppName "Najm"
; AppId is Inno Setup's upgrade identity (registry-only, never shown to
; users). src/os/windows.zig reads its "_is1" uninstall key.
#define AppId "io.github.vette1123.najm"
#define AppUserModelId "io.github.vette1123.najm"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif
#ifndef PackageArch
  #define PackageArch "x64"
#endif
#ifndef StageDir
  #error StageDir must be defined on the ISCC command line.
#endif
#ifndef OutputDir
  #error OutputDir must be defined on the ISCC command line.
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppPublisher=Mohamed Gado
AppPublisherURL=https://github.com/Vette1123/najm
AppSupportURL=https://github.com/Vette1123/najm/issues
AppUpdatesURL=https://github.com/Vette1123/najm/releases
DefaultDirName={autopf}\Najm
DefaultGroupName=Najm
DisableProgramGroupPage=yes
LicenseFile={#StageDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=najm-{#MyAppVersion}-windows-{#PackageArch}-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
#if PackageArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
ChangesAssociations=yes
; Setup asks Restart Manager to close what holds the files it replaces. The
; bundled OpenConsole.exe runs once per pane as a headless ConPTY host, and
; Restart Manager classes it RmUnknownApp, which only a forced shutdown can
; close: with it registered, every non-forced RmShutdown failed with 351 in
; under 100 ms before Najm saw any message, and Setup aborted (exit 5 under
; /SUPPRESSMSGBOXES). It exits with Najm (measured: no OpenConsole child
; survived once Restart Manager had closed Najm), so leaving it out still
; frees the file. najm.exe, conpty.dll and the handoff proxy stay registered.
; Needs Inno Setup 6.4.2 or later. Keep CloseApplications off "force": a
; forced close kills the programs running in Najm's terminals.
CloseApplications=yes
CloseApplicationsFilterExcludes=OpenConsole.exe
RestartApplications=yes
UninstallDisplayIcon={app}\najm.exe
SetupIconFile={#SourceDir}\dist\windows\noctty.ico
VersionInfoVersion={#MyAppVersion}
VersionInfoTextVersion={#MyAppVersion}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoCompany=Mohamed Gado
VersionInfoDescription=Najm Setup
VersionInfoProductName=Najm
VersionInfoOriginalFileName=najm-{#MyAppVersion}-windows-{#PackageArch}-setup.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
; The recursive stage rule includes the bundled ConPTY pair and its license.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Always clear a previously bundled ConPTY before staging this package.
Type: files; Name: "{app}\conpty.dll"
Type: files; Name: "{app}\OpenConsole.exe"
Type: files; Name: "{app}\LICENSE-conpty.txt"
; Remove pre-rename WingHostty binaries and shortcuts left behind when an
; existing install upgrades in-place (same AppId, new file names).
Type: files; Name: "{app}\winghostty.exe"
Type: files; Name: "{app}\winghostty.com"
Type: files; Name: "{group}\winghostty.lnk"
Type: files; Name: "{group}\Uninstall winghostty.lnk"
Type: files; Name: "{autodesktop}\winghostty.lnk"

[Icons]
; AppUserModelToastActivatorCLSID is the toast activator registered under
; [Registry] below (src/apprt/win32_toast_activator.zig, clsid_text): Action
; Center hands a click on a Najm toast to that class.
Name: "{group}\Najm"; Filename: "{app}\najm.exe"; AppUserModelID: "{#AppUserModelId}"; AppUserModelToastActivatorCLSID: "8CA0641E-900B-47D2-8E71-58290BD54BDA"
Name: "{group}\Uninstall Najm"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Najm"; Filename: "{app}\najm.exe"; Tasks: desktopicon; AppUserModelID: "{#AppUserModelId}"; AppUserModelToastActivatorCLSID: "8CA0641E-900B-47D2-8E71-58290BD54BDA"

[Registry]
Root: HKLM; Subkey: "Software\Classes\CLSID\{{33368C6F-D328-410C-B225-26DC9F12C728}"; ValueType: string; ValueName: ""; ValueData: "Najm Terminal Handoff"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\CLSID\{{33368C6F-D328-410C-B225-26DC9F12C728}\LocalServer32"; ValueType: string; ValueName: ""; ValueData: """{app}\najm.exe"""
Root: HKLM; Subkey: "Software\Classes\CLSID\{{1D349824-21FB-46C7-ACF3-746EDC991D52}"; ValueType: string; ValueName: ""; ValueData: "Najm Terminal Handoff Proxy/Stub"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\CLSID\{{1D349824-21FB-46C7-ACF3-746EDC991D52}\InprocServer32"; ValueType: string; ValueName: ""; ValueData: "{app}\noctty-terminal-handoff-proxy.dll"
Root: HKLM; Subkey: "Software\Classes\CLSID\{{1D349824-21FB-46C7-ACF3-746EDC991D52}\InprocServer32"; ValueType: string; ValueName: "ThreadingModel"; ValueData: "Both"
; Shared Interface\{IID}\ProxyStubClsid32 values are registered per-user by
; +register-default-terminal so their prior values can be restored safely.

; The toast activator. COM starts this command (and appends -Embedding) when
; a toast is clicked in Action Center and no running Najm registered the
; class; a running installed copy registers it itself. The per-user
; CustomActivator value that points the AUMID here is written by the app
; (win32_aumid.zig) and removed at uninstall (CurUninstallStepChanged).
Root: HKA; Subkey: "Software\Classes\CLSID\{{8CA0641E-900B-47D2-8E71-58290BD54BDA}"; ValueType: string; ValueName: ""; ValueData: "Najm Toast Activator"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\CLSID\{{8CA0641E-900B-47D2-8E71-58290BD54BDA}\LocalServer32"; ValueType: string; ValueName: ""; ValueData: """{app}\najm.exe"" -ToastActivated"

Root: HKA; Subkey: "Software\Classes\Directory\shell\najm"; ValueType: string; ValueName: ""; ValueData: "Open Najm here"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Directory\shell\najm"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\najm.exe"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Directory\shell\najm\command"; ValueType: string; ValueName: ""; ValueData: "{code:ShellMenuCommand}"; Flags: uninsdeletevalue uninsdeletekeyifempty

Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\najm"; ValueType: string; ValueName: ""; ValueData: "Open Najm here"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\najm"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\najm.exe"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\najm\command"; ValueType: string; ValueName: ""; ValueData: "{code:ShellMenuCommand}"; Flags: uninsdeletevalue uninsdeletekeyifempty

Root: HKA; Subkey: "Software\Classes\Drive\shell\najm"; ValueType: string; ValueName: ""; ValueData: "Open Najm here"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Drive\shell\najm"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\najm.exe"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\Drive\shell\najm\command"; ValueType: string; ValueName: ""; ValueData: "{code:ShellMenuCommand}"; Flags: uninsdeletevalue uninsdeletekeyifempty

[Run]
; Both entries start Najm through Explorer, which runs the file as the
; logged-on user's shell and so never elevated. runasoriginaluser would not be
; enough on its own: the Inno Setup help says it "is the default behavior when
; the postinstall flag is used", but also that it has no effect when Setup was
; started with "Run as administrator" or from an already-elevated process, and
; then "Launch Najm" would open an Administrator terminal. It is kept anyway
; for a Setup that was started the ordinary way.
Filename: "{win}\explorer.exe"; Parameters: """{app}\najm.exe"""; Description: "Launch Najm"; Flags: nowait postinstall skipifsilent runasoriginaluser
; The in-app Install quits Najm and runs this Setup silently with
; /RELAUNCH=1, so nothing else starts Najm again: /RESTARTAPPLICATIONS only
; restarts what Restart Manager closed and registered for a restart, Najm has
; already exited by then, and another Najm process does not register while
; this Setup runs.
; Install starts Setup with ShellExecute "runas", the case where
; runasoriginaluser does nothing, hence Explorer here too.
Filename: "{win}\explorer.exe"; Parameters: """{app}\najm.exe"""; Flags: nowait runasoriginaluser; Check: RelaunchAfterSilentSetup

[Code]
{ True for the silent apply that Najm starts from its update notice, which
  passes /RELAUNCH=1. A silent install started any other way (WinGet,
  Chocolatey, a script) does not pass it, so this entry does not start Najm
  there. RestartApplications does instead, when the Najm that owns the saved
  session agreed to close: it registers for Setup's restart while agreeing.
  Setup restarts applications after the [Run] entries and before the finished
  page, so in a wizard run a "Launch Najm" left checked starts Najm a
  second time, which opens one more window. }
function RelaunchAfterSilentSetup(): Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

function OwnsDefaultTerminalRegistration(): Boolean;
var
  RegisteredCommand: String;
  RegisteredProxy: String;
  ExpectedCommand: String;
  ExpectedProxy: String;
begin
  ExpectedCommand := '"' + ExpandConstant('{app}\najm.exe') + '"';
  ExpectedProxy := ExpandConstant('{app}\noctty-terminal-handoff-proxy.dll');
  Result :=
    RegQueryStringValue(
      HKCU,
      'Software\Classes\CLSID\{33368C6F-D328-410C-B225-26DC9F12C728}\LocalServer32',
      '',
      RegisteredCommand) and
    (CompareText(RegisteredCommand, ExpectedCommand) = 0) and
    RegQueryStringValue(
      HKCU,
      'Software\Classes\CLSID\{1D349824-21FB-46C7-ACF3-746EDC991D52}\InprocServer32',
      '',
      RegisteredProxy) and
    (CompareText(RegisteredProxy, ExpectedProxy) = 0);
end;

function ShellMenuCommand(Param: String): String;
var
  ExePath: String;
begin
  ExePath := ExpandConstant('{app}\najm.exe');
  StringChangeEx(ExePath, '%', '%%', True);
  Result := AddQuotes(ExePath) + ' --single-instance=false --working-directory="%V\."';
end;

{ The uninstalling user's AUMID registration names the toast activator whose
  class key this uninstall removes. Without the class, a click on a toast
  from a portable copy left behind would ask COM for a server that is gone.
  Only a value naming this activator is removed: the rest of the key is
  shared with portable copies. Other users' values are theirs. }
procedure RemoveToastActivatorValue();
var
  Registered: String;
begin
  if RegQueryStringValue(HKCU, 'Software\Classes\AppUserModelId\{#AppUserModelId}', 'CustomActivator', Registered) and
    (CompareText(Registered, '{8CA0641E-900B-47D2-8E71-58290BD54BDA}') = 0) then
    RegDeleteValue(HKCU, 'Software\Classes\AppUserModelId\{#AppUserModelId}', 'CustomActivator');
end;

{ Drop the uninstalling user's default-terminal selection before the files go
  away. Without this, HKCU keeps pointing DelegationTerminal at Najm's CLSID
  and the shared Interface proxy mappings at the deleted DLL, so every console
  launch fails activation and silently falls back to conhost. Other users'
  selections are theirs to unregister. The ownership check preserves a newer
  registration made by another installed/portable copy.

  This is deliberately code and not an [UninstallRun] entry with a Check:
  Inno Setup evaluates an [UninstallRun] Check while INSTALLING, so on a fresh
  install (nothing registered yet) it returned False and the entry was never
  recorded in the uninstall log, and uninstall then left Najm registered.
  Measured with a throwaway installer: the Check ran once, at install time,
  and never at uninstall. CurUninstallStepChanged runs in the uninstaller,
  before the files are removed. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExePath: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  RemoveToastActivatorValue();
  ExePath := ExpandConstant('{app}\najm.exe');
  if not (FileExists(ExePath) and OwnsDefaultTerminalRegistration()) then
    Exit;
  { The uninstall goes on either way, but a registration left pointing at the
    removed files makes every console launch fall back to conhost, so say so. }
  if not Exec(ExePath, '+unregister-default-terminal', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    or (ResultCode <> 0) then
  begin
    Log('+unregister-default-terminal did not finish: result ' + IntToStr(ResultCode));
    { Only an attended uninstall gets the box: /SILENT and /VERYSILENT without
      /SUPPRESSMSGBOXES would otherwise wait for a click nobody can give. }
    if not UninstallSilent then
      MsgBox(
        'Najm could not remove its default terminal registration, so Windows may keep trying to start it after it is uninstalled.' + #13#10#13#10 +
        'To clear it, reinstall Najm, run "Najm +unregister-default-terminal", and uninstall again, or pick another default terminal in Windows Settings.',
        mbInformation, MB_OK);
  end;
end;
