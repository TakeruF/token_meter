using System.IO.Compression;
using System.Reflection;
using System.Xml;
using System.Xml.Linq;

namespace TokenMeter.Windows.Setup;

internal sealed record PackageMetadata(
    string IdentityName,
    string Publisher,
    Version Version,
    string ApplicationId);

internal sealed class PackagePayload
{
    private const string ResourceName = "TokenMeter.Windows.Setup.Payload.msix";
    private readonly Assembly _assembly;

    private PackagePayload(Assembly assembly, PackageMetadata metadata)
    {
        _assembly = assembly;
        Metadata = metadata;
    }

    public PackageMetadata Metadata { get; }

    public static PackagePayload Open()
    {
        var assembly = typeof(PackagePayload).Assembly;
        using var stream = OpenResource(assembly);
        var metadata = ReadMetadata(stream);
        return new PackagePayload(assembly, metadata);
    }

    public async Task<string> ExtractAsync(string directory, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, "TokenMeter.msix");

        await using var source = OpenResource(_assembly);
        await using var target = new FileStream(
            destination,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 81920,
            useAsync: true);
        await source.CopyToAsync(target, cancellationToken).ConfigureAwait(false);
        return destination;
    }

    internal static PackageMetadata ReadMetadata(Stream packageStream)
    {
        using var archive = new ZipArchive(packageStream, ZipArchiveMode.Read, leaveOpen: true);
        var manifestEntry = archive.GetEntry("AppxManifest.xml")
            ?? throw new InvalidDataException("AppxManifest.xml was not found in the embedded package.");

        using var manifestStream = manifestEntry.Open();
        using var reader = XmlReader.Create(manifestStream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
        });
        var document = XDocument.Load(reader, LoadOptions.None);
        var root = document.Root ?? throw new InvalidDataException("The package manifest is empty.");
        var ns = root.Name.Namespace;
        var identity = root.Element(ns + "Identity")
            ?? throw new InvalidDataException("The package manifest has no Identity element.");
        var application = root.Element(ns + "Applications")?.Element(ns + "Application")
            ?? throw new InvalidDataException("The package manifest has no Application element.");
        var packageDependencies = root
            .Element(ns + "Dependencies")?
            .Elements(ns + "PackageDependency")
            .Select(element => (string?)element.Attribute("Name") ?? "unknown")
            .ToArray() ?? [];
        if (packageDependencies.Length > 0)
        {
            throw new InvalidDataException(
                $"The embedded package is not self-contained. External package dependencies: {string.Join(", ", packageDependencies)}");
        }

        var identityName = RequiredAttribute(identity, "Name");
        var publisher = RequiredAttribute(identity, "Publisher");
        var versionText = RequiredAttribute(identity, "Version");
        var applicationId = RequiredAttribute(application, "Id");
        if (!Version.TryParse(versionText, out var version))
        {
            throw new InvalidDataException($"The package version is invalid: {versionText}");
        }

        return new PackageMetadata(identityName, publisher, version, applicationId);
    }

    private static Stream OpenResource(Assembly assembly)
    {
        return assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidDataException("The signed MSIX payload is missing.");
    }

    private static string RequiredAttribute(XElement element, string name)
    {
        var value = (string?)element.Attribute(name);
        return string.IsNullOrWhiteSpace(value)
            ? throw new InvalidDataException($"The package manifest attribute {name} is missing.")
            : value;
    }
}
