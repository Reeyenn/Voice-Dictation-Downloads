[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$PortableSha256,
    [string]$PortableAssetName,
    [string]$PortableZipPath,
    [string]$PlatformTestsSha256,
    [string]$PlatformTestsAssetName,
    [string]$PlatformTestsZipPath,
    [bool]$RunPlatformTests = $true,
    [string]$Repository,
    [string]$ReleaseTag,
    [string]$OutputRoot = "$PSScriptRoot\..\artifacts",
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

# This script is intentionally a consumer of prebuilt release assets. It must
# never be given a private source-repository token or a source checkout.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "ReleaseSelection.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = [System.IO.Path]::GetFullPath($OutputRoot)
$canonicalOutput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts"))
$artifactMarkerName = ".voice-dictation-artifact-root"
$artifactMarkerContent = "Voice Dictation public generated artifact root v1"
$downloadRoot = Join-Path $env:TEMP "voice-dictation-bootstrap-$([Guid]::NewGuid().ToString('N'))"
$portableStage = Join-Path $downloadRoot "portable"
$testsStage = Join-Path $downloadRoot "platform-tests"
$testResultsRoot = Join-Path $downloadRoot "test-results"
$installRoot = Join-Path $env:TEMP "voice-dictation-install-$([Guid]::NewGuid().ToString('N'))"
$modelPath = Join-Path $downloadRoot "ggml-small.en.bin"
$samplePath = Join-Path $downloadRoot "whisper-jfk.wav"
$silencePath = Join-Path $downloadRoot "whisper-silence.wav"

$modelRevision = "c521a4b02f422512d734391fdf08bb08c0862f68"
$modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/$modelRevision/ggml-small.en.bin?download=true"
$modelBytes = 487614201L
$modelSha256 = "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
$sampleCommit = "1fe009caeda75f69bc864d6370b10674e45a92bd"
$sampleUrl = "https://raw.githubusercontent.com/ggerganov/whisper.cpp/$sampleCommit/samples/jfk.wav"
$sampleBytes = 352078L
$sampleSha256 = "59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e"

# The public bootstrap is deliberately fail-closed on the native prerequisite:
# a new release must add and review a new pin before it can be packaged.
$vcRedistPins = @{
    '0.7.0' = [pscustomobject]@{
        Sha256 = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
        Size = 25635768L
        ProductVersion = '14.44.35211.0'
        FileVersion = '14.44.35211.0'
        ProductName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211'
        OriginalFilename = 'VC_redist.x64.exe'
    }
    '0.7.1' = [pscustomobject]@{
        Sha256 = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
        Size = 25635768L
        ProductVersion = '14.44.35211.0'
        FileVersion = '14.44.35211.0'
        ProductName = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.44.35211'
        OriginalFilename = 'VC_redist.x64.exe'
    }
}

function Fail([string]$Message) {
    throw "Distribution validation failed: $Message"
}

function Clear-OutputRoot([string]$Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $repoPath = [System.IO.Path]::GetFullPath($repoRoot)
    if ($fullPath -eq $repoPath -or $fullPath -eq [System.IO.Path]::GetPathRoot($fullPath)) {
        Fail 'OutputRoot must be a dedicated artifact directory, not a repository or filesystem root.'
    }
    if ($repoPath.StartsWith($fullPath.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail 'OutputRoot cannot contain the repository; choose a dedicated artifact leaf.'
    }
    if (Test-Path -LiteralPath $fullPath) {
        $outputItem = Get-Item -LiteralPath $fullPath
        if (-not $outputItem.PSIsContainer -or
            (($outputItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            Fail 'OutputRoot must be a normal directory before cleanup.'
        }
        $markerPath = Join-Path $fullPath $artifactMarkerName
        $isCanonicalOutput = $fullPath.Equals($canonicalOutput, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isCanonicalOutput) {
            $markerContentPath = Join-Path $markerPath 'purpose.txt'
            if (-not (Test-Path -LiteralPath $markerContentPath -PathType Leaf) -or
                (Get-Content -LiteralPath $markerContentPath -Raw).Trim() -cne $artifactMarkerContent) {
                Fail 'An existing custom OutputRoot must contain the generated-artifact marker; refusing broad recursive deletion.'
            }
        }
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
    $markerPath = Join-Path $fullPath $artifactMarkerName
    New-Item -ItemType Directory -Force -Path $markerPath | Out-Null
    Set-Content -LiteralPath (Join-Path $markerPath 'purpose.txt') -Value $artifactMarkerContent -Encoding ascii
}

function Assert-Sha256([string]$Value, [string]$Label) {
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') {
        Fail "$Label must be a 64-character SHA-256 value."
    }
    return $Value.ToLowerInvariant()
}

function Assert-Version([string]$Value) {
    if ($Value -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
        Fail "Version '$Value' is not a valid versioned release identifier."
    }
}

function Get-ExpectedFileVersion([string]$ExpectedVersion) {
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $ExpectedVersion,
        '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:[-+][0-9A-Za-z.-]+)?$'
    )
    if (-not $match.Success) {
        Fail "Version '$ExpectedVersion' cannot be mapped to a Windows four-part file version."
    }
    return "$($match.Groups['major'].Value).$($match.Groups['minor'].Value).$($match.Groups['patch'].Value).0"
}

function Assert-ExecutableVersion([string]$Path, [string]$ExpectedVersion, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Label is missing: $Path"
    }
    $expectedFileVersion = Get-ExpectedFileVersion $ExpectedVersion
    $actualFileVersion = [string](Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    if ([string]::IsNullOrWhiteSpace($actualFileVersion)) {
        Fail "$Label has no file version metadata; expected exactly $expectedFileVersion."
    }
    $actualFileVersion = $actualFileVersion.Trim()
    if ($actualFileVersion -cne $expectedFileVersion) {
        Fail "$Label file version '$actualFileVersion' does not exactly match expected '$expectedFileVersion'."
    }
}

function Assert-PeAmd64([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Label is missing: $Path"
    }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        if ($stream.Length -lt 64) {
            Fail "$Label is too small to be a PE image."
        }
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            Fail "$Label is not an MZ executable."
        }
        $stream.Position = 0x3C
        $peOffset = [int64]$reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 24)) {
            Fail "$Label has an invalid PE header offset."
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            Fail "$Label is missing the PE signature."
        }
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) {
            Fail "$Label has PE machine 0x$('{0:X4}' -f $machine); expected AMD64 0x8664."
        }
    } catch {
        Fail "$Label PE header could not be validated: $($_.Exception.Message)"
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-VcRedistPin([string]$ExpectedVersion) {
    if (-not $vcRedistPins.ContainsKey($ExpectedVersion)) {
        Fail "No reviewed VC++ redist pin exists for release '$ExpectedVersion'; add a new exact pin before packaging it."
    }
    $pin = $vcRedistPins[$ExpectedVersion]
    foreach ($field in @('Sha256', 'Size', 'ProductVersion', 'FileVersion', 'ProductName', 'OriginalFilename')) {
        $value = [string]$pin.$field
        if ([string]::IsNullOrWhiteSpace($value)) {
            Fail "VC++ redist pin field '$field' is empty for release '$ExpectedVersion'."
        }
    }
    if ([int64]$pin.Size -le 0) {
        Fail "VC++ redist pin size must be positive for release '$ExpectedVersion'."
    }
    return $pin
}

function Assert-AssetName([string]$Name, [string]$Label, [string]$ExpectedVersion) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Fail "$Label asset name is required when the corresponding path is not supplied."
    }
    if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        Fail "$Label asset name contains path separators or unsafe characters."
    }
    if ($Name -notmatch [System.Text.RegularExpressions.Regex]::Escape($ExpectedVersion)) {
        Fail "$Label asset '$Name' does not contain version '$ExpectedVersion'."
    }
}

function Assert-FileSha256([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Label file is missing: $Path"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        Fail "$Label SHA-256 mismatch. Expected $Expected, got $actual."
    }
    if ((Get-Item -LiteralPath $Path).Length -le 0) {
        Fail "$Label is empty."
    }
}

function Assert-VcRedistEvidence([string]$Path, [pscustomobject]$Pin, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "$Label is missing." }
    $provenanceText = Get-Content -LiteralPath $Path -Raw
    foreach ($line in @(
        "SHA256: $($Pin.Sha256)"
        "Size: $($Pin.Size)"
        "FileVersion: $($Pin.FileVersion)"
        "ProductVersion: $($Pin.ProductVersion)"
        "ProductName: $($Pin.ProductName)"
        'Authenticode: Valid (Microsoft signer)'
    )) {
        if ($provenanceText -notlike "*$line*") {
            Fail "$Label does not record '$line'."
        }
    }
}

function Clear-WorkflowTokens {
    # Release API calls are completed before this function is called. Clearing
    # both conventional variables prevents a downloaded/precompiled child
    # process from inheriting a repository token through either name.
    foreach ($name in @('GITHUB_TOKEN', 'GH_TOKEN')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
}

function Get-RegistryRunValueState([string]$RunKeyPath, [string]$RunValueName) {
    $runSubkey = $RunKeyPath -replace '^HKCU:\\', ''
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($runSubkey, $false)
    if ($null -eq $key -or $key.GetValueNames() -notcontains $RunValueName) {
        if ($null -ne $key) { $key.Dispose() }
        return [pscustomobject]@{ Present = $false; Value = $null; Kind = $null }
    }
    try {
        return [pscustomobject]@{
            Present = $true
            Value = [string]$key.GetValue($RunValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Kind = $key.GetValueKind($RunValueName)
        }
    } finally {
        $key.Dispose()
    }
}

function Get-RegistryRunValue([string]$RunKeyPath, [string]$RunValueName) {
    $state = Get-RegistryRunValueState $RunKeyPath $RunValueName
    if (-not $state.Present) { return $null }
    return $state.Value
}

function Set-RegistryRunValue([string]$RunKeyPath, [string]$RunValueName, [string]$Value, [object]$Kind = "String") {
    New-Item -Path $RunKeyPath -Force | Out-Null
    $propertyType = if ($Kind -is [Microsoft.Win32.RegistryValueKind]) { $Kind.ToString() } else { [string]$Kind }
    New-ItemProperty -LiteralPath $RunKeyPath -Name $RunValueName -PropertyType $propertyType -Value $Value -Force | Out-Null
}

function Remove-RegistryRunValue([string]$RunKeyPath, [string]$RunValueName) {
    Remove-ItemProperty -LiteralPath $RunKeyPath -Name $RunValueName -ErrorAction SilentlyContinue
}

function Restore-RegistryRunValueState([string]$RunKeyPath, [string]$RunValueName, [pscustomobject]$State) {
    Remove-RegistryRunValue $RunKeyPath $RunValueName
    if ($State.Present) { Set-RegistryRunValue $RunKeyPath $RunValueName $State.Value $State.Kind }
}

function Get-ZipEntries([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        Fail "Unable to open ZIP '$Path': $($_.Exception.Message)"
    }
    try {
        $entries = @($archive.Entries | ForEach-Object {
            $name = $_.FullName.Replace('\', '/')
            [pscustomobject]@{
                Name = $name
                IsDirectory = $name.EndsWith('/')
                Length = $_.Length
            }
        })
    } finally {
        $archive.Dispose()
    }
    if ($entries.Count -eq 0) {
        Fail "ZIP '$Path' has no entries."
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        if ($entry.Name.StartsWith('/') -or $entry.Name -match '(^|/)\.\.(?:/|$)') {
            Fail "ZIP '$Path' contains an unsafe entry path '$($entry.Name)'."
        }
        if (-not $seen.Add($entry.Name)) {
            Fail "ZIP '$Path' contains duplicate entry '$($entry.Name)'."
        }
    }
    return $entries
}

function Download-ReleaseAsset(
    [string]$AssetName,
    [string]$ExpectedVersion,
    [string]$Repo,
    [string]$Tag,
    [string]$Token,
    [string]$Destination
) {
    Assert-AssetName $AssetName "Bootstrap" $ExpectedVersion
    if ([string]::IsNullOrWhiteSpace($Repo) -or $Repo -notmatch '^[^/\s]+/[^/\s]+$') {
        Fail "A repository in owner/name form is required to download bootstrap assets."
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY) -and $Repo -cne $env:GITHUB_REPOSITORY) {
        Fail "Bootstrap assets must come from this distribution repository ($env:GITHUB_REPOSITORY), not '$Repo'."
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Fail "GITHUB_TOKEN is required only to read the matching release in this distribution repository."
    }
    if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = "bootstrap-v$ExpectedVersion" }
    $expectedBootstrapTag = "bootstrap-v$ExpectedVersion"
    if ($Tag -cne $expectedBootstrapTag -or $Tag -notmatch '^bootstrap-v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
        Fail "Bootstrap release tag '$Tag' must be exactly '$expectedBootstrapTag'."
    }

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github+json"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'voice-dictation-public-distribution-validator'
    }
    $releaseUri = "https://api.github.com/repos/$Repo/releases/tags/$([Uri]::EscapeDataString($Tag))"
    $tagEndpointFailed = $false
    $tagResponse = $null
    try {
        $tagResponse = Invoke-RestMethod -Method Get -Uri $releaseUri -Headers $headers
    } catch {
        $tagEndpointFailed = $true
    }
    if (-not $tagEndpointFailed) {
        try {
            $release = Select-ExactRelease -Response $tagResponse -ExpectedTag $Tag -Source 'Release tag endpoint'
        } catch {
            Fail $_.Exception.Message
        }
    } else {
        # GitHub's tag endpoint has historically been inconsistent for draft
        # releases. Retry the authenticated release list, still constrained to
        # this repository and exact tag, before failing closed.
        try {
            $releaseListUri = "https://api.github.com/repos/$Repo/releases?per_page=100"
            $releaseListResponse = Invoke-RestMethod -Method Get -Uri $releaseListUri -Headers $headers
            $release = Select-ExactRelease -Response $releaseListResponse -ExpectedTag $Tag -Source 'Release list endpoint'
        } catch {
            Fail "Could not read release '$Tag' from this distribution repository: $($_.Exception.Message)"
        }
    }
    $asset = @($release.assets | Where-Object { $_.name -ceq $AssetName })
    if ($asset.Count -ne 1) {
        Fail "Release '$Tag' must contain exactly one asset named '$AssetName'."
    }
    $assetUrl = [string]$asset[0].url
    $assetUri = [Uri]$assetUrl
    $expectedAssetPath = "^/repos/$([System.Text.RegularExpressions.Regex]::Escape($Repo))/releases/assets/\d+$"
    if ($assetUri.Host -ne 'api.github.com' -or $assetUri.AbsolutePath -notmatch $expectedAssetPath) {
        Fail "Release asset '$AssetName' did not resolve to the expected GitHub repository asset endpoint."
    }
    $downloadHeaders = @{
        Authorization = "Bearer $Token"
        Accept = 'application/octet-stream'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'voice-dictation-public-distribution-validator'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    try {
        Invoke-WebRequest -Method Get -Uri $asset[0].url -Headers $downloadHeaders -OutFile $Destination
    } catch {
        Fail "Could not download release asset '$AssetName': $($_.Exception.Message)"
    }
    return $Destination
}

function Assert-PortableArchive([string]$Path, [string]$ExpectedVersion, [pscustomobject]$VcRedistPin) {
    $entries = @(Get-ZipEntries $Path | Where-Object { -not $_.IsDirectory })
    $required = @(
        'VoiceDictation.exe',
        'vc_redist.x64.exe',
        'VCREDIST-PROVENANCE.txt',
        'README.txt',
        'THIRD_PARTY_NOTICES.md',
        'DOTNET_THIRD_PARTY_NOTICES.txt'
    )
    foreach ($name in $required) {
        if (-not (@($entries | Where-Object { $_.Name -ceq $name }).Count -eq 1)) {
            Fail "Portable ZIP must contain exactly one root '$name'."
        }
    }
    $dotnetNotice = @($entries | Where-Object { $_.Name -ceq 'DOTNET_THIRD_PARTY_NOTICES.txt' })
    if ($dotnetNotice.Count -ne 1 -or $dotnetNotice[0].Length -le 0) {
        Fail 'DOTNET_THIRD_PARTY_NOTICES.txt must be one non-empty root file.'
    }
    $allowedRootNames = @($required)
    $unexpectedRoot = @($entries | Where-Object {
        $_.Name -notmatch '/' -and $_.Name -cnotin $allowedRootNames
    })
    if ($unexpectedRoot.Count -gt 0) {
        Fail "Portable ZIP contains unexpected root files; the public beta contract is single-executable: $($unexpectedRoot.Name -join ', ')"
    }

    $expectedWhisperNames = @('ggml-base-whisper.dll', 'ggml-cpu-whisper.dll', 'ggml-whisper.dll', 'whisper.dll')
    $expectedRuntime = @(
        $expectedWhisperNames | ForEach-Object { "runtimes/win-x64/$_" }
        $expectedWhisperNames | ForEach-Object { "runtimes/noavx/win-x64/$_" }
    )
    $actualRuntime = @($entries | Where-Object { $_.Name -like 'runtimes/*' } | Select-Object -ExpandProperty Name)
    $missingRuntime = @($expectedRuntime | Where-Object { $_ -cnotin $actualRuntime })
    $unexpectedRuntime = @($actualRuntime | Where-Object { $_ -cnotin $expectedRuntime })
    if ($missingRuntime.Count -gt 0) {
        Fail "Portable ZIP is missing required Whisper runtime DLLs: $($missingRuntime -join ', ')"
    }
    if ($unexpectedRuntime.Count -gt 0 -or $actualRuntime.Count -ne $expectedRuntime.Count) {
        Fail "Portable ZIP must contain exactly four optimized and four NoAvx Whisper DLLs; unexpected runtime entries: $($unexpectedRuntime -join ', ')"
    }
    $unsupportedRuntime = @($entries | Where-Object { $_.Name -match '(?i)^runtimes/(?:win-arm64|win-x86)(?:/|$)' })
    if ($unsupportedRuntime.Count -gt 0) {
        Fail "Portable ZIP must not contain win-arm64 or win-x86 runtimes."
    }

    $badReleaseFiles = @($entries | Where-Object {
        $_.Name -match '(?i)\.(?:pdb|xml|cs|csproj|sln|props|targets)$'
    })
    if ($badReleaseFiles.Count -gt 0) {
        Fail "Portable ZIP contains source/debug/documentation build material: $($badReleaseFiles.Name -join ', ')"
    }
    $unexpectedFiles = @($entries | Where-Object {
        $_.Name -cnotin $allowedRootNames -and $_.Name -cnotin $expectedRuntime
    })
    if ($unexpectedFiles.Count -gt 0) {
        Fail "Portable ZIP contains unexpected files; only the app, notices, VC++ runtime, and eight Whisper DLLs are allowed: $($unexpectedFiles.Name -join ', ')"
    }
    $executables = @($entries | Where-Object { $_.Name -match '(?i)\.exe$' } | Select-Object -ExpandProperty Name)
    $allowedExecutables = @('VoiceDictation.exe', 'vc_redist.x64.exe')
    if (@($executables | Where-Object { $_ -cnotin $allowedExecutables }).Count -gt 0 -or $executables.Count -ne 2) {
        Fail "Portable ZIP must contain only VoiceDictation.exe and vc_redist.x64.exe as executables."
    }

    New-Item -ItemType Directory -Force -Path $portableStage | Out-Null
    Expand-Archive -LiteralPath $Path -DestinationPath $portableStage -Force
    $exe = Join-Path $portableStage 'VoiceDictation.exe'
    $runtime = Join-Path $portableStage 'vc_redist.x64.exe'
    Assert-FileSha256 $runtime $VcRedistPin.Sha256 'Bundled VC++ redist'
    if ((Get-Item -LiteralPath $runtime).Length -ne $VcRedistPin.Size) {
        Fail "Bundled VC++ redist size does not match the reviewed pin ($($VcRedistPin.Size) bytes)."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $runtime
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
        Fail "vc_redist.x64.exe did not pass Authenticode validation."
    }
    $subject = $signature.SignerCertificate.Subject
    $issuer = $signature.SignerCertificate.Issuer
    if ($subject -notmatch '(?i)Microsoft' -and $issuer -notmatch '(?i)Microsoft') {
        Fail "vc_redist.x64.exe is signed, but not by a Microsoft certificate."
    }
    $vcVersionInfo = (Get-Item -LiteralPath $runtime).VersionInfo
    $vcMetadata = @(
        [pscustomobject]@{ Name = 'FileVersion'; Expected = $VcRedistPin.FileVersion; Actual = [string]$vcVersionInfo.FileVersion }
        [pscustomobject]@{ Name = 'ProductVersion'; Expected = $VcRedistPin.ProductVersion; Actual = [string]$vcVersionInfo.ProductVersion }
        [pscustomobject]@{ Name = 'ProductName'; Expected = $VcRedistPin.ProductName; Actual = [string]$vcVersionInfo.ProductName }
        [pscustomobject]@{ Name = 'OriginalFilename'; Expected = $VcRedistPin.OriginalFilename; Actual = [string]$vcVersionInfo.OriginalFilename }
    )
    foreach ($metadata in $vcMetadata) {
        if ([string]::IsNullOrWhiteSpace([string]$metadata.Expected)) {
            Fail "vc_redist.x64.exe expected $($metadata.Name) metadata is empty in the reviewed pin."
        }
        if ([string]::IsNullOrWhiteSpace($metadata.Actual)) {
            Fail "vc_redist.x64.exe $($metadata.Name) metadata is empty; expected '$($metadata.Expected)'."
        }
        if ($metadata.Actual.Trim() -cne $metadata.Expected) {
            Fail "vc_redist.x64.exe $($metadata.Name) '$($metadata.Actual)' does not exactly match expected '$($metadata.Expected)'."
        }
    }
    Assert-VcRedistEvidence (Join-Path $portableStage 'VCREDIST-PROVENANCE.txt') $VcRedistPin 'Portable VC++ provenance'
    Assert-ExecutableVersion $exe $ExpectedVersion 'Portable VoiceDictation.exe'
    Assert-PeAmd64 $exe 'Portable VoiceDictation.exe'
    foreach ($relative in $expectedRuntime) {
        $runtimeDll = Join-Path $portableStage ($relative.Replace('/', '\'))
        Assert-PeAmd64 $runtimeDll "Portable Whisper runtime $relative"
    }
    # vc_redist.x64.exe is intentionally not checked here: Microsoft's
    # bootstrap is a signed PE32 (i386) installer, while the app and Whisper
    # native payload are the x64 components this validator claims to ship.
    Write-Host "Portable archive structure, notices, Whisper runtimes, executable set, and VC++ signature passed."
    return $exe
}

function Get-TrxCounter([System.Xml.XmlElement]$Counters, [string]$Name, [bool]$Required = $true) {
    $raw = $Counters.GetAttribute($Name)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ($Required) { Fail "Platform.Tests TRX is missing required '$Name' counter." }
        return $null
    }
    if ($raw -notmatch '^\d+$') {
        Fail "Platform.Tests TRX counter '$Name' is not a non-negative integer."
    }
    try {
        return [int]$raw
    } catch {
        Fail "Platform.Tests TRX counter '$Name' is outside the supported integer range."
    }
}

function Assert-PlatformTestsResults([string]$ResultsDirectory, [int]$MinimumTests = 58) {
    $trxFiles = @(Get-ChildItem -LiteralPath $ResultsDirectory -Filter '*.trx' -File -Recurse)
    if ($trxFiles.Count -ne 1) {
        Fail "Platform.Tests must produce exactly one TRX in the dedicated results directory; found $($trxFiles.Count)."
    }
    try {
        [xml]$trx = Get-Content -LiteralPath $trxFiles[0].FullName -Raw
    } catch {
        Fail "Platform.Tests TRX could not be parsed as XML: $($_.Exception.Message)"
    }
    $counters = $trx.SelectSingleNode("//*[local-name()='Counters']")
    if ($null -eq $counters -or -not ($counters -is [System.Xml.XmlElement])) {
        Fail 'Platform.Tests TRX has no Counters element.'
    }
    $total = Get-TrxCounter $counters 'total'
    $executed = Get-TrxCounter $counters 'executed'
    $passed = Get-TrxCounter $counters 'passed'
    $failed = Get-TrxCounter $counters 'failed'
    $notExecuted = Get-TrxCounter $counters 'notExecuted'
    if ($total -lt $MinimumTests) {
        Fail "Platform.Tests discovered $total tests; the current baseline requires at least $MinimumTests."
    }
    if ($executed -ne $total -or $notExecuted -ne 0 -or $failed -ne 0 -or $passed -ne $total) {
        Fail "Platform.Tests TRX counters are unhealthy: total=$total executed=$executed passed=$passed failed=$failed notExecuted=$notExecuted."
    }
    foreach ($counterName in @('error', 'timeout', 'aborted', 'inconclusive')) {
        $counter = Get-TrxCounter $counters $counterName $false
        if ($null -ne $counter -and $counter -ne 0) {
            Fail "Platform.Tests TRX reports $counter $counterName result(s)."
        }
    }
    Write-Host "Platform.Tests TRX passed: total=$total executed=$executed passed=$passed failed=$failed notExecuted=$notExecuted."
}

function Assert-PlatformTestsArchive([string]$Path) {
    $entries = @(Get-ZipEntries $Path | Where-Object { -not $_.IsDirectory })
    $badFiles = @($entries | Where-Object {
        $_.Name -match '(?i)\.(?:pdb|cs|csproj|sln|props|targets)$'
    })
    if ($badFiles.Count -gt 0) {
        Fail "Platform.Tests ZIP contains source/debug build material: $($badFiles.Name -join ', ')"
    }
    $testDlls = @($entries | Where-Object { [System.IO.Path]::GetFileName($_.Name) -ceq 'VoiceDictation.Platform.Tests.dll' })
    if ($testDlls.Count -ne 1) {
        Fail "Platform.Tests ZIP must contain exactly one VoiceDictation.Platform.Tests.dll."
    }
    New-Item -ItemType Directory -Force -Path $testsStage | Out-Null
    if (Test-Path -LiteralPath $testResultsRoot) {
        Remove-Item -LiteralPath $testResultsRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $testResultsRoot | Out-Null
    Expand-Archive -LiteralPath $Path -DestinationPath $testsStage -Force
    $dll = Join-Path $testsStage ($testDlls[0].Name.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        $dll = Get-ChildItem -LiteralPath $testsStage -Filter 'VoiceDictation.Platform.Tests.dll' -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $dll) { Fail "Extracted Platform.Tests ZIP did not contain its test assembly." }
    $dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($null -eq $dotnet) { Fail "dotnet.exe is required to run Platform.Tests." }
    Write-Host "Running precompiled Platform.Tests with dotnet vstest."
    Clear-WorkflowTokens
    $previousUiaFixture = [Environment]::GetEnvironmentVariable('VOICE_DICTATION_UIA_FIXTURE', 'Process')
    $testExitCode = 0
    try {
        # The hosted Windows run must exercise the real WPF UIA fixture. Keep
        # the opt-in process-local so local/non-Windows runs retain skip behavior.
        [Environment]::SetEnvironmentVariable('VOICE_DICTATION_UIA_FIXTURE', '1', 'Process')
        & $dotnet.Source vstest $dll "--ResultsDirectory:$testResultsRoot" '--logger:trx;LogFileName=platform-tests.trx'
        $testExitCode = $LASTEXITCODE
    } finally {
        [Environment]::SetEnvironmentVariable('VOICE_DICTATION_UIA_FIXTURE', $previousUiaFixture, 'Process')
    }
    if ($testExitCode -ne 0) {
        Fail "dotnet vstest failed with exit code $testExitCode."
    }
    Assert-PlatformTestsResults $testResultsRoot
}

function Write-SilenceWave([string]$Path, [int]$Seconds = 3) {
    $sampleRate = 16000
    $dataBytes = $sampleRate * $Seconds * 2
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.BinaryWriter]::new($stream)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int](36 + $dataBytes))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([int]16)
        $writer.Write([short]1)
        $writer.Write([short]1)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate * 2))
        $writer.Write([short]2)
        $writer.Write([short]16)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]$dataBytes)
        $writer.Write([byte[]]::new($dataBytes))
        $writer.Flush()
        $writer.Dispose()
    } finally {
        $stream.Dispose()
    }
}

function Quote-ProcessArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    if ($Value.Contains('"')) { Fail 'Inference argument unexpectedly contains a quote.' }
    return '"' + $Value + '"'
}

function Invoke-WindowsExecutable([string]$Path, [string[]]$Arguments, [string]$Label) {
    Clear-WorkflowTokens
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WorkingDirectory (Split-Path -Parent $Path) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Fail "$Label failed with exit code $($process.ExitCode)."
    }
}

function Invoke-PinnedInference([string]$ExecutablePath) {
    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath
    $model = Get-Item -LiteralPath $modelPath
    if ($model.Length -ne $modelBytes) { Fail "Pinned Whisper model size mismatch: $($model.Length)." }
    Assert-FileSha256 $modelPath $modelSha256 'Pinned Whisper model'
    Invoke-WebRequest -Uri $sampleUrl -OutFile $samplePath
    $sample = Get-Item -LiteralPath $samplePath
    if ($sample.Length -ne $sampleBytes) { Fail "Pinned JFK sample size mismatch: $($sample.Length)." }
    Assert-FileSha256 $samplePath $sampleSha256 'Pinned JFK sample'
    Write-SilenceWave $silencePath

    Invoke-WindowsExecutable $ExecutablePath @(
        '--inference-test', '--model', (Quote-ProcessArgument $modelPath),
        '--audio', (Quote-ProcessArgument $samplePath), '--expect-text',
        (Quote-ProcessArgument 'And so my fellow Americans'), '--max-deviation', '0.55'
    ) 'Known-phrase inference'
    Invoke-WindowsExecutable $ExecutablePath @(
        '--inference-test', '--model', (Quote-ProcessArgument $modelPath),
        '--audio', (Quote-ProcessArgument $silencePath), '--expect-empty'
    ) 'Silence anti-hallucination inference'
    Write-Host 'Pinned Whisper model, JFK phrase, and silence inference passed.'
}

function Invoke-InstallerSmoke([string]$InstallerPath, [string]$ExpectedVersion) {
    if ([System.Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        Fail 'Installer smoke tests require Windows.'
    }
    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'Voice Dictation'
    $originalRunState = Get-RegistryRunValueState $runKeyPath $runValueName

    if (Test-Path -LiteralPath $installRoot) {
        Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        Remove-RegistryRunValue $runKeyPath $runValueName

        # Default install must not create startup. Simulate the running app
        # writing its exact owned value, then verify uninstall removes only it.
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$installRoot`"", '/TASKS=""')
        Clear-WorkflowTokens
        $install = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
        if ($install.ExitCode -ne 0) { Fail "Silent installer exited with code $($install.ExitCode)." }
        $installedExe = Join-Path $installRoot 'VoiceDictation.exe'
        if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) { Fail 'Installer did not place VoiceDictation.exe.' }
        Assert-ExecutableVersion $installedExe $ExpectedVersion 'Installed VoiceDictation.exe'
        if ($null -ne (Get-RegistryRunValue $runKeyPath $runValueName)) { Fail 'Default install unexpectedly created the HKCU startup value.' }
        Assert-VcRedistEvidence (Join-Path $installRoot 'VCREDIST-PROVENANCE.txt') $vcRedistPin 'Installed VC++ provenance'
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'README.txt') -PathType Leaf)) { Fail 'Installer did not place README.txt.' }
        $expectedRuntimeRelative = @(
            'runtimes\win-x64\ggml-base-whisper.dll',
            'runtimes\win-x64\ggml-cpu-whisper.dll',
            'runtimes\win-x64\ggml-whisper.dll',
            'runtimes\win-x64\whisper.dll',
            'runtimes\noavx\win-x64\ggml-base-whisper.dll',
            'runtimes\noavx\win-x64\ggml-cpu-whisper.dll',
            'runtimes\noavx\win-x64\ggml-whisper.dll',
            'runtimes\noavx\win-x64\whisper.dll'
        )
        foreach ($relative in $expectedRuntimeRelative) {
            if (-not (Test-Path -LiteralPath (Join-Path $installRoot $relative) -PathType Leaf)) {
                Fail "Installer did not recursively install required Whisper runtime '$relative'."
            }
        }
        $unsupportedInstalledRuntime = Get-ChildItem -LiteralPath (Join-Path $installRoot 'runtimes') -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '(?i)\\(?:win-arm64|win-x86)\\' }
        if ($unsupportedInstalledRuntime) { Fail 'Installer installed an unsupported ARM64 or x86 runtime.' }
        $expectedRunValue = "`"$installedExe`" --background"
        Set-RegistryRunValue $runKeyPath $runValueName $expectedRunValue
        $uninstaller = Join-Path $installRoot 'unins000.exe'
        if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { Fail 'Installer did not place an uninstaller.' }
        $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) { Fail "Silent uninstaller exited with code $($uninstall.ExitCode)." }
        if (Test-Path -LiteralPath $installRoot) { Fail 'Uninstall left installation files behind.' }
        if ($null -ne (Get-RegistryRunValue $runKeyPath $runValueName)) { Fail 'Uninstall did not remove the exact app-owned startup value.' }

        # A user/other application value under the same name must survive.
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$installRoot`"", '/TASKS=""')
        Clear-WorkflowTokens
        $install = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
        if ($install.ExitCode -ne 0) { Fail "Silent default installer exited with code $($install.ExitCode)." }
        $unrelatedRunValue = '"C:\Other\OtherApp.exe" --background'
        Set-RegistryRunValue $runKeyPath $runValueName $unrelatedRunValue "ExpandString"
        $uninstaller = Join-Path $installRoot 'unins000.exe'
        $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) { Fail "Unrelated-value uninstaller exited with code $($uninstall.ExitCode)." }
        $unrelatedState = Get-RegistryRunValueState $runKeyPath $runValueName
        if (-not $unrelatedState.Present -or $unrelatedState.Value -cne $unrelatedRunValue -or $unrelatedState.Kind.ToString() -cne 'ExpandString') { Fail 'Uninstall removed, changed, or retyped an unrelated startup value.' }
        Remove-RegistryRunValue $runKeyPath $runValueName

        # Keep the explicit installer startup-task case and app self-tests.
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$installRoot`"", '/TASKS="startup"')
        Clear-WorkflowTokens
        $install = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
        if ($install.ExitCode -ne 0) { Fail "Silent startup-task installer exited with code $($install.ExitCode)." }
        $installedExe = Join-Path $installRoot 'VoiceDictation.exe'
        Assert-VcRedistEvidence (Join-Path $installRoot 'VCREDIST-PROVENANCE.txt') $vcRedistPin 'Installed VC++ provenance'
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'README.txt') -PathType Leaf)) { Fail 'Installer did not place README.txt.' }
        $runValue = Get-RegistryRunValue $runKeyPath $runValueName
        $expectedRunValue = "`"$installedExe`" --background"
        if ($runValue -cne $expectedRunValue) { Fail 'Installer did not create the expected HKCU startup value.' }
        Invoke-WindowsExecutable $installedExe @('--self-test') 'Installed --self-test'
        Invoke-WindowsExecutable $installedExe @('--inference-match-test') 'Installed --inference-match-test'
        $uninstaller = Join-Path $installRoot 'unins000.exe'
        if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { Fail 'Installer did not place an uninstaller.' }
        $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) { Fail "Silent uninstaller exited with code $($uninstall.ExitCode)." }
        if (Test-Path -LiteralPath $installRoot) { Fail 'Uninstall left installation files behind.' }
        if ($null -ne (Get-RegistryRunValue $runKeyPath $runValueName)) { Fail 'Startup-task uninstall left the startup value behind.' }
        Write-Host "Silent default-install/owned-startup/unrelated-value/startup-task/self-test/uninstall smoke passed for $ExpectedVersion."
    } finally {
        if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Restore-RegistryRunValueState $runKeyPath $runValueName $originalRunState
    }
    $restoredRunState = Get-RegistryRunValueState $runKeyPath $runValueName
    if ($restoredRunState.Present -ne $originalRunState.Present -or
        $restoredRunState.Value -cne $originalRunState.Value -or
        ([string]$restoredRunState.Kind) -cne ([string]$originalRunState.Kind)) {
        Fail 'Installer smoke did not restore the pre-existing startup registry value and kind exactly.'
    }
}

Assert-Version $Version
$vcRedistPin = Get-VcRedistPin $Version
$PortableSha256 = Assert-Sha256 $PortableSha256 'Portable ZIP SHA-256'
$PlatformTestsSha256 = if ([string]::IsNullOrWhiteSpace($PlatformTestsSha256)) { '' } else { Assert-Sha256 $PlatformTestsSha256 'Platform.Tests ZIP SHA-256' }
if ($RunPlatformTests -and ([string]::IsNullOrWhiteSpace($PlatformTestsSha256) -or [string]::IsNullOrWhiteSpace($PlatformTestsAssetName) -and [string]::IsNullOrWhiteSpace($PlatformTestsZipPath))) {
    Fail 'Platform.Tests validation is enabled by default; provide its asset name/path and SHA-256, or explicitly set RunPlatformTests to false for a bootstrap-only check.'
}
if (-not $RunPlatformTests -and (-not [string]::IsNullOrWhiteSpace($PlatformTestsSha256) -or -not [string]::IsNullOrWhiteSpace($PlatformTestsAssetName) -or -not [string]::IsNullOrWhiteSpace($PlatformTestsZipPath))) {
    Fail 'Platform.Tests asset inputs must be omitted when RunPlatformTests is false; no compiled test archive will be trusted or silently ignored.'
}
if (-not [string]::IsNullOrWhiteSpace($PortableAssetName)) { Assert-AssetName $PortableAssetName 'Portable' $Version }
if (-not [string]::IsNullOrWhiteSpace($PortableAssetName) -and $PortableAssetName -cnotmatch "^Voice-Dictation-Windows-x64-$([System.Text.RegularExpressions.Regex]::Escape($Version))-Portable\.zip$") {
    Fail "Portable asset must use the versioned Voice-Dictation-Windows-x64-<version>-Portable.zip name."
}
if (-not [string]::IsNullOrWhiteSpace($PlatformTestsAssetName)) {
    Assert-AssetName $PlatformTestsAssetName 'Platform.Tests' $Version
    if ($PlatformTestsAssetName -cnotmatch "^Voice-Dictation-Windows-x64-$([System.Text.RegularExpressions.Regex]::Escape($Version))-Platform\.Tests\.zip$") {
        Fail "Platform.Tests asset must use the versioned Voice-Dictation-Windows-x64-<version>-Platform.Tests.zip name."
    }
}

try {
    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
    if ([string]::IsNullOrWhiteSpace($PortableZipPath)) {
        if ([string]::IsNullOrWhiteSpace($PortableAssetName)) { $PortableAssetName = "Voice-Dictation-Windows-x64-$Version-Portable.zip" }
        $PortableZipPath = Download-ReleaseAsset $PortableAssetName $Version $Repository $(if ($ReleaseTag) { $ReleaseTag } else { "bootstrap-v$Version" }) $GitHubToken (Join-Path $downloadRoot $PortableAssetName)
    } else {
        $PortableZipPath = (Resolve-Path -LiteralPath $PortableZipPath).Path
    }
    Assert-FileSha256 $PortableZipPath $PortableSha256 'Portable ZIP'
    $portableExe = Assert-PortableArchive $PortableZipPath $Version $vcRedistPin

    if ($RunPlatformTests) {
        if ([string]::IsNullOrWhiteSpace($PlatformTestsZipPath)) {
            $PlatformTestsZipPath = Download-ReleaseAsset $PlatformTestsAssetName $Version $Repository $(if ($ReleaseTag) { $ReleaseTag } else { "bootstrap-v$Version" }) $GitHubToken (Join-Path $downloadRoot $PlatformTestsAssetName)
        } else {
            $PlatformTestsZipPath = (Resolve-Path -LiteralPath $PlatformTestsZipPath).Path
        }
        Assert-FileSha256 $PlatformTestsZipPath $PlatformTestsSha256 'Platform.Tests ZIP'
    }

    # The built-in token is needed only for the release-asset API calls. Do not
    # let a precompiled app, test host, compiler, or installer child process
    # inherit it through either conventional environment variable.
    Clear-WorkflowTokens

    if ($RunPlatformTests) {
        Assert-PlatformTestsArchive $PlatformTestsZipPath
    }

    Clear-OutputRoot $output
    $publishDir = Join-Path $repoRoot 'publish\win-x64'
    # The copied Inno script resolves these paths relative to the repository
    # root. Keep its scratch tree fixed, then copy only final artifacts to a
    # caller-selected output directory.
    $innoArtifacts = Join-Path $repoRoot 'artifacts'
    $installerArtifacts = Join-Path $innoArtifacts 'installer'
    $vcRedist = Join-Path $innoArtifacts 'vc_redist.x64.exe'
    $vcRedistEvidence = Join-Path $innoArtifacts 'VCREDIST-PROVENANCE.txt'
    foreach ($path in @($publishDir, $installerArtifacts, $vcRedist, $vcRedistEvidence)) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Fail "Release staging path must not be a reparse point: $path"
            }
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Force -Path $publishDir, $installerArtifacts | Out-Null
    Copy-Item -Path (Join-Path $portableStage '*') -Destination $publishDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $publishDir 'vc_redist.x64.exe') -Destination $vcRedist -Force
    Remove-Item -LiteralPath (Join-Path $publishDir 'vc_redist.x64.exe') -Force
    Copy-Item -LiteralPath (Join-Path $publishDir 'VCREDIST-PROVENANCE.txt') -Destination $vcRedistEvidence -Force
    # Inno adds the repository-owned README, VC++ provenance, and notices
    # explicitly below. Remove the portable copies so the installed package
    # has one deterministic copy of each payload file.
    foreach ($noticeName in @('README.txt', 'VCREDIST-PROVENANCE.txt', 'THIRD_PARTY_NOTICES.md', 'DOTNET_THIRD_PARTY_NOTICES.txt')) {
        $stagedNotice = Join-Path $publishDir $noticeName
        if (-not (Test-Path -LiteralPath $stagedNotice -PathType Leaf)) {
            Fail "Portable staging did not contain required notice '$noticeName'."
        }
        Remove-Item -LiteralPath $stagedNotice -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'release\PORTABLE-README.txt') -PathType Leaf)) {
        Fail 'Repository-owned PORTABLE-README.txt is missing for the installer payload.'
    }

    $iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($null -eq $iscc) { Fail 'iscc.exe is required. Install the pinned Inno Setup package before running this script.' }
    $iss = Join-Path $repoRoot 'installer\VoiceDictation.iss'
    Clear-WorkflowTokens
    & $iscc.Source '/Qp' "/DAPP_VERSION=$Version" $iss
    if ($LASTEXITCODE -ne 0) { Fail "Inno Setup exited with code $LASTEXITCODE." }
    $expectedSetupName = "Voice-Dictation-Windows-x64-$Version-Setup.exe"
    $setupMatches = @(Get-ChildItem -LiteralPath $installerArtifacts -Filter $expectedSetupName -File -Recurse)
    if ($setupMatches.Count -ne 1) { Fail 'Inno Setup must produce exactly one expected versioned setup executable.' }
    $setup = $setupMatches[0]
    $portableOut = Join-Path $output "Voice-Dictation-Windows-x64-$Version-Portable.zip"
    Copy-Item -LiteralPath $PortableZipPath -Destination $portableOut -Force
    $setupOut = Join-Path $output $setup.Name
    Copy-Item -LiteralPath $setup.FullName -Destination $setupOut -Force

    $expectedOutputNames = @(
        [System.IO.Path]::GetFileName($portableOut)
        [System.IO.Path]::GetFileName($setupOut)
        'SHA256SUMS.json'
        'SHA256SUMS.txt'
    )
    $unexpectedOutput = @(Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Name -notin $expectedOutputNames })
    if ($unexpectedOutput.Count -gt 0) { Fail "OutputRoot contains unexpected release files: $($unexpectedOutput.Name -join ', ')" }

    Invoke-InstallerSmoke $setupOut $Version
    Invoke-PinnedInference $portableExe

    $releaseFiles = @($setupOut, $portableOut)
    $manifest = @($releaseFiles | ForEach-Object {
        $item = Get-Item -LiteralPath $_
        [ordered]@{
            name = $item.Name
            size = $item.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash.ToLowerInvariant()
            platform = 'windows-x64'
            version = $Version
        }
    })
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.json') -Encoding utf8
    @($manifest | ForEach-Object { "$($_.sha256)  $($_.name)" }) | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
    Write-Host "Distribution artifacts written to $output"
} finally {
    foreach ($path in @($downloadRoot, $installRoot, (Join-Path $repoRoot 'publish'))) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'artifacts\installer')) {
        Remove-Item -LiteralPath (Join-Path $repoRoot 'artifacts\installer') -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'artifacts\vc_redist.x64.exe')) {
        Remove-Item -LiteralPath (Join-Path $repoRoot 'artifacts\vc_redist.x64.exe') -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'artifacts\VCREDIST-PROVENANCE.txt')) {
        Remove-Item -LiteralPath (Join-Path $repoRoot 'artifacts\VCREDIST-PROVENANCE.txt') -Force -ErrorAction SilentlyContinue
    }
}
