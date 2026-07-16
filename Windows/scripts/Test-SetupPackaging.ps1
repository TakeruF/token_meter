[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$appProject = Join-Path $repositoryRoot 'Windows\src\TokenMeter.Windows.App\TokenMeter.Windows.App.csproj'
$appManifest = Join-Path $repositoryRoot 'Windows\src\TokenMeter.Windows.App\Package.appxmanifest'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "TokenMeterSetupTest-$([Guid]::NewGuid().ToString('N'))"
$packageDirectory = Join-Path $testRoot 'package'
$setupDirectory = Join-Path $testRoot 'setup'
$pfxPath = Join-Path $testRoot 'test-signing.pfx'
$cerPath = Join-Path $testRoot 'test-signing.cer'
$certificatePassword = [Guid]::NewGuid().ToString('N')
$securePassword = ConvertTo-SecureString -String $certificatePassword -AsPlainText -Force
$signingCertificate = $null
$trustedCertificate = $null

New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null

try {
    $manifestDocument = [xml][System.IO.File]::ReadAllText($appManifest)
    $identityElement = $manifestDocument.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
    $publisher = $identityElement.GetAttribute('Publisher')
    if ([string]::IsNullOrWhiteSpace($publisher)) {
        throw 'Package.appxmanifest does not define Identity/Publisher.'
    }

    $signingCertificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $publisher `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddDays(1)
    Export-PfxCertificate `
        -Cert $signingCertificate `
        -FilePath $pfxPath `
        -Password $securePassword | Out-Null
    Export-Certificate `
        -Cert $signingCertificate `
        -FilePath $cerPath | Out-Null
    $trustedCertificate = Import-Certificate `
        -FilePath $cerPath `
        -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople'

    $publishArguments = @(
        'restore',
        $appProject,
        '-p:Platform=x64',
        '-p:RuntimeIdentifier=win-x64',
        '-p:SelfContained=true',
        '-p:WindowsAppSDKSelfContained=true',
        '--locked-mode'
    )
    & dotnet @publishArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Test MSIX restore failed with exit code $LASTEXITCODE."
    }

    $publishArguments = @(
        'publish',
        $appProject,
        '--configuration', 'Release',
        '--no-restore',
        '-p:Platform=x64',
        '-p:RuntimeIdentifier=win-x64',
        '-p:SelfContained=true',
        '-p:WindowsAppSDKSelfContained=true',
        '-p:GenerateAppxPackageOnBuild=true',
        '-p:AppxPackageSigningEnabled=true',
        "-p:PackageCertificateKeyFile=$pfxPath",
        "-p:PackageCertificatePassword=$certificatePassword",
        '-p:AppxBundle=Never',
        '-p:UapAppxPackageBuildMode=SideloadOnly',
        "-p:AppxPackageDir=$packageDirectory\"
    )
    & dotnet @publishArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Test MSIX build failed with exit code $LASTEXITCODE."
    }

    $msix = Get-ChildItem -LiteralPath $packageDirectory -Filter '*.msix' -File -Recurse |
        Select-Object -First 1
    if ($null -eq $msix) {
        throw 'The test MSIX package was not generated.'
    }

    & (Join-Path $PSScriptRoot 'Build-Setup.ps1') `
        -MsixPath $msix.FullName `
        -DeferSetupSigning `
        -OutputDirectory $setupDirectory | Out-Host

    $setupPath = Join-Path $setupDirectory 'TokenMeterSetup.exe'
    & $setupPath '--verify-payload'
    if ($LASTEXITCODE -ne 0) {
        throw "The generated Setup.exe could not read its embedded MSIX payload. Exit code: $LASTEXITCODE."
    }

    Write-Host 'Setup.exe packaging smoke test passed.'
}
finally {
    if ($null -ne $trustedCertificate) {
        Remove-Item -LiteralPath $trustedCertificate.PSPath -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $signingCertificate) {
        Remove-Item -LiteralPath $signingCertificate.PSPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
