[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$ReleaseTag,

    [string]$GitHubOutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $repositoryRoot
try {
    & git show-ref --verify --quiet "refs/tags/$ReleaseTag"
    if ($LASTEXITCODE -ne 0) {
        throw "Release tag '$ReleaseTag' is not present in the checkout."
    }

    $tagCommit = (& git rev-list -n 1 $ReleaseTag).Trim()
    $headCommit = (& git rev-parse HEAD).Trim()
    if ($tagCommit -ne $headCommit) {
        throw "HEAD $headCommit is not the commit selected by $ReleaseTag ($tagCommit)."
    }

    & git fetch --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not fetch origin/main for release ancestry verification.'
    }
    & git merge-base --is-ancestor $tagCommit 'refs/remotes/origin/main'
    if ($LASTEXITCODE -ne 0) {
        throw "Release tag '$ReleaseTag' is not reachable from origin/main."
    }

    $dirtyPaths = @(& git status --porcelain=v1 --untracked-files=all)
    if ($dirtyPaths.Count -ne 0) {
        throw "Release checkout is not clean:`n$($dirtyPaths -join "`n")"
    }

    & (Join-Path $PSScriptRoot 'Test-ReleaseMetadata.ps1') `
        -ReleaseTag $ReleaseTag `
        -GitHubOutputPath $GitHubOutputPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Release metadata verification failed.'
    }

    Write-Host "Release source is the clean $ReleaseTag commit $tagCommit on main."
}
finally {
    Pop-Location
}
