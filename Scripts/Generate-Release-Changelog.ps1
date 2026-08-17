[CmdletBinding()]
param(
    [string] $RepositoryPath = (Join-Path $PSScriptRoot ".."),
    [string] $CurrentRef = "HEAD",
    [Parameter(Mandatory)]
    [string] $Version,
    [string] $OutputPath = "CHANGELOG.md"
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path

function Invoke-RepositoryGit {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $output = & git -C $repository @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "git $($Arguments -join ' ') failed with exit code ${exitCode}:`n$details"
    }

    if ($exitCode -ne 0) {
        return @()
    }
    return @($output | ForEach-Object { $_.ToString() })
}

Invoke-RepositoryGit -Arguments @("rev-parse", "--verify", "${CurrentRef}^{commit}") | Out-Null

$previousTag = Invoke-RepositoryGit `
    -Arguments @("describe", "--tags", "--abbrev=0", "--match", "*.*.*", "${CurrentRef}^") `
    -AllowFailure |
    Select-Object -First 1

$range = $CurrentRef
if (-not [string]::IsNullOrWhiteSpace($previousTag)) {
    $previousTag = $previousTag.Trim()
    $range = "${previousTag}..${CurrentRef}"
}

$notes = [System.Collections.Generic.List[string]]::new()
$recordSeparator = [char]0x1e
$fieldSeparator = [char]0x1f
$log = (Invoke-RepositoryGit -Arguments @(
    "log",
    "--no-merges",
    "--format=%s%x1f%B%x1e",
    $range
)) -join "`n"

foreach ($record in $log.Split($recordSeparator, [StringSplitOptions]::RemoveEmptyEntries)) {
    $separatorIndex = $record.IndexOf($fieldSeparator)
    if ($separatorIndex -lt 0) {
        continue
    }

    $subject = $record.Substring(0, $separatorIndex).Trim()
    $message = $record.Substring($separatorIndex + 1).Trim()
    if ($message -match "(?i)\[skip changelog\]") {
        continue
    }

    $subject = ($subject -replace "(?i)\s*\[(?:skip ci|ci skip)\]\s*", " ").Trim()
    if (-not [string]::IsNullOrWhiteSpace($subject)) {
        $notes.Add("- $subject")
    }
}

if ($notes.Count -eq 0) {
    $notes.Add("- Internal maintenance and compatibility improvements")
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Changelog")
$lines.Add("")
$lines.Add("## $Version")
$lines.Add("")
foreach ($note in $notes) {
    $lines.Add($note)
}

$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $repository $OutputPath
}

$outputDirectory = Split-Path -Parent $resolvedOutput
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Set-Content -LiteralPath $resolvedOutput -Value $lines -Encoding utf8NoBOM
Write-Host "Generated $resolvedOutput from $range with $($notes.Count) release note(s)."
