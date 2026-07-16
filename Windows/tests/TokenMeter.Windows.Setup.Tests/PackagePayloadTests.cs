using System.IO.Compression;
using System.Text;
using System.Xml;
using TokenMeter.Windows.Setup;
using Xunit;

namespace TokenMeter.Windows.Setup.Tests;

public sealed class PackagePayloadTests
{
    [Fact]
    public void ReadMetadataReturnsIdentityVersionAndApplicationId()
    {
        using var package = CreatePackage(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
              <Identity Name="com.tokenmeter.windows" Publisher="CN=TakeruF" Version="1.3.0.0" />
              <Applications>
                <Application Id="App" Executable="TokenMeter.exe" EntryPoint="Windows.FullTrustApplication" />
              </Applications>
            </Package>
            """);

        var metadata = PackagePayload.ReadMetadata(package);

        Assert.Equal("com.tokenmeter.windows", metadata.IdentityName);
        Assert.Equal("CN=TakeruF", metadata.Publisher);
        Assert.Equal(new Version(1, 3, 0, 0), metadata.Version);
        Assert.Equal("App", metadata.ApplicationId);
    }

    [Fact]
    public void ReadMetadataRejectsPackageWithoutManifest()
    {
        using var package = new MemoryStream();
        using (var archive = new ZipArchive(package, ZipArchiveMode.Create, leaveOpen: true))
        {
            archive.CreateEntry("payload.txt");
        }
        package.Position = 0;

        Assert.Throws<InvalidDataException>(() => PackagePayload.ReadMetadata(package));
    }

    [Fact]
    public void ReadMetadataRejectsDocumentTypeDeclarations()
    {
        using var package = CreatePackage(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE Package [<!ENTITY publisher "TakeruF">]>
            <Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
              <Identity Name="com.tokenmeter.windows" Publisher="&publisher;" Version="1.3.0.0" />
              <Applications><Application Id="App" /></Applications>
            </Package>
            """);

        Assert.Throws<XmlException>(() => PackagePayload.ReadMetadata(package));
    }

    [Fact]
    public void ReadMetadataRejectsExternalPackageDependencies()
    {
        using var package = CreatePackage(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
              <Identity Name="com.tokenmeter.windows" Publisher="CN=TakeruF" Version="1.3.0.0" />
              <Dependencies>
                <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22000.0" MaxVersionTested="10.0.26100.0" />
                <PackageDependency Name="Microsoft.WindowsAppRuntime.2.2" Publisher="CN=Microsoft Corporation" MinVersion="2000.1.0.0" />
              </Dependencies>
              <Applications><Application Id="App" /></Applications>
            </Package>
            """);

        var exception = Assert.Throws<InvalidDataException>(() => PackagePayload.ReadMetadata(package));
        Assert.Contains("Microsoft.WindowsAppRuntime.2.2", exception.Message, StringComparison.Ordinal);
    }

    private static MemoryStream CreatePackage(string manifest)
    {
        var package = new MemoryStream();
        using (var archive = new ZipArchive(package, ZipArchiveMode.Create, leaveOpen: true))
        {
            var entry = archive.CreateEntry("AppxManifest.xml");
            using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            writer.Write(manifest);
        }
        package.Position = 0;
        return package;
    }
}
