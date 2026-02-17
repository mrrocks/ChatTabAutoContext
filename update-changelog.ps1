param(
    [string]$OutputPath = "CHANGELOG.txt",
    [string]$Title = "Chat Tabs Auto Context (@project-version@)",
    [int]$MaxEntries = 5,
    [int]$MaxLength = 0,
    [string]$FromRef = "",
    [string]$ExcludePattern = "^(trigger packaging|update changelog(\\.txt)?|chore: trigger packaging)$"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ($MaxEntries -lt 1) {
    throw "MaxEntries must be at least 1."
}

if ($MaxLength -ne 0 -and $MaxLength -lt 20) {
    throw "MaxLength must be 0 or at least 20."
}

function Get-LatestTag {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $tag = git describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -ne 0) {
            return ""
        }
        return ($tag | Select-Object -First 1).Trim()
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Format-ChangelogEntry {
    param(
        [string]$Text,
        [int]$Limit
    )

    $value = (($Text -replace "\s+", " ").Trim())
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    if ($Limit -gt 0 -and $value.Length -gt $Limit) {
        $value = $value.Substring(0, $Limit).TrimEnd(" ", ".", ",", ";", ":") + "..."
    }

    if (-not $value.EndsWith(".")) {
        $value += "."
    }

    return $value
}

$range = "HEAD"
if (-not [string]::IsNullOrWhiteSpace($FromRef)) {
    $range = "$FromRef..HEAD"
} else {
    $latestTag = Get-LatestTag
    if (-not [string]::IsNullOrWhiteSpace($latestTag)) {
        $range = "$latestTag..HEAD"
    }
}

$rawSubjects = git log $range --pretty=format:%s --no-merges
if ($LASTEXITCODE -ne 0) {
    throw "Failed to read git history for range '$range'."
}

$entries = @()
foreach ($subject in $rawSubjects) {
    $rawValue = ($subject -replace "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        continue
    }
    if ($rawValue -imatch $ExcludePattern) {
        continue
    }
    $candidate = Format-ChangelogEntry -Text $subject -Limit $MaxLength
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        continue
    }
    $entries += $candidate
    if ($entries.Count -ge $MaxEntries) {
        break
    }
}

if ($entries.Count -eq 0) {
    $entries = @("Maintenance update.")
}

$lines = @($Title, "")
foreach ($entry in $entries) {
    $lines += "- $entry"
}

$resolvedPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
[System.IO.File]::WriteAllLines($resolvedPath, $lines, [System.Text.UTF8Encoding]::new($false))
