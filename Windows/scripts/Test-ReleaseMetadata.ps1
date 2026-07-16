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
$centralPropertiesPath = Join-Path $repositoryRoot 'Windows\Directory.Build.props'
$appProjectPath = Join-Path $repositoryRoot 'Windows\src\TokenMeter.Windows.App\TokenMeter.Windows.App.csproj'
$manifestPath = Join-Path $repositoryRoot 'Windows\src\TokenMeter.Windows.App\Package.appxmanifest'

$displayVersion = $ReleaseTag.Substring(1)
$packageVersion = "$displayVersion.0"

$centralProperties = [xml][System.IO.File]::ReadAllText($centralPropertiesPath)
$centralVersion = $centralProperties.Project.PropertyGroup.TokenMeterVersion | Select-Object -First 1
if ($centralVersion -ne $packageVersion) {
    throw "Directory.Build.props TokenMeterVersion '$centralVersion' does not match release tag '$ReleaseTag' (expected $packageVersion)."
}

$appProject = [xml][System.IO.File]::ReadAllText($appProjectPath)
$appDisplayVersion = $appProject.Project.PropertyGroup.ApplicationDisplayVersion | Select-Object -First 1
$appRevision = $appProject.Project.PropertyGroup.ApplicationVersion | Select-Object -First 1
if ($appDisplayVersion -ne $displayVersion -or $appRevision -ne '0') {
    throw "App version metadata '$appDisplayVersion.$appRevision' does not match $packageVersion."
}

$manifest = [xml][System.IO.File]::ReadAllText($manifestPath)
$identity = $manifest.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
if ($null -eq $identity) {
    throw 'Package.appxmanifest does not contain an Identity element.'
}
$manifestVersion = $identity.GetAttribute('Version')
if ($manifestVersion -ne $packageVersion) {
    throw "Package.appxmanifest version '$manifestVersion' does not match $packageVersion."
}

$runtimeProjects = @(
    'Windows\src\TokenMeter.Windows.Core\TokenMeter.Windows.Core.csproj',
    'Windows\src\TokenMeter.Windows.App\TokenMeter.Windows.App.csproj',
    'Windows\src\TokenMeter.Windows.Setup\TokenMeter.Windows.Setup.csproj'
)
foreach ($projectRelativePath in $runtimeProjects) {
    $project = [xml][System.IO.File]::ReadAllText((Join-Path $repositoryRoot $projectRelativePath))
    $overrides = @('Version', 'AssemblyVersion', 'FileVersion', 'InformationalVersion', 'Product', 'Company')
    foreach ($propertyName in $overrides) {
        $node = $project.Project.PropertyGroup.$propertyName | Select-Object -First 1
        if ($null -ne $node) {
            throw "$projectRelativePath overrides centralized $propertyName metadata."
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    [System.IO.File]::AppendAllText(
        $GitHubOutputPath,
        "display_version=$displayVersion`npackage_version=$packageVersion`n",
        [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Release metadata is consistent for $ReleaseTag ($packageVersion)."
