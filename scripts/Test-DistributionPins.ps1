[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-Contains([string]$Text, [string]$Needle, [string]$Label) {
    if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw "$Label is missing required text: $Needle"
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Label) {
    if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw "$Label contains forbidden text: $Needle"
    }
}

$workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\windows-distribution.yml') -Raw
$validator = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Validate-Distribution.ps1') -Raw
$releaseSelection = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\ReleaseSelection.ps1') -Raw
$releaseSelectionTest = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Test-ReleaseSelection.ps1') -Raw
$installer = Get-Content -LiteralPath (Join-Path $repoRoot 'installer\VoiceDictation.iss') -Raw
$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw

$vcPin = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
Assert-Contains $workflow 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' 'Public workflow'
Assert-Contains $workflow 'actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9' 'Public workflow'
Assert-Contains $workflow 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' 'Public workflow'
Assert-Contains $workflow 'dotnet-version: 10.0.400' 'Public workflow'
Assert-Contains $workflow 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_1/innosetup-6.7.1.exe' 'Public workflow'
Assert-Contains $workflow '4d11e8050b6185e0d49bd9e8cc661a7a59f44959a621d31d11033124c4e8a7b0' 'Public workflow'
Assert-Contains $workflow '10619024' 'Public workflow'
Assert-Contains $workflow 'Pyrsys B.V.' 'Public workflow'
Assert-Contains $workflow 'GITHUB_PATH' 'Public workflow'
Assert-NotContains $workflow 'VersionInfo.FileVersion' 'Public workflow'
Assert-NotContains $workflow 'VersionInfo.ProductVersion' 'Public workflow'
Assert-Contains $workflow 'VOICE_DICTATION_UIA_FIXTURE' 'Public workflow'
Assert-Contains $workflow 'run: ./scripts/Test-ReleaseSelection.ps1' 'Public workflow'
Assert-Contains $workflow 'for example 0.7.1' 'Public workflow'
Assert-Contains $workflow 'default: bootstrap-v0.7.1' 'Public workflow'
Assert-NotContains $workflow 'for example 0.7.0' 'Public workflow'
Assert-NotContains $workflow 'default: bootstrap-v0.7.0' 'Public workflow'
Assert-NotContains $workflow 'choco install' 'Public workflow'
Assert-NotContains $workflow 'artifacts/**' 'Public workflow'
Assert-Contains $workflow 'artifacts/Voice-Dictation-Windows-x64-${{ inputs.version }}-Setup.exe' 'Public workflow'
Assert-Contains $workflow 'artifacts/Voice-Dictation-Windows-x64-${{ inputs.version }}-Portable.zip' 'Public workflow'
Assert-Contains $workflow 'artifacts/SHA256SUMS.json' 'Public workflow'
Assert-Contains $workflow 'artifacts/SHA256SUMS.txt' 'Public workflow'
Assert-Contains $validator $vcPin 'Distribution validator'
Assert-Contains $validator "'0.7.0' = [pscustomobject]@{" 'Distribution validator'
Assert-Contains $validator "'0.7.1' = [pscustomobject]@{" 'Distribution validator'
if ([regex]::Matches($validator, "'0\.7\.[01]' = \[pscustomobject\]@").Count -ne 2) {
    throw 'Distribution validator must contain exactly the reviewed 0.7.0 and 0.7.1 VC++ pins.'
}
$expectedVcFields = @(
    "Sha256 = '$vcPin'"
    "Size = 25635768L"
    "ProductVersion = '14.44.35211.0'"
    "FileVersion = '14.44.35211.0'"
    "ProductName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211'"
    "OriginalFilename = 'VC_redist.x64.exe'"
)
foreach ($field in $expectedVcFields) {
    if ([regex]::Matches($validator, [regex]::Escape($field)).Count -ne 2) {
        throw "The 0.7.0 and 0.7.1 VC++ pins must contain the identical reviewed field twice: $field"
    }
}
Assert-Contains $installer '#define APP_VERSION "0.7.1"' 'Public installer'
Assert-NotContains $installer '#define APP_VERSION "0.7.0"' 'Public installer'
Assert-Contains $installer '#preproc ispp' 'Public installer'
Assert-Contains $installer '#if PREPROCVER != ExpectedInnoCompilerVersion' 'Public installer'
Assert-Contains $installer '#define ExpectedInnoCompilerVersion (6 * 16777216 + 7 * 65536 + 1 * 256)' 'Public installer'
Assert-Contains $installer 'requires Inno Setup compiler 6.7.1.0' 'Public installer'
Assert-Contains $readme 'The 0.7.1 bootstrap pins' 'Distribution README'
Assert-NotContains $readme 'The 0.7.0 bootstrap pins' 'Distribution README'
Assert-Contains $validator '25635768L' 'Distribution validator'
Assert-Contains $validator 'VCREDIST-PROVENANCE.txt' 'Distribution validator'
Assert-Contains $validator 'unrelated startup value' 'Distribution validator'
Assert-Contains $validator 'GetValueKind' 'Distribution validator'
Assert-Contains $validator 'ExpandString' 'Distribution validator'
Assert-Contains $validator '/TASKS=""' 'Distribution validator'
Assert-Contains $validator 'Clear-OutputRoot' 'Distribution validator'
Assert-Contains $validator '.voice-dictation-artifact-root' 'Distribution validator'
Assert-Contains $validator 'generated-artifact marker' 'Distribution validator'
Assert-Contains $validator 'ReparsePoint' 'Distribution validator'
Assert-Contains $validator 'metadata is empty' 'Distribution validator'
Assert-Contains $validator 'foreach ($field in @(''Sha256'', ''Size'', ''ProductVersion'', ''FileVersion'', ''ProductName'', ''OriginalFilename''))' 'Distribution validator'
Assert-Contains $validator "SetEnvironmentVariable('VOICE_DICTATION_UIA_FIXTURE', '1', 'Process')" 'Distribution validator'
Assert-Contains $validator 'ReleaseSelection.ps1' 'Distribution validator'
Assert-Contains $validator 'Select-ExactRelease' 'Distribution validator'
Assert-Contains $releaseSelection 'foreach ($candidate in $Response)' 'Release selection helper'
Assert-Contains $releaseSelection 'exactly one release object' 'Release selection helper'
Assert-Contains $releaseSelection 'aggregated tag_name array' 'Release selection helper'
Assert-Contains $releaseSelectionTest 'multiple-release regression' 'Release selection regression'
Assert-Contains $releaseSelectionTest 'duplicate-release regression' 'Release selection regression'
Assert-Contains $releaseSelectionTest 'aggregated-response regression' 'Release selection regression'
Assert-Contains $installer 'RegQueryStringValue' 'Public installer'
Assert-Contains $installer 'RegDeleteValue' 'Public installer'
Assert-Contains $installer 'CurUninstallStepChanged' 'Public installer'
Assert-Contains $installer 'README.txt' 'Public installer'
Assert-NotContains $installer 'uninsdeletevalue' 'Public installer'
Write-Host 'Distribution pin and provenance static checks passed.'
