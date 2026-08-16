#preproc ispp
; PREPROCVER is Inno Setup's authoritative compiler version: four bytes for
; major, minor, revision, and build. Fail closed unless ISCC is exactly 6.7.1.0.
#define ExpectedInnoCompilerVersion (6 * 16777216 + 7 * 65536 + 1 * 256)
#if PREPROCVER != ExpectedInnoCompilerVersion
  #error "Voice Dictation requires Inno Setup compiler 6.7.1.0."
#endif

#define AppName "Voice Dictation"
#define AppPublisher "Reeyen"
#ifndef APP_VERSION
  #define APP_VERSION "0.8.0"
#endif
#define AppVersion APP_VERSION

[Setup]
AppId={{0ACD9F61-06B7-4F60-9B4A-0BBD0C10C8C2}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion} beta
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Voice Dictation
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UsePreviousTasks=yes
PrivilegesRequired=lowest
MinVersion=10.0.22621
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=..\artifacts\installer
OutputBaseFilename=Voice-Dictation-Windows-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\VoiceDictation.exe
SetupIconFile=..\assets\VoiceDictation.ico
ChangesEnvironment=no
CloseApplications=yes
RestartApplications=no
AppMutex={code:GetAppMutex}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Launch Voice Dictation when I sign in"; GroupDescription: "Startup:"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\publish\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsX64Install
Source: "..\publish\win-arm64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsArm64Install
Source: "..\release\PORTABLE-README.txt"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\DOTNET_THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\VCREDIST-PROVENANCE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall ignoreversion

[Icons]
Name: "{group}\Voice Dictation"; Filename: "{app}\VoiceDictation.exe"
Name: "{autodesktop}\Voice Dictation"; Filename: "{app}\VoiceDictation.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Voice Dictation"; ValueData: """{app}\VoiceDictation.exe"" --background"; Tasks: startup

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Verb: "runas"; StatusMsg: "Installing the Microsoft Visual C++ runtime..."; Flags: shellexec waituntilterminated skipifdoesntexist; Check: VCRedistNeeded
Filename: "{app}\VoiceDictation.exe"; Description: "Launch Voice Dictation"; Flags: nowait skipifdoesntexist; Check: ShouldLaunchAfterSetup

[Code]
function VersionAtLeast(VersionText: string; RequiredMajor: Integer; RequiredMinor: Integer): Boolean;
var
  FirstDot: Integer;
  SecondDot: Integer;
  Major: Integer;
  Minor: Integer;
begin
  Result := False;
  if (Length(VersionText) > 0) and ((VersionText[1] = 'v') or (VersionText[1] = 'V')) then
    Delete(VersionText, 1, 1);
  FirstDot := Pos('.', VersionText);
  if FirstDot <= 1 then Exit;
  Major := StrToIntDef(Copy(VersionText, 1, FirstDot - 1), -1);
  Delete(VersionText, 1, FirstDot);
  SecondDot := Pos('.', VersionText);
  if SecondDot > 1 then
    Minor := StrToIntDef(Copy(VersionText, 1, SecondDot - 1), -1)
  else
    Minor := StrToIntDef(VersionText, -1);
  Result := (Major > RequiredMajor) or
    ((Major = RequiredMajor) and (Minor >= RequiredMinor));
end;

function IsArm64Install: Boolean;
begin
  Result := IsArm64;
end;

function IsX64Install: Boolean;
begin
  Result := (not IsArm64) and Is64BitInstallMode;
end;

function IsVoiceUpdateMode: Boolean;
begin
  Result := CompareText(ExpandConstant('{param:VOICEUPDATE|}'), '1') = 0;
end;

function GetAppMutex(Param: String): String;
begin
  if IsVoiceUpdateMode then
    Result := ''
  else
    Result := 'Local\VoiceDictation.Windows.Singleton';
end;

function UpdateInstallDirectoryIsValid: Boolean;
var
  Requested: String;
  Expected: String;
begin
  Requested := ExpandConstant('{param:UPDATEINSTALLDIR|}');
  Expected := ExpandConstant('{localappdata}\Programs\Voice Dictation');
  Result := (CompareText(Requested, Expected) = 0) and
    (CompareText(ExpandConstant('{param:DIR|}'), Expected) = 0);
end;

function GetParentPid: Cardinal;
begin
  Result := StrToIntDef(ExpandConstant('{param:PARENTPID|0}'), 0);
end;

function OpenProcess(DesiredAccess: Cardinal; InheritHandle: Boolean; ProcessId: Cardinal): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function WaitForVoiceUpdateParent: Boolean;
var
  Pid: Cardinal;
  ProcessHandle: THandle;
begin
  Result := True;
  if not IsVoiceUpdateMode then Exit;
  Pid := GetParentPid;
  if Pid = 0 then begin Result := False; Exit; end;
  ProcessHandle := OpenProcess($00100000, False, Pid);
  if ProcessHandle = 0 then Exit;
  try
    Result := WaitForSingleObject(ProcessHandle, 120000) = 0;
  finally
    CloseHandle(ProcessHandle);
  end;
end;

function InitializeSetup: Boolean;
begin
  Result := IsX64Install or IsArm64Install;
  if not Result then begin
    MsgBox('Voice Dictation requires native Windows 11 x64 or ARM64 (build 22621 or later).', mbError, MB_OK);
    Exit;
  end;
  if not IsVoiceUpdateMode then Exit;
  Result := UpdateInstallDirectoryIsValid and WaitForVoiceUpdateParent;
  if not Result then
    MsgBox('The update could not safely close the existing Voice Dictation install. Your current version was left unchanged.', mbError, MB_OK);
end;

var
  UpdateSucceeded: Boolean;

function ShouldLaunchAfterSetup: Boolean;
begin
  Result := IsVoiceUpdateMode or (not WizardSilent);
end;

function VCRedistNeeded: Boolean;
var
  Installed: Cardinal;
  VersionText: string;
  X64Ready: Boolean;
  Arm64Ready: Boolean;
begin
  Result := True;
  X64Ready := False;
  Arm64Ready := False;
  if RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed', Installed) then
  begin
    if (Installed = 1) and RegQueryStringValue(HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Version', VersionText) then
    begin
      X64Ready := (Installed = 1) and VersionAtLeast(VersionText, 14, 30);
    end;
  end;
  if IsArm64 then begin
    Installed := 0;
    VersionText := '';
    if RegQueryDWordValue(HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\arm64',
      'Installed', Installed) and RegQueryStringValue(HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\arm64',
      'Version', VersionText) then
      Arm64Ready := (Installed = 1) and VersionAtLeast(VersionText, 14, 30);
    Result := not (X64Ready and Arm64Ready);
  end else begin
    Result := not X64Ready;
  end;
end;

procedure RemoveOwnedStartupValue;
var
  CurrentValue: string;
  ExpectedValue: string;
begin
  ExpectedValue := '"' + ExpandConstant('{app}\VoiceDictation.exe') + '" --background';
  if RegQueryStringValue(HKCU,
     'Software\Microsoft\Windows\CurrentVersion\Run',
     'Voice Dictation', CurrentValue) and
     (CurrentValue = ExpectedValue) then
    RegDeleteValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Run',
      'Voice Dictation');
end;

procedure CurUninstallStepChanged(UninstallStep: TUninstallStep);
begin
  if UninstallStep = usUninstall then
    RemoveOwnedStartupValue;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and IsVoiceUpdateMode then
    UpdateSucceeded := True;
end;

procedure DeinitializeSetup;
var
  ResultCode: Integer;
  ExistingApp: String;
begin
  if IsVoiceUpdateMode and (not UpdateSucceeded) then begin
    ExistingApp := ExpandConstant('{param:UPDATEINSTALLDIR|}') + '\VoiceDictation.exe';
    if FileExists(ExistingApp) then
      Exec(ExistingApp, '--background', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
  end;
end;
