using System.Text;
using System.Security.Cryptography;

namespace TokenMeter.Core;

public sealed record IncrementalReadResult(
    IReadOnlyList<string> Lines,
    long NewOffset,
    bool DidReset,
    string PrefixFingerprint);

public static class JsonlReader
{
    public static IncrementalReadResult ReadNewLines(
        string path,
        long offset,
        string? expectedPrefixFingerprint = null)
    {
        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);

            var fingerprint = PrefixFingerprint(stream);
            var start = Math.Max(0, offset);
            var didReset = expectedPrefixFingerprint is not null &&
                !string.Equals(expectedPrefixFingerprint, fingerprint, StringComparison.Ordinal);
            if (didReset)
            {
                start = 0;
            }
            if (stream.Length < start)
            {
                start = 0;
                didReset = true;
            }

            if (stream.Length <= start)
            {
                return new IncrementalReadResult([], stream.Length, didReset, fingerprint);
            }

            stream.Seek(start, SeekOrigin.Begin);
            using var buffer = new MemoryStream();
            stream.CopyTo(buffer);
            var bytes = buffer.ToArray();
            var lastNewline = Array.LastIndexOf(bytes, (byte)'\n');
            if (lastNewline < 0)
            {
                return new IncrementalReadResult([], start, didReset, fingerprint);
            }

            var consumed = lastNewline + 1;
            var text = Encoding.UTF8.GetString(bytes, 0, consumed);
            var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
            return new IncrementalReadResult(lines, start + consumed, didReset, fingerprint);
        }
        catch (UnauthorizedAccessException error)
        {
            throw new UsageProviderException($"Access denied: {path}", error);
        }
        catch (FileNotFoundException error)
        {
            throw new UsageProviderException($"Log file not found: {path}", error);
        }
        catch (DirectoryNotFoundException error)
        {
            throw new UsageProviderException($"Log directory not found: {path}", error);
        }
    }

    private static string PrefixFingerprint(FileStream stream)
    {
        var length = checked((int)Math.Min(stream.Length, 4096));
        var prefix = new byte[length];
        stream.Seek(0, SeekOrigin.Begin);
        var read = stream.Read(prefix, 0, length);
        stream.Seek(0, SeekOrigin.Begin);
        var newline = Array.IndexOf(prefix, (byte)'\n', 0, read);
        var stableLength = newline >= 0 ? newline + 1 : read;
        return Convert.ToHexString(SHA256.HashData(prefix.AsSpan(0, stableLength)));
    }
}

internal static class LogDate
{
    public static DateTimeOffset? Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return DateTimeOffset.TryParse(
            value,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal |
                System.Globalization.DateTimeStyles.AdjustToUniversal,
            out var date)
            ? date
            : null;
    }
}
