[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Read([string]$path) { Get-Content -LiteralPath (Join-Path $root $path) -Raw }
function Has([string]$text,[string]$needle,[string]$label) { if (-not $text.Contains($needle)) { throw "$label missing: $needle" } }
function Lacks([string]$text,[string]$needle,[string]$label) { if ($text.Contains($needle)) { throw "$label contains forbidden: $needle" } }
$workflow = Read '.github\workflows\windows-distribution.yml'
$validator = Read 'scripts\Validate-Distribution.ps1'
$installer = Read 'installer\VoiceDictation.iss'
$readme = Read 'README.md'
$vcPin = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
foreach ($pin in @('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683','actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9','actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02','actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093','dotnet-version: 10.0.400','windows-2025','windows-11-arm','Voice-Dictation-Windows-${{ inputs.version }}-Setup.exe','Voice-Dictation-Windows-x64-${{ inputs.version }}-Portable.zip','Voice-Dictation-Windows-arm64-${{ inputs.version }}-Portable.zip')) { Has $workflow $pin 'Workflow' }
Lacks $workflow 'run_platform_tests' 'Workflow'
Lacks $workflow 'windows-latest' 'Workflow'
foreach ($needle in @("'0.8.0' = [pscustomobject]@{",$vcPin,'Assert-NativeHost','0xAA64','0x8664','Voice-Dictation-Windows-$Version-Setup.exe','windows-universal','windows-arm64','windows-x64','Get-ValidatedCandidateArtifacts','Invoke-PinnedInference','VOICE_DICTATION_UIA_FIXTURE','portable.flag','runtimes\win-arm64','runtimes\noavx\win-x64')) { Has $validator $needle 'Validator' }
foreach ($needle in @('#define APP_VERSION "0.8.0"','ArchitecturesAllowed=x64compatible arm64','ArchitecturesInstallIn64BitMode=x64compatible arm64','OutputBaseFilename=Voice-Dictation-Windows-{#AppVersion}-Setup','Check: IsX64Install','Check: IsArm64Install','AppMutex={code:GetAppMutex}')) { Has $installer $needle 'Installer' }
foreach ($needle in @('Windows 11 x64 and ARM64','windows-11-arm','windows-2025','0.8.0')) { Has $readme $needle 'README' }
Lacks $readme 'Windows on ARM64' 'README'
Write-Host 'Distribution dual-architecture pin and provenance checks passed.'
