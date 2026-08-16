[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Read([string]$path) { Get-Content -LiteralPath (Join-Path $root $path) -Raw }
function Has([string]$text,[string]$needle,[string]$label) { if (-not $text.Contains($needle)) { throw "$label missing: $needle" } }
function Lacks([string]$text,[string]$needle,[string]$label) { if ($text.Contains($needle)) { throw "$label contains forbidden: $needle" } }
$workflow = Read '.github\workflows\windows-distribution.yml'
$macWorkflow = Read '.github\workflows\macos-distribution.yml'
$validator = Read 'scripts\Validate-Distribution.ps1'
$macValidator = Read 'scripts\Validate-MacDistribution.sh'
$macContractTest = Read 'scripts\Test-MacDistributionContract.sh'
$installer = Read 'installer\VoiceDictation.iss'
$readme = Read 'README.md'
$vcPin = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
foreach ($pin in @('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683','actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9','actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02','actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093','dotnet-version: 10.0.400','windows-2025','windows-11-arm','windows-2022','Voice-Dictation-Windows-${{ inputs.version }}-Setup.exe','Voice-Dictation-Windows-x64-${{ inputs.version }}-Portable.zip','Voice-Dictation-Windows-arm64-${{ inputs.version }}-Portable.zip')) { Has $workflow $pin 'Workflow' }
foreach ($needle in @('validate-x64','validate-server-2022-x64','CandidateRoot ./candidate','-Mode Native -Architecture x64','-MinimumWindowsBuild 19045','X64_TESTS_SHA','needs: [package-x64, validate-x64, validate-arm64, validate-server-2022-x64]')) { Has $workflow $needle 'Workflow' }
foreach ($needle in @('workflow_dispatch:','macos-15-intel','macos-15','app_zip_sha256','validation_bundle_sha256','EXPECTED_ARCHITECTURE: x86_64','EXPECTED_ARCHITECTURE: arm64','Validate-MacDistribution.sh')) { Has $macWorkflow $needle 'macOS workflow' }
foreach ($needle in @('Voice-Dictation-macOS-$VERSION.zip','Voice-Dictation-macOS-Universal-Validation-$VERSION.zip','bootstrap release must remain a draft','Voice-Dictation-MacValidation/VoiceDictationMacValidation','Voice-Dictation-MacValidation/run-mac-validation.sh','VD_MAC_VALIDATION_BEGIN','VD_MAC_VALIDATION_MODEL_PRELOAD','VD_MAC_VALIDATION_CASE','VD_MAC_VALIDATION_SILENCE','--max-latency-seconds 5','--max-wer 0.35','Universal 2','codesign --verify --deep --strict')) { Has $macValidator $needle 'macOS validator' }
foreach ($needle in @('macos-15-intel','runs-on: macos-15','app_zip_sha256','validation_bundle_sha256','binary-only validation','assert_universal2','bash -n')) { Has $macContractTest $needle 'macOS contract test' }
foreach ($needle in @('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683','contents: read')) { Has $macWorkflow $needle 'macOS workflow' }
Lacks $macWorkflow 'swift test' 'macOS workflow'
Lacks $macWorkflow 'xcodebuild' 'macOS workflow'
Lacks $macWorkflow 'Voice-Dictation.git' 'macOS workflow'
Lacks $macValidator 'swift test' 'macOS validator'
Lacks $macValidator 'xcodebuild' 'macOS validator'
Lacks $macValidator 'Voice-Dictation.git' 'macOS validator'
Lacks $workflow 'Package and validate native x64' 'Workflow'
Lacks $workflow 'run_platform_tests' 'Workflow'
Lacks $workflow 'windows-latest' 'Workflow'
foreach ($needle in @("'0.8.0' = [pscustomobject]@{",$vcPin,'Assert-NativeHost','MinimumWindowsBuild','19045','0xAA64','0x8664','Voice-Dictation-Windows-$Version-Setup.exe','windows-universal','windows-arm64','windows-x64','Get-ValidatedCandidateArtifacts','Invoke-PinnedInference','Invoke-WindowsExecutableTimed','Timed inference measurements','VOICE_DICTATION_UIA_FIXTURE','portable.flag','runtimes\win-arm64','runtimes\noavx\win-x64','ExecuteTests','-ExecuteTests:($Mode -eq ''Native'')','archive structure, hash, and PE metadata passed','function Get-VoiceBackgroundProcesses','function Invoke-UpdateModeSmoke','/VOICEUPDATE=1','/UPDATEINSTALLDIR=','/PARENTPID=','WaitForExit(180000)','--background','Get-CimInstance -ClassName Win32_Process')) { Has $validator $needle 'Validator' }
foreach ($needle in @('#define APP_VERSION "0.8.0"','ArchitecturesAllowed=x64compatible arm64','ArchitecturesInstallIn64BitMode=x64compatible arm64','DisableDirPage=yes','OutputBaseFilename=Voice-Dictation-Windows-{#AppVersion}-Setup','Check: IsX64Install','Check: IsArm64Install','AppMutex={code:GetAppMutex}','GetLastError@kernel32.dll stdcall','Result := GetLastError = 87','Result := (not IsVoiceUpdateMode) and (not WizardSilent);','ExistingApp := ExpandConstant(''{app}\VoiceDictation.exe'');','Result := Exec(ExistingApp, ''--background'', '''', SW_SHOWNORMAL, ewNoWait, ResultCode);','UpdateSucceeded := LaunchInstalledApplication;','if not UpdateSucceeded then','Voice Dictation could not be started automatically.')) { Has $installer $needle 'Installer' }
Lacks $installer 'Result := IsVoiceUpdateMode or (not WizardSilent);' 'Installer'
if ([regex]::IsMatch($installer, '(?ms)procedure\s+DeinitializeSetup\s*;\s*var\b')) {
    throw 'Installer uses an empty procedure-local var block.'
}
Lacks $installer 'if ProcessHandle = 0 then Exit;' 'Installer'

$archiveGuard = $validator.IndexOf('if (-not $ExecuteTests) {', [StringComparison]::Ordinal)
$dotnetLookup = $validator.IndexOf('Get-Command dotnet.exe', [StringComparison]::Ordinal)
if ($archiveGuard -lt 0 -or $dotnetLookup -lt 0 -or $archiveGuard -ge $dotnetLookup) {
    throw 'Validator must guard package-mode Platform.Tests execution before looking up dotnet.exe.'
}
$packageStart = $validator.IndexOf('    Clear-OutputRoot $output', [StringComparison]::Ordinal)
$installerSmoke = $validator.IndexOf('Invoke-InstallerSmoke $setupPath', [StringComparison]::Ordinal)
$inference = $validator.IndexOf('Invoke-PinnedInference $portableExe', [StringComparison]::Ordinal)
if ($packageStart -lt 0 -or $installerSmoke -lt 0 -or $inference -lt 0 -or $installerSmoke -ge $packageStart -or $inference -ge $packageStart) {
    throw 'Package mode must not execute the downloaded installer or portable inference; those calls belong to Native mode.'
}
Lacks $validator 'Invoke-InstallerSmoke $setupOut' 'Validator'
foreach ($needle in @('function Wait-ForInstallRootRemoval','Wait-ForInstallRootRemoval $installRoot','Wait-ForInstallRootRemoval $canonicalInstallRoot','15000')) { Has $validator $needle 'Validator' }
if ([regex]::Matches($validator, 'Wait-ForInstallRootRemoval \$').Count -ne 4) {
    throw 'Each native installer smoke uninstall must wait for its isolated install root to disappear.'
}
foreach ($needle in @('Windows 11 x64 and ARM64','windows-11-arm','windows-2025','0.8.0')) { Has $readme $needle 'README' }
Lacks $readme 'Windows on ARM64' 'README'
Write-Host 'Distribution dual-architecture pin and provenance checks passed.'
