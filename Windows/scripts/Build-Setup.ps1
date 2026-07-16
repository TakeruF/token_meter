[CmdletBinding(DefaultParameterSetName = 'Pfx')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$MsixPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')]
    [string]$CertificatePassword,

    [Parameter(Mandatory = $true, ParameterSetName = 'Deferred')]
    [switch]$DeferSetupSigning,

    [Parameter(ParameterSetName = 'Deferred')]
    [string]$UntrustedTestSignerThumbprint,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\setup'),

    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SignToolPath {
    $command = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $candidate = Get-ChildItem -LiteralPath $kitsRoot -Filter 'signtool.exe' -File -Recurse |
        Where-Object { $_.DirectoryName -match '\\x64$' } |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw 'signtool.exe was not found. Install the Windows 11 SDK.'
    }

    return $candidate.FullName
}

function Assert-SignatureValid {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [string]$AllowedUntrustedSignerThumbprint
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) {
        return
    }

    $isExplicitTestSigner =
        -not [string]::IsNullOrWhiteSpace($AllowedUntrustedSignerThumbprint) -and
        $null -ne $signature.SignerCertificate -and
        [string]::Equals(
            $signature.SignerCertificate.Thumbprint,
            $AllowedUntrustedSignerThumbprint,
            [System.StringComparison]::OrdinalIgnoreCase) -and
        $signature.Status -in @(
            [System.Management.Automation.SignatureStatus]::NotTrusted,
            [System.Management.Automation.SignatureStatus]::UnknownError)
    if ($isExplicitTestSigner) {
        Write-Warning "$Description uses the expected untrusted test signer. Production builds still require a trusted signature."
        return
    }

    throw "$Description does not have a trusted, valid signature. Status: $($signature.Status). $($signature.StatusMessage)"
}

$resolvedMsixPath = (Resolve-Path -LiteralPath $MsixPath).Path
if ([System.IO.Path]::GetExtension($resolvedMsixPath) -ne '.msix') {
    throw 'MsixPath must point to a .msix package, not an upload bundle.'
}

Assert-SignatureValid `
    -Path $resolvedMsixPath `
    -Description 'The embedded MSIX package' `
    -AllowedUntrustedSignerThumbprint $UntrustedTestSignerThumbprint

$setupProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\src\TokenMeter.Windows.Setup\TokenMeter.Windows.Setup.csproj')).Path
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$publishDirectory = Join-Path $resolvedOutputDirectory '.publish'
$finalSetup = Join-Path $resolvedOutputDirectory 'TokenMeterSetup.exe'
$checksumPath = Join-Path $resolvedOutputDirectory 'SHA256SUMS.txt'

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null
Remove-Item -LiteralPath $finalSetup -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue

$restoreArguments = @(
    'restore',
    $setupProject,
    '--runtime', 'win-x64',
    '-p:Platform=x64',
    '--locked-mode'
)
& dotnet @restoreArguments
if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore failed with exit code $LASTEXITCODE."
}

$publishArguments = @(
    'publish',
    $setupProject,
    '--configuration', 'Release',
    '--no-restore',
    '--runtime', 'win-x64',
    '--self-contained', 'true',
    '-p:Platform=x64',
    "-p:MsixPackagePath=$resolvedMsixPath",
    '--output', $publishDirectory
)
& dotnet @publishArguments
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$publishedSetup = Join-Path $publishDirectory 'TokenMeterSetup.exe'
if (-not (Test-Path -LiteralPath $publishedSetup -PathType Leaf)) {
    throw "The setup executable was not generated: $publishedSetup"
}

if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
    $resolvedCertificatePath = (Resolve-Path -LiteralPath $CertificatePath).Path
    $signTool = Get-SignToolPath
    $signArguments = @(
        'sign',
        '/fd', 'SHA256',
        '/f', $resolvedCertificatePath,
        '/p', $CertificatePassword,
        '/tr', $TimestampUrl,
        '/td', 'SHA256',
        $publishedSetup
    )
    & $signTool @signArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Signing TokenMeterSetup.exe failed with exit code $LASTEXITCODE."
    }

    Assert-SignatureValid -Path $publishedSetup -Description 'TokenMeterSetup.exe'

    & $publishedSetup '--verify-payload'
    if ($LASTEXITCODE -ne 0) {
        throw 'The generated Setup.exe rejected its MSIX payload. Build the direct-distribution MSIX with SelfContained=true and WindowsAppSDKSelfContained=true.'
    }
}

Copy-Item -LiteralPath $publishedSetup -Destination $finalSetup -Force
Remove-Item -LiteralPath $publishDirectory -Recurse -Force

$sha256 = $null
if (-not $DeferSetupSigning.IsPresent) {
    $hash = Get-FileHash -LiteralPath $finalSetup -Algorithm SHA256
    $sha256 = $hash.Hash.ToLowerInvariant()
    $checksum = "$sha256  TokenMeterSetup.exe`r`n"
    [System.IO.File]::WriteAllText(
        $checksumPath,
        $checksum,
        [System.Text.UTF8Encoding]::new($false))
}

[pscustomobject]@{
    SetupPath = $finalSetup
    Sha256 = $sha256
    SetupSigningDeferred = $DeferSetupSigning.IsPresent
}
