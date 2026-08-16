function Select-ExactRelease {
    param(
        [AllowNull()][object[]]$Response,
        [Parameter(Mandatory = $true)][string]$ExpectedTag,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $matches = @(
        foreach ($candidate in $Response) {
            if ($null -eq $candidate) { continue }
            $tagProperty = $candidate.PSObject.Properties['tag_name']
            if ($null -eq $tagProperty) { continue }
            $candidateTag = $tagProperty.Value
            if ($candidateTag -is [System.Array]) {
                throw "$Source returned an aggregated tag_name array; release objects must be enumerated individually."
            }
            if ([string]$candidateTag -ceq $ExpectedTag) {
                $candidate
            }
        }
    )

    if ($matches.Count -ne 1) {
        throw "$Source must contain exactly one release object with tag '$ExpectedTag'; found $($matches.Count)."
    }
    return $matches[0]
}
