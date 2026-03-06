param(
    [string]$OutputPath = "CHANGELOG.txt",
    [string]$StatePath = ".changelog-state",
    [string]$Title = "Chat Tabs Auto Context (@project-version@)",
    [int]$MaxEntries = 5,
    [int]$MaxLength = 0,
    [string]$FromRef = "",
    [string]$ExcludePattern = "^(trigger packaging|chore: trigger packaging|update changelog(\.txt)?(\b.*)?)$"
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

function Get-HeadCommit {
    $commit = git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve HEAD."
    }
    return ($commit | Select-Object -First 1).Trim()
}

function Test-CommitExists {
    param(
        [string]$Commitish
    )

    if ([string]::IsNullOrWhiteSpace($Commitish)) {
        return $false
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        git rev-parse --verify "$Commitish^{commit}" 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Get-RepositoryRoot {
    $root = git rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve the git repository root."
    }
    return ($root | Select-Object -First 1).Trim()
}

function Get-RepositoryRelativePath {
    param(
        [string]$Path,
        [string]$RepositoryRoot
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\", "/")
    $fullRepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd("\", "/")
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if ($fullPath.Equals($fullRepositoryRoot, $comparison)) {
        return ""
    }

    $repositoryRootPrefix = $fullRepositoryRoot + "\"
    if (-not $fullPath.StartsWith($repositoryRootPrefix, $comparison)) {
        return ""
    }

    $relativePath = $fullPath.Substring($repositoryRootPrefix.Length)
    return ($relativePath -replace "\\", "/")
}

function Get-StateRef {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    if (-not [System.IO.File]::Exists($resolvedPath)) {
        return ""
    }

    $value = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8).Trim()
    if (-not (Test-CommitExists -Commitish $value)) {
        return ""
    }

    return $value
}

function Set-StateRef {
    param(
        [string]$Path,
        [string]$Commit
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Commit)) {
        return
    }

    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    $directory = [System.IO.Path]::GetDirectoryName($resolvedPath)
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not [System.IO.Directory]::Exists($directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    [System.IO.File]::WriteAllText($resolvedPath, $Commit + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Get-CommitChangedPaths {
    param(
        [string]$Commit
    )

    $paths = git diff-tree --root --no-commit-id --name-only -r $Commit
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read changed files for commit '$Commit'."
    }

    return @(
        $paths |
            ForEach-Object { ($_ -replace "\\", "/").Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Test-IsOutputOnlyCommit {
    param(
        [string]$Commit,
        [string]$OutputPathRelativeToRepo
    )

    if ([string]::IsNullOrWhiteSpace($OutputPathRelativeToRepo)) {
        return $false
    }

    $changedPaths = Get-CommitChangedPaths -Commit $Commit
    if ($changedPaths.Count -ne 1) {
        return $false
    }

    return $changedPaths[0] -ieq $OutputPathRelativeToRepo
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

$headCommit = Get-HeadCommit
$resolvedPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
$repositoryRoot = Get-RepositoryRoot
$outputPathRelativeToRepo = Get-RepositoryRelativePath -Path $resolvedPath -RepositoryRoot $repositoryRoot
$shouldPersistState = [string]::IsNullOrWhiteSpace($FromRef) -and -not [string]::IsNullOrWhiteSpace($StatePath)
$range = "HEAD"

if (-not [string]::IsNullOrWhiteSpace($FromRef)) {
    $range = "$FromRef..HEAD"
} else {
    $stateRef = Get-StateRef -Path $StatePath
    if (-not [string]::IsNullOrWhiteSpace($stateRef)) {
        $range = "$stateRef..HEAD"
    } else {
        $latestTag = Get-LatestTag
        if (-not [string]::IsNullOrWhiteSpace($latestTag)) {
            $range = "$latestTag..HEAD"
        }
    }
}

$rawCommits = git log $range --pretty=format:%H%x1f%s --no-merges
if ($LASTEXITCODE -ne 0) {
    throw "Failed to read git history for range '$range'."
}

$entries = @()
foreach ($commitLine in $rawCommits) {
    $parts = $commitLine -split ([string][char]0x1f), 2
    if ($parts.Count -ne 2) {
        continue
    }

    $commit = $parts[0].Trim()
    $subject = $parts[1]
    $rawValue = ($subject -replace "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        continue
    }
    if ($rawValue -imatch $ExcludePattern) {
        continue
    }
    if (Test-IsOutputOnlyCommit -Commit $commit -OutputPathRelativeToRepo $outputPathRelativeToRepo) {
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

[System.IO.File]::WriteAllLines($resolvedPath, $lines, [System.Text.UTF8Encoding]::new($false))
if ($shouldPersistState) {
    Set-StateRef -Path $StatePath -Commit $headCommit
}
