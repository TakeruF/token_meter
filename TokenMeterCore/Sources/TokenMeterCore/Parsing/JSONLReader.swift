import Foundation

/// Remembers how far into a file we have already parsed, so an append-only log is
/// never re-read from the top (and never double-counted).
public struct FileCursor: Codable, Sendable, Equatable {
    public let path: String
    public let offset: UInt64

    public init(path: String, offset: UInt64) {
        self.path = path
        self.offset = offset
    }
}

public struct IncrementalReadResult: Sendable {
    /// Only whole lines. A trailing fragment (the writer is mid-append) is excluded.
    public let lines: [String]
    public let newOffset: UInt64
    /// True when the file shrank, meaning it was rotated/truncated and we restarted at 0.
    public let didReset: Bool
}

public enum JSONLReader {
    /// Reads the bytes appended since `offset`.
    ///
    /// Two safety rules that matter for live logs:
    /// - a trailing partial line is left unconsumed, so the next pass re-reads it once complete;
    /// - if the file is now shorter than `offset` it was truncated, so we start over from 0.
    public static func readNewLines(at path: String, from offset: UInt64) throws -> IncrementalReadResult {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        } catch {
            if (error as NSError).code == NSFileReadNoPermissionError {
                throw UsageProviderError.permissionDenied(path)
            }
            throw UsageProviderError.sourceNotFound(path)
        }
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        var start = offset
        var didReset = false
        if size < offset {
            start = 0
            didReset = true
        }
        guard size > start else {
            return IncrementalReadResult(lines: [], newOffset: size, didReset: didReset)
        }

        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        guard !data.isEmpty else {
            return IncrementalReadResult(lines: [], newOffset: start, didReset: didReset)
        }

        let newline = UInt8(ascii: "\n")
        // Consume only up to the last newline; anything after it is a partial write.
        guard let lastNewline = data.lastIndex(of: newline) else {
            return IncrementalReadResult(lines: [], newOffset: start, didReset: didReset)
        }

        let complete = data[data.startIndex...lastNewline]
        let consumed = UInt64(complete.count)
        let text = String(decoding: complete, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        return IncrementalReadResult(
            lines: lines,
            newOffset: start + consumed,
            didReset: didReset
        )
    }
}

/// Timestamps in both logs are ISO8601 with fractional seconds, but the parsers
/// tolerate the plain form too rather than dropping a record over it.
public enum LogDate {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    public static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return (try? withFraction.parse(string)) ?? (try? plain.parse(string))
    }
}
