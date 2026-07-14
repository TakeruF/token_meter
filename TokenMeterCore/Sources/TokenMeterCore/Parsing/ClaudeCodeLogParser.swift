import Foundation

/// Parses `~/.claude/projects/<slug>/<sessionId>.jsonl`.
///
/// Field names below were read off real transcripts on 2026-07-14; see
/// docs/data-sources.md. Nothing here is inferred.
///
/// The single most important behaviour: Claude Code writes the *same* `usage`
/// object on every line belonging to one assistant message (one line per content
/// block). Measured on this machine: 2340 usage-bearing lines collapsed to 866
/// real messages. Summing lines naively overcounts ~2.7x, so every event carries
/// the dedup key `message.id|requestId` and the store treats it as a primary key.
public struct ClaudeCodeLogParser: Sendable {

    public struct Result: Sendable {
        public var events: [UsageEvent]
        /// Last message seen, used for "current model" and current context length.
        public var latestModel: String?
        public var latestContextTokens: Int?
        public var latestTimestamp: Date?
        /// Lines that looked like usage records but would not decode. Non-zero is
        /// normal only when the tail is mid-write; if it equals `candidateLineCount`
        /// the format has moved.
        public var malformedLineCount: Int = 0
        /// Lines that passed the cheap pre-filter and were actually parsed.
        public var candidateLineCount: Int = 0
        public var totalLineCount: Int = 0
    }

    public init() {}

    /// Models that never hit the API; their usage is not real consumption.
    private static let syntheticModels: Set<String> = ["<synthetic>"]

    public func parse(lines: [String], sessionID: String? = nil) -> Result {
        var result = Result(events: [], latestModel: nil, latestContextTokens: nil, latestTimestamp: nil)
        result.totalLineCount = lines.count

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Most of a transcript by volume is prompt and response text on lines we
            // are going to discard anyway. JSON-decoding all of it made the first
            // scan take minutes, so gate on a cheap substring first. This is only a
            // filter — everything that passes is still fully parsed and validated,
            // so a false positive costs nothing.
            guard trimmed.contains("\"usage\"") else { continue }
            result.candidateLineCount += 1

            guard let data = trimmed.data(using: .utf8) else {
                result.malformedLineCount += 1
                continue
            }
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.malformedLineCount += 1
                continue
            }

            guard root["type"] as? String == "assistant" else { continue }
            guard let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let model = message["model"] as? String
            if let model, Self.syntheticModels.contains(model) { continue }

            // Without a message id we cannot dedupe, and counting it risks
            // inflating totals — so we skip rather than guess an id.
            guard let messageID = message["id"] as? String, !messageID.isEmpty else { continue }
            let requestID = root["requestId"] as? String ?? ""

            guard let timestamp = LogDate.parse(root["timestamp"] as? String) else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let total = input + cacheRead + cacheCreation + output
            guard total > 0 else { continue }

            let event = UsageEvent(
                id: "\(messageID)|\(requestID)",
                provider: .claudeCode,
                timestamp: timestamp,
                model: model,
                sessionID: root["sessionId"] as? String ?? sessionID,
                inputTokens: input,
                cachedInputTokens: cacheRead,
                cacheCreationTokens: cacheCreation,
                outputTokens: output,
                // Claude Code does not break out reasoning tokens; thinking is
                // folded into output_tokens. Reporting 0 here would be a lie.
                reasoningTokens: nil,
                totalTokens: total,
                source: .localLog
            )
            result.events.append(event)

            if result.latestTimestamp == nil || timestamp >= result.latestTimestamp! {
                result.latestTimestamp = timestamp
                result.latestModel = model
                // The context carried into this request: everything the model read.
                result.latestContextTokens = input + cacheRead + cacheCreation
            }
        }

        return result
    }
}
