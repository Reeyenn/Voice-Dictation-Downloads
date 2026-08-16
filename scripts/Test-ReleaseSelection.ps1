[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReleaseSelection.ps1')

$expectedAssetName = 'Voice-Dictation-Windows-x64-0.8.0-Portable.zip'
$release080 = [pscustomobject]@{
    tag_name = 'bootstrap-v0.8.0'
    assets = @([pscustomobject]@{ name = $expectedAssetName })
}
$release071 = [pscustomobject]@{
    tag_name = 'v0.7.1'
    assets = @([pscustomobject]@{ name = 'Voice-Dictation-Windows-x64-0.7.1-Portable.zip' })
}
$selected = Select-ExactRelease -Response @($release080, $release071) -ExpectedTag 'bootstrap-v0.8.0' -Source 'multiple-release regression'
if ($null -eq $selected -or $selected.tag_name -cne 'bootstrap-v0.8.0') {
    throw 'Multiple-release selection returned the wrong object or an aggregated tag value.'
}
$selectedAssets = @($selected.assets | Where-Object { $_.name -ceq $expectedAssetName })
if ($selectedAssets.Count -ne 1) { throw 'Multiple-release selection did not retain the exact expected asset.' }

$duplicateRejected = $false
try {
    Select-ExactRelease -Response @($release080, $release080) -ExpectedTag 'bootstrap-v0.8.0' -Source 'duplicate-release regression' | Out-Null
} catch {
    $duplicateRejected = $true
}
if (-not $duplicateRejected) { throw 'Duplicate exact-tag releases were not rejected.' }

$aggregated = [pscustomobject]@{
    tag_name = [object[]]@('bootstrap-v0.8.0', 'v0.7.1')
    assets = @()
}
$aggregateRejected = $false
try {
    Select-ExactRelease -Response $aggregated -ExpectedTag 'bootstrap-v0.8.0' -Source 'aggregated-response regression' | Out-Null
} catch {
    $aggregateRejected = $true
}
if (-not $aggregateRejected) { throw 'Aggregated tag response was not rejected.' }

Write-Host 'Release selection regression passed.'
