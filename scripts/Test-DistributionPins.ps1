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
$installer = Get-Content -LiteralPath (Join-Path $repoRoot 'installer\VoiceDictation.iss') -Raw

$vcPin = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
Assert-Contains $workflow 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' 'Public workflow'
Assert-Contains $workflow 'actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9' 'Public workflow'
Assert-Contains $workflow 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' 'Public workflow'
Assert-Contains $workflow 'dotnet-version: 10.0.400' 'Public workflow'
Assert-Contains $workflow 'choco install innosetup --version $innoVersion' 'Public workflow'
Assert-Contains $workflow 'Expected Inno Setup 6.7.1' 'Public workflow'
Assert-Contains $validator $vcPin 'Distribution validator'
Assert-Contains $validator '25635768L' 'Distribution validator'
Assert-Contains $validator 'VCREDIST-PROVENANCE.txt' 'Distribution validator'
Assert-Contains $validator 'unrelated startup value' 'Distribution validator'
Assert-Contains $installer 'RegQueryStringValue' 'Public installer'
Assert-Contains $installer 'RegDeleteValue' 'Public installer'
Assert-Contains $installer 'CurUninstallStepChanged' 'Public installer'
Assert-NotContains $installer 'uninsdeletevalue' 'Public installer'
Write-Host 'Distribution pin and provenance static checks passed.'
