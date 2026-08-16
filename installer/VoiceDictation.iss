#define AppName "Voice Dictation"
#define AppPublisher "Reeyen"
#ifndef APP_VERSION
  #define APP_VERSION "0.7.0"
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
PrivilegesRequired=lowest
MinVersion=10.0.22621
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
OutputDir=..\artifacts\installer
OutputBaseFilename=Voice-Dictation-Windows-x64-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\VoiceDictation.exe
SetupIconFile=..\assets\VoiceDictation.ico
ChangesEnvironment=no
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Launch Voice Dictation when I sign in"; GroupDescription: "Startup:"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\publish\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
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
Filename: "{app}\VoiceDictation.exe"; Description: "Launch Voice Dictation"; Flags: nowait postinstall skipifsilent

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

function VCRedistNeeded: Boolean;
var
  Installed: Cardinal;
  VersionText: string;
begin
  Result := True;
  if RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed', Installed) then
  begin
    if (Installed = 1) and RegQueryStringValue(HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Version', VersionText) then
    begin
      Result := not VersionAtLeast(VersionText, 14, 30);
    end;
  end;
end;

procedure RemoveOwnedStartupValue;
const
  RunSubkey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunValueName = 'Voice Dictation';
var
  CurrentValue: string;
  ExpectedValue: string;
begin
  ExpectedValue := '"' + ExpandConstant('{app}\VoiceDictation.exe') + '" --background';
  if RegQueryStringValue(HKCU, RunSubkey, RunValueName, CurrentValue) and
     (CurrentValue = ExpectedValue) then
    RegDeleteValue(HKCU, RunSubkey, RunValueName);
end;

procedure CurUninstallStepChanged(UninstallStep: TUninstallStep);
begin
  if UninstallStep = usUninstall then
    RemoveOwnedStartupValue;
end;
