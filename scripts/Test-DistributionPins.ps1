[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Read([string]$path) { Get-Content -LiteralPath (Join-Path $root $path) -Raw }
function Has([string]$text,[string]$needle,[string]$label) { if (-not $text.Contains($needle)) { throw "$label missing: $needle" } }
function HasWhitespaceNormalized([string]$text,[string]$needle,[string]$label) {
    $normalizedText = [regex]::Replace($text, '\s+', ' ').Trim()
    $normalizedNeedle = [regex]::Replace($needle, '\s+', ' ').Trim()
    if (-not $normalizedText.Contains($normalizedNeedle)) { throw "$label missing (whitespace-normalized): $needle" }
}
function Lacks([string]$text,[string]$needle,[string]$label) { if ($text.Contains($needle)) { throw "$label contains forbidden: $needle" } }
$workflow = Read '.github\workflows\windows-distribution.yml'
$macWorkflow = Read '.github\workflows\macos-distribution.yml'
$validator = Read 'scripts\Validate-Distribution.ps1'
$macValidator = Read 'scripts\Validate-MacDistribution.sh'
$macContractTest = Read 'scripts\Test-MacDistributionContract.sh'
$installer = Read 'installer\VoiceDictation.iss'
$portableReadme = Read 'release\PORTABLE-README.txt'
$thirdPartyNotices = Read 'THIRD_PARTY_NOTICES.md'
$readme = Read 'README.md'
$vcPin = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
foreach ($pin in @('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683','actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9','actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02','actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093','dotnet-version: 10.0.400','windows-2025','windows-11-arm','windows-2022','Voice-Dictation-Windows-${{ inputs.version }}-Setup.exe','Voice-Dictation-Windows-x64-${{ inputs.version }}-Portable.zip','Voice-Dictation-Windows-arm64-${{ inputs.version }}-Portable.zip')) { Has $workflow $pin 'Workflow' }
foreach ($needle in @('validate-x64','validate-server-2022-x64','CandidateRoot ./candidate','-Mode Package -Architecture x64 -MinimumWindowsBuild 19045','-Mode Native -Architecture x64','-Mode Native -Architecture arm64','-MinimumWindowsBuild 19045','X64_TESTS_SHA','needs: [package-x64, validate-x64, validate-arm64, validate-server-2022-x64]')) { Has $workflow $needle 'Workflow' }
foreach ($needle in @('workflow_dispatch:','macos-15-intel','macos-15','app_zip_sha256','validation_bundle_sha256','EXPECTED_ARCHITECTURE: x86_64','EXPECTED_ARCHITECTURE: arm64','Validate-MacDistribution.sh')) { Has $macWorkflow $needle 'macOS workflow' }
foreach ($needle in @('default: 0.9.0','default: bootstrap-v0.9.0','x64_portable_sha256','arm64_portable_sha256','x64_platform_tests_sha256','arm64_platform_tests_sha256')) { Has $workflow $needle 'Workflow v0.9 dispatch contract' }
foreach ($needle in @('default: 0.9.0','default: bootstrap-v0.9.0','app_zip_sha256','validation_bundle_sha256')) { Has $macWorkflow $needle 'macOS workflow v0.9 dispatch contract' }
foreach ($needle in @('Voice-Dictation-macOS-$VERSION.zip','Voice-Dictation-macOS-Universal-Validation-$VERSION.zip','bootstrap release must remain a draft','Voice-Dictation-MacValidation/VoiceDictationMacValidation','Voice-Dictation-MacValidation/run-mac-validation.sh','VALIDATED_ASSET_URLS','validated_asset_urls[expected] = raw_url','asset_urls = json.load(handle)','re.fullmatch','parsed.netloc','parsed.hostname','parsed.username','parsed.password','parsed.port','parsed.params','parsed.query','parsed.fragment','exact same-repository GitHub release-asset URL','VD_MAC_VALIDATION_BEGIN','VD_MAC_VALIDATION_MODEL_PRELOAD','VD_MAC_VALIDATION_MODEL','VD_MAC_VALIDATION_GEOMETRY','VD_MAC_VALIDATION_CASE','VD_MAC_VALIDATION_SILENCE','VD_MAC_VALIDATION_CANCEL','capture_mode','capture_chunk_seconds','capture_overlap_seconds','maximum_rss_megabytes','at least four decimal places','maximum_latency = 20.0 if expected_architecture == "x86_64" else 12.0','VALIDATION_MAX_LATENCY_SECONDS=20','VALIDATION_MAX_LATENCY_SECONDS=12','x86_64) VALIDATION_MAX_LATENCY_SECONDS=20','arm64) VALIDATION_MAX_LATENCY_SECONDS=12','HOST_ARCHITECTURE="$(uname -m)"','sysctl.proc_translated','must not run under Rosetta translation','--max-wer 0.35','Universal 2','codesign --verify --deep --strict')) { Has $macValidator $needle 'macOS validator' }
foreach ($needle in @('macos-15-intel','runs-on: macos-15','app_zip_sha256','validation_bundle_sha256','binary-only validation','assert_universal2','bash -n')) { Has $macContractTest $needle 'macOS contract test' }
foreach ($needle in @('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683','contents: write')) { Has $macWorkflow $needle 'macOS workflow' }
Lacks $macWorkflow 'contents: read' 'macOS workflow'
Lacks $macWorkflow 'swift test' 'macOS workflow'
Lacks $macWorkflow 'xcodebuild' 'macOS workflow'
Lacks $macWorkflow 'Voice-Dictation.git' 'macOS workflow'
Lacks $macValidator 'VALIDATION_MAX_LATENCY_SECONDS=5' 'macOS validator'
Lacks $macValidator 'swift test' 'macOS validator'
Lacks $macValidator 'xcodebuild' 'macOS validator'
Lacks $macValidator 'Voice-Dictation.git' 'macOS validator'
Lacks $workflow 'Package and validate native x64' 'Workflow'
Lacks $workflow 'run_platform_tests' 'Workflow'
Lacks $workflow 'windows-latest' 'Workflow'
foreach ($needle in @("'0.8.0' = [pscustomobject]@{", "'0.9.0' = [pscustomobject]@{",$vcPin,'Assert-NativeHost','MinimumWindowsBuild','19045','0xAA64','0x8664','Voice-Dictation-Windows-$Version-Setup.exe','windows-universal','windows-arm64','windows-x64','Get-ValidatedCandidateArtifacts','Invoke-PinnedInference','Invoke-WindowsExecutableTimed','Timed inference measurements','VOICE_DICTATION_UIA_FIXTURE','portable.flag','runtimes\win-arm64','runtimes\noavx\win-x64','ExecuteTests','-ExecuteTests:($Mode -eq ''Native'')','archive structure, hash, and PE metadata passed','function Get-VoiceBackgroundProcesses','function Invoke-UpdateModeSmoke','Assert-PlatformTestsArchiveBoundary','nested ZIP archives','(?:^|/)[^/]*\.zip(?:/|$)','foreign native test tooling','\.(?:so|dylib|a|o)$','''testhost.dll''','/VOICEUPDATE=1','/UPDATEINSTALLDIR=','/PARENTPID=','WaitForExit(180000)','--background','Get-CimInstance -ClassName Win32_Process','function Clear-WorkflowTokens','$script:GitHubToken = $null','GITHUB_API_TOKEN','ACTIONS_RUNTIME_TOKEN','RUNNER_TOKEN','inferenceTimeoutMilliseconds = 300000','WaitForExit($inferenceTimeoutMilliseconds)','Stop-Process -Id $process.Id -Force')) { Has $validator $needle 'Validator' }
$expectedExecutableGuard = '[System.IO.Path]::GetFileName($_.Name) -cne ''VoiceDictation.exe'''
if (-not $validator.Contains($expectedExecutableGuard)) {
    throw "Validator missing exact executable guard: $expectedExecutableGuard"
}
Has $validator 'exact asset name for the selected version' 'Validator'
Lacks $validator 'versioned v0.8 name' 'Validator'
$timedStart = $validator.IndexOf('function Invoke-WindowsExecutableTimed', [StringComparison]::Ordinal)
$timedEnd = $validator.IndexOf('function Get-VoiceBackgroundProcesses', [StringComparison]::Ordinal)
if ($timedStart -lt 0 -or $timedEnd -le $timedStart) { throw 'Timed inference helper boundaries are missing.' }
$timedBody = $validator.Substring($timedStart, $timedEnd - $timedStart)
if ($timedBody.Contains(' -Wait')) { throw 'Timed inference helper must not use unbounded Start-Process -Wait.' }
$nativeScrubAnchor = $validator.IndexOf('# The built-in token is needed', [StringComparison]::Ordinal)
if ($nativeScrubAnchor -lt 0) { throw 'Windows validator auth scrub anchor is missing.' }
$nativeScrub = $validator.IndexOf('    Clear-WorkflowTokens', $nativeScrubAnchor, [StringComparison]::Ordinal)
$nativeTests = $validator.IndexOf('Assert-PlatformTestsArchive -Path $PlatformTestsZipPath', $nativeScrubAnchor, [StringComparison]::Ordinal)
$nativeInstaller = $validator.IndexOf('Invoke-InstallerSmoke $setupPath', $nativeScrubAnchor, [StringComparison]::Ordinal)
$nativeInference = $validator.IndexOf('Invoke-PinnedInference $portableExe', $nativeScrubAnchor, [StringComparison]::Ordinal)
if ($nativeScrub -lt 0 -or $nativeTests -lt 0 -or $nativeInstaller -lt 0 -or $nativeInference -lt 0 -or $nativeScrub -ge $nativeTests -or $nativeScrub -ge $nativeInstaller -or $nativeScrub -ge $nativeInference) {
    throw 'Windows validator must scrub auth before any downloaded test host, installer, or inference process.'
}
foreach ($needle in @('#define APP_VERSION "0.9.0"','#ifndef ARTIFACT_ROOT','MinVersion=10.0.19045','ArchitecturesAllowed=x64compatible arm64','ArchitecturesInstallIn64BitMode=x64compatible arm64','DisableDirPage=yes','OutputBaseFilename=Voice-Dictation-Windows-{#AppVersion}-Setup','Check: IsX64Install','Check: IsArm64Install','AppMutex={code:GetAppMutex}','GetLastErrorCode: Cardinal','external ''GetLastError@kernel32.dll stdcall'';','Result := GetLastErrorCode = 87','Result := (not IsVoiceUpdateMode) and (not WizardSilent);','ExistingApp := ExpandConstant(''{app}\VoiceDictation.exe'');','Result := Exec(ExistingApp, ''--background'', '''', SW_SHOWNORMAL, ewNoWait, ResultCode);','UpdateSucceeded := LaunchInstalledApplication;','if not UpdateSucceeded then','Voice Dictation could not be started automatically.')) { Has $installer $needle 'Installer' }
Lacks $installer 'Result := IsVoiceUpdateMode or (not WizardSilent);' 'Installer'
foreach ($needle in @('Windows 10 version 22H2 or newer (build 19045+)','Windows x64 or ARM64','Portable copies never overwrite themselves','32-bit Windows is not supported')) { Has $portableReadme $needle 'Portable README' }
foreach ($needle in @('self-contained x64 and ARM64 beta','Whisper.net 1.9.1')) { Has $thirdPartyNotices $needle 'Third-party notices' }

# Keep the archive-boundary cases explicit so a future validator edit cannot
# accidentally allow foreign coverage payloads or a nested archive while still
# accepting the native Whisper runtime paths that the test bundle requires.
$nestedArchivePattern = '(?i)(?:^|/)[^/]*\.zip(?:/|$)'
$foreignNativePattern = '(?i)(?:(?:^|/)(?:alpine|macos|osx|ubuntu|linux|freebsd|x86|x64|arm64|CodeCoverage)(?:/|$)|(?:^|/)(?:MicrosoftInstrumentationEngine|msdia|covrun|libCoverage|libInstrumentation)|\.(?:so|dylib|a|o)$)'
$archiveBoundaryFixtures = @(
    [pscustomobject]@{ Name = 'payload.zip'; Reject = $true }
    [pscustomobject]@{ Name = 'nested/payload.zip/file.txt'; Reject = $true }
    [pscustomobject]@{ Name = 'x86/MicrosoftInstrumentationEngine_x86.dll'; Reject = $true }
    [pscustomobject]@{ Name = 'macos/x64/libInstrumentationEngine.dylib'; Reject = $true }
    [pscustomobject]@{ Name = 'alpine/x64/libCoverageInstrumentationMethod.so'; Reject = $true }
    [pscustomobject]@{ Name = 'CodeCoverage/amd64/CodeCoverage.exe'; Reject = $true }
    [pscustomobject]@{ Name = 'helper.exe'; Reject = $true }
    [pscustomobject]@{ Name = 'testhost.exe'; Reject = $true }
    [pscustomobject]@{ Name = 'VoiceDictation.exe'; Reject = $false }
    [pscustomobject]@{ Name = 'testhost.dll'; Reject = $false }
    [pscustomobject]@{ Name = 'runtimes/win-x64/whisper.dll'; Reject = $false }
    [pscustomobject]@{ Name = 'runtimes/noavx/win-x64/whisper.dll'; Reject = $false }
    [pscustomobject]@{ Name = 'runtimes/win-arm64/whisper.dll'; Reject = $false }
)
foreach ($fixture in $archiveBoundaryFixtures) {
    $reject = ($fixture.Name -match $nestedArchivePattern) -or
        ($fixture.Name -match $foreignNativePattern) -or
        ($fixture.Name -match '(?i)\.exe$' -and [System.IO.Path]::GetFileName($fixture.Name) -cne 'VoiceDictation.exe')
    if ($reject -ne $fixture.Reject) {
        throw "Platform.Tests archive-boundary fixture '$($fixture.Name)' expected Reject=$($fixture.Reject), got Reject=$reject."
    }
}
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
foreach ($needle in @('Windows 10 22H2 x64/ARM64','Windows 11 x64/ARM64','windows-11-arm','windows-2025','0.8.0','0.9.0','x64_portable_sha256','arm64_portable_sha256')) { Has $readme $needle 'README' }
# Preserve the exact contract while allowing the sentence to wrap across lines.
# This guards the failure mode where README formatting inserts a newline inside
# the phrase without allowing altered wording to satisfy the check.
HasWhitespaceNormalized $readme 'does not accept arbitrary asset-name inputs' 'README'
foreach ($needle in @('Windows Server 2022 x64 build 20348','validator machine-readable')) { Has $readme $needle 'README' }
Lacks $readme "worker's machine-readable" 'README'
Lacks $readme 'Windows on ARM64' 'README'
Write-Host 'Distribution dual-architecture pin and provenance checks passed.'
