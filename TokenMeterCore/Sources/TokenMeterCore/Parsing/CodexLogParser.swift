import Foundation

/// Cumulative counters carried across one Codex session file.
///
/// `total_token_usage` in a `token_count` event is cumulative *for the session*,
/// so daily figures come from the delta against the previous event. Persisting
/// this per session is what makes re-parsing idempotent.
public struct CodexCumulativeTotals: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int
    public var totalTokens: Int
    /// Number of token_count events already consumed, used to build unique event ids.
    public var eventCount: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningTokens: Int = 0,
        totalTokens: Int = 0,
        eventCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.eventCount = eventCount
    }
}

/// Parses `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// This is the only local source on this machine that reports a usage percentage
/// or a reset time for either tool (see docs/data-sources.md).
public struct CodexLogParser: Sendable {

    public struct Result: Sendable {
        public var events: [UsageEvent]
        public var totalsByModel: [String: CodexCumulativeTotals]
        public var latestModel: String?
        public var latestContextTokens: Int?
        public var contextWindowTokens: Int?
        public var shortWindow: UsageWindow?
        public var weeklyWindow: UsageWindow?
        public var sparkShortWindow: UsageWindow?
        public var sparkWeeklyWindow: UsageWindow?
        public var planType: String?
        public var latestTimestamp: Date?
        var latestRateLimitTimestamp: Date?
        /// Lines that looked like usage records but would not decode.
        public var malformedLineCount: Int = 0
        /// Lines that passed the cheap pre-filter and were actually parsed.
        public var candidateLineCount: Int = 0
        public var totalLineCount: Int = 0

        /// Compatibility aggregate for callers that only need the session total.
        /// Provider persistence uses `totalsByModel` so mixed-model sessions do not
        /// lose their per-model counters.
        public var totals: CodexCumulativeTotals {
            totalsByModel.values.reduce(into: CodexCumulativeTotals()) { total, value in
                total.inputTokens += value.inputTokens
                total.cachedInputTokens += value.cachedInputTokens
                total.outputTokens += value.outputTokens
                total.reasoningTokens += value.reasoningTokens
                total.totalTokens += value.totalTokens
                total.eventCount += value.eventCount
            }
        }
    }

    /// Anything up to a day is treated as the "short" window; a week or longer is
    /// the weekly window. Slot names are deliberately ignored: on this machine
    /// `primary` was the 5h window in some sessions and the weekly window in
    /// others, so classifying by name would mislabel the data.
    static func classify(windowMinutes: Int?) -> WindowKind? {
        guard let windowMinutes else { return nil }
        if windowMinutes <= 1440 { return .short }
        return .weekly
    }

    enum WindowKind { case short, weekly }

    public init() {}

    /// `previousModel` is the model already known for this session. An incremental
    /// read starts mid-file, after the `turn_context` line that names the model, so
    /// without it every resumed chunk would record its usage with no model at all.
    public func parse(
        lines: [String],
        sessionID: String,
        previousTotalsByModel: [String: CodexCumulativeTotals] = [:],
        previousModel: String? = nil
    ) -> Result {
        var totalsByModel = previousTotalsByModel
        var result = Result(events: [], totalsByModel: totalsByModel)
        result.totalLineCount = lines.count

        // turn_context precedes the token_count events of that turn, so the most
        // recent one names the model that produced the usage.
        var currentModel: String? = previousModel

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Rollout logs are mostly reasoning traces, tool output and diffs — none
            // of which we read. Decoding every line of ~600 MB took minutes, so gate
            // on a cheap substring first. Whatever passes is still fully parsed and
            // type-checked below, so a false positive is harmless.
            guard trimmed.contains("token_count") || trimmed.contains("turn_context") else { continue }
            result.candidateLineCount += 1

            guard let data = trimmed.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.malformedLineCount += 1
                continue
            }

            let type = root["type"] as? String
            guard let payload = root["payload"] as? [String: Any] else { continue }

            if type == "turn_context" {
                if let model = payload["model"] as? String, !model.isEmpty {
                    currentModel = model
                }
                continue
            }

            guard type == "event_msg", payload["type"] as? String == "token_count" else { continue }
            guard let timestamp = LogDate.parse(root["timestamp"] as? String) else { continue }

            // rate_limits and info are independently nullable.
            if let limits = payload["rate_limits"] as? [String: Any],
               let reading = rateLimitReading(from: limits, model: currentModel) {
                apply(reading, into: &result)
                result.latestRateLimitTimestamp = timestamp
            }

            guard let info = payload["info"] as? [String: Any] else { continue }

            if let window = info["model_context_window"] as? Int {
                result.contextWindowTokens = window
            }
            if let last = info["last_token_usage"] as? [String: Any] {
                // input_tokens of the most recent request is the context that was
                // sent — a measured value, not an estimate.
                result.latestContextTokens = last["input_tokens"] as? Int
            }

            guard let cumulative = info["total_token_usage"] as? [String: Any] else { continue }

            let modelKey = Self.modelKey(currentModel)
            let previous = totalsByModel[modelKey] ?? CodexCumulativeTotals()
            let cInput = cumulative["input_tokens"] as? Int ?? 0
            let cCached = cumulative["cached_input_tokens"] as? Int ?? 0
            let cOutput = cumulative["output_tokens"] as? Int ?? 0
            let cReasoning = cumulative["reasoning_output_tokens"] as? Int ?? 0
            let cTotal = cumulative["total_tokens"] as? Int ?? 0

            // A decrease means the counter restarted; the current value is then the
            // whole of the new consumption. Equal values mean a repeated event and
            // yield a zero delta, which we drop.
            let restarted = cTotal < previous.totalTokens
            let dInput = restarted ? cInput : cInput - previous.inputTokens
            let dCached = restarted ? cCached : cCached - previous.cachedInputTokens
            let dOutput = restarted ? cOutput : cOutput - previous.outputTokens
            let dReasoning = restarted ? cReasoning : cReasoning - previous.reasoningTokens
            let dTotal = restarted ? cTotal : cTotal - previous.totalTokens

            let totals = CodexCumulativeTotals(
                inputTokens: cInput,
                cachedInputTokens: cCached,
                outputTokens: cOutput,
                reasoningTokens: cReasoning,
                totalTokens: cTotal,
                eventCount: previous.eventCount + 1
            )
            totalsByModel[modelKey] = totals

            result.latestTimestamp = timestamp
            if let currentModel { result.latestModel = currentModel }

            guard dTotal > 0 else { continue }

            result.events.append(
                UsageEvent(
                    id: "\(sessionID)|\(modelKey)|\(totals.eventCount)",
                    provider: .codex,
                    timestamp: timestamp,
                    model: currentModel,
                    sessionID: sessionID,
                    inputTokens: max(0, dInput),
                    cachedInputTokens: max(0, dCached),
                    cacheCreationTokens: 0,
                    outputTokens: max(0, dOutput),
                    reasoningTokens: max(0, dReasoning),
                    totalTokens: dTotal,
                    source: .localLog
                )
            )
        }

        result.totalsByModel = totalsByModel
        return result
    }

    /// Backwards-compatible entry point for clients that persisted one counter per
    /// session. New callers should pass `previousTotalsByModel`.
    public func parse(
        lines: [String],
        sessionID: String,
        previousTotals: CodexCumulativeTotals,
        previousModel: String? = nil
    ) -> Result {
        let key = previousModel ?? "__unattributed__"
        return parse(
            lines: lines,
            sessionID: sessionID,
            previousTotalsByModel: [key: previousTotals],
            previousModel: previousModel
        )
    }

    private static func modelKey(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "__unattributed__" }
        return model
    }

    /// Reads quota data without producing token events. The provider uses this once
    /// at launch to repair samples written by older builds that did not distinguish
    /// the general `codex` limit from model-specific limit buckets.
    func parseLatestRateLimits(lines: [String]) -> RateLimitResult {
        var result = RateLimitResult()
        var currentModel: String?

        for line in lines {
            guard line.contains("token_count") || line.contains("turn_context"),
                  let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let payload = root["payload"] as? [String: Any] else { continue }

            if root["type"] as? String == "turn_context" {
                if let model = payload["model"] as? String, !model.isEmpty { currentModel = model }
                continue
            }
            guard root["type"] as? String == "event_msg",
                  payload["type"] as? String == "token_count",
                  let timestamp = LogDate.parse(root["timestamp"] as? String),
                  let limits = payload["rate_limits"] as? [String: Any],
                  let reading = rateLimitReading(from: limits, model: currentModel) else { continue }

            // A rollout can contain general Codex and Spark readings in either
            // order. Keep each independently: assigning nil here used to let a
            // later Spark-only record erase the general value recovered above.
            if let short = reading.shortWindow { result.shortWindow = short }
            if let weekly = reading.weeklyWindow { result.weeklyWindow = weekly }
            if let sparkShort = reading.sparkShortWindow { result.sparkShortWindow = sparkShort }
            if let sparkWeekly = reading.sparkWeeklyWindow { result.sparkWeeklyWindow = sparkWeekly }
            if let planType = reading.planType { result.planType = planType }
            result.timestamp = timestamp
        }

        return result
    }

    struct RateLimitResult: Sendable {
        var shortWindow: UsageWindow? = nil
        var weeklyWindow: UsageWindow? = nil
        var sparkShortWindow: UsageWindow? = nil
        var sparkWeeklyWindow: UsageWindow? = nil
        var planType: String? = nil
        var timestamp: Date? = nil

        var hasQuota: Bool {
            shortWindow != nil || weeklyWindow != nil
                || sparkShortWindow != nil || sparkWeeklyWindow != nil
        }
    }

    private struct RateLimitReading {
        var shortWindow: UsageWindow? = nil
        var weeklyWindow: UsageWindow? = nil
        var sparkShortWindow: UsageWindow? = nil
        var sparkWeeklyWindow: UsageWindow? = nil
        var planType: String? = nil

        var hasQuota: Bool {
            shortWindow != nil || weeklyWindow != nil
                || sparkShortWindow != nil || sparkWeeklyWindow != nil
        }
    }

    private func rateLimitReading(from limits: [String: Any], model: String?) -> RateLimitReading? {
        // Codex can emit additional model-specific buckets (for example
        // `codex_bengalfox`) alongside the account's general `codex` limit. Those
        // percentages are not the value shown by Codex's usage UI.
        let limitID = limits["limit_id"] as? String
        let isSpark = model == "gpt-5.3-codex-spark"
        if !isSpark, let limitID, limitID != "codex" {
            return nil
        }

        var reading = RateLimitReading(planType: limits["plan_type"] as? String)

        for slot in ["primary", "secondary"] {
            guard let entry = limits[slot] as? [String: Any] else { continue }
            let minutes = entry["window_minutes"] as? Int
            guard let kind = Self.classify(windowMinutes: minutes) else { continue }

            let percent = (entry["used_percent"] as? Double) ?? (entry["used_percent"] as? Int).map(Double.init)

            // resets_at is a Unix epoch (seconds). Some builds emit a relative
            // resets_in_seconds instead, so honour that when the absolute one is absent.
            var resetsAt: Date?
            if let epoch = entry["resets_at"] as? Double {
                resetsAt = Date(timeIntervalSince1970: epoch)
            } else if let epoch = entry["resets_at"] as? Int {
                resetsAt = Date(timeIntervalSince1970: Double(epoch))
            } else if let seconds = entry["resets_in_seconds"] as? Int {
                resetsAt = Date().addingTimeInterval(Double(seconds))
            }

            guard let window = UsageWindow.fromUsedPercent(percent, resetsAt: resetsAt, windowMinutes: minutes) else {
                continue
            }
            switch (isSpark, kind) {
            case (false, .short): reading.shortWindow = window
            case (false, .weekly): reading.weeklyWindow = window
            case (true, .short): reading.sparkShortWindow = window
            case (true, .weekly): reading.sparkWeeklyWindow = window
            }
        }

        guard reading.hasQuota else { return nil }
        return reading
    }

    private func apply(_ reading: RateLimitReading, into result: inout Result) {
        if let short = reading.shortWindow { result.shortWindow = short }
        if let weekly = reading.weeklyWindow { result.weeklyWindow = weekly }
        if let short = reading.sparkShortWindow { result.sparkShortWindow = short }
        if let weekly = reading.sparkWeeklyWindow { result.sparkWeeklyWindow = weekly }
        if let plan = reading.planType { result.planType = plan }
    }
}
