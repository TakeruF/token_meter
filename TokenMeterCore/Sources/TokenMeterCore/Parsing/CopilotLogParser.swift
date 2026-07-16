import Foundation

/// Parses GitHub Copilot CLI transcripts at
/// `~/.copilot/session-state/<uuid>/events.jsonl`.
///
/// Complete, per-model token counts are only written in the `session.shutdown`
/// event's `modelMetrics` block (input / output / cacheRead / cacheWrite). The
/// per-message `outputTokens` on `assistant.message` is partial, so this parser
/// leads with the authoritative shutdown totals. A session's usage therefore
/// lands once it ends — an active session is counted on its next refresh after
/// exit, not mid-flight.
///
/// `modelMetrics` values are cumulative for the session, so — exactly like Codex —
/// events are the delta against what was already stored. The counters are kept
/// per `<sessionID>|<model>` because Copilot reports one bucket per model.
///
/// Storage note: `CodexCumulativeTotals` has no cache-creation field, so the
/// `reasoningTokens` slot carries the cumulative `cacheWriteTokens` here. Copilot
/// never reports reasoning tokens, and the two providers never share a session
/// key, so there is no collision.
public struct CopilotLogParser: Sendable {

    public struct ModelResult: Sendable {
        public let model: String
        public var events: [UsageEvent]
        public var totals: CodexCumulativeTotals
    }

    public struct Result: Sendable {
        public var events: [UsageEvent] = []
        /// Final cumulative totals per model, to persist under `<sessionID>|<model>`.
        public var totalsByModel: [String: CodexCumulativeTotals] = [:]
        public var latestModel: String?
        public var latestTimestamp: Date?
        public var malformedLineCount: Int = 0
        public var candidateLineCount: Int = 0
        public var totalLineCount: Int = 0
    }

    public init() {}

    /// `previousTotalsByModel` holds the last cumulative counters stored for each
    /// model of this session, so a resumed transcript keeps producing correct deltas.
    public func parse(
        lines: [String],
        sessionID: String,
        previousTotalsByModel: [String: CodexCumulativeTotals] = [:]
    ) -> Result {
        var result = Result()
        result.totalLineCount = lines.count
        var totalsByModel = previousTotalsByModel

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Transcripts are dominated by message content and tool output. Gate on a
            // cheap substring so only the rare shutdown line is fully decoded.
            guard trimmed.contains("session.shutdown") else { continue }
            result.candidateLineCount += 1

            guard let data = trimmed.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.malformedLineCount += 1
                continue
            }
            guard root["type"] as? String == "session.shutdown",
                  let payload = root["data"] as? [String: Any],
                  let metrics = payload["modelMetrics"] as? [String: Any] else { continue }
            guard let timestamp = LogDate.parse(root["timestamp"] as? String) else { continue }

            for (model, raw) in metrics {
                guard let entry = raw as? [String: Any],
                      let usage = entry["usage"] as? [String: Any] else { continue }

                let cInput = usage["inputTokens"] as? Int ?? 0
                let cCacheRead = usage["cacheReadTokens"] as? Int ?? 0
                let cCacheWrite = usage["cacheWriteTokens"] as? Int ?? 0
                let cOutput = usage["outputTokens"] as? Int ?? 0
                let cTotal = cInput + cOutput   // cache tokens are a subset of input

                let previous = totalsByModel[model] ?? CodexCumulativeTotals()

                // A decrease means the session's counter restarted; the current value
                // is then the whole of the new consumption.
                let restarted = cTotal < previous.totalTokens
                let dInput = restarted ? cInput : cInput - previous.inputTokens
                let dCacheRead = restarted ? cCacheRead : cCacheRead - previous.cachedInputTokens
                let dCacheWrite = restarted ? cCacheWrite : cCacheWrite - previous.reasoningTokens
                let dOutput = restarted ? cOutput : cOutput - previous.outputTokens
                let dTotal = restarted ? cTotal : cTotal - previous.totalTokens

                let totals = CodexCumulativeTotals(
                    inputTokens: cInput,
                    cachedInputTokens: cCacheRead,
                    outputTokens: cOutput,
                    reasoningTokens: cCacheWrite,   // see storage note above
                    totalTokens: cTotal,
                    eventCount: previous.eventCount + 1
                )
                totalsByModel[model] = totals

                result.latestTimestamp = timestamp
                result.latestModel = model

                guard dTotal > 0 else { continue }

                result.events.append(
                    UsageEvent(
                        id: "\(sessionID)|\(model)|\(totals.eventCount)",
                        provider: .copilotCli,
                        timestamp: timestamp,
                        model: model,
                        sessionID: sessionID,
                        inputTokens: max(0, dInput),
                        cachedInputTokens: max(0, dCacheRead),
                        cacheCreationTokens: max(0, dCacheWrite),
                        outputTokens: max(0, dOutput),
                        reasoningTokens: nil,
                        totalTokens: dTotal,
                        source: .localLog
                    )
                )
            }
        }

        result.totalsByModel = totalsByModel
        return result
    }
}
