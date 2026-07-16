using Microsoft.Data.Sqlite;

namespace TokenMeter.Core;

public sealed class SqliteUsageStore : IUsageStore
{
    private readonly object _gate = new();
    private readonly SqliteConnection _connection;
    private bool _disposed;

    public SqliteUsageStore(string databasePath)
    {
        SQLitePCL.Batteries_V2.Init();
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var builder = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
            Pooling = true,
        };
        _connection = new SqliteConnection(builder.ConnectionString);
        _connection.Open();
        ExecuteNonQuery("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000; PRAGMA foreign_keys=ON;");
        CreateSchema();
    }

    public int InsertEvents(IEnumerable<UsageEvent> events)
    {
        var items = events.ToArray();
        if (items.Length == 0)
        {
            return 0;
        }

        lock (_gate)
        {
            using var transaction = _connection.BeginTransaction();
            using var command = _connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                INSERT OR IGNORE INTO usage_event
                (id, provider, timestamp, model, session_id, input_tokens,
                 cached_input_tokens, cache_creation_tokens, output_tokens,
                 reasoning_tokens, total_tokens, source)
                VALUES ($id,$provider,$timestamp,$model,$session,$input,$cached,
                        $cacheCreation,$output,$reasoning,$total,$source);
                """;
            var id = command.Parameters.Add("$id", SqliteType.Text);
            var provider = command.Parameters.Add("$provider", SqliteType.Text);
            var timestamp = command.Parameters.Add("$timestamp", SqliteType.Real);
            var model = command.Parameters.Add("$model", SqliteType.Text);
            var session = command.Parameters.Add("$session", SqliteType.Text);
            var input = command.Parameters.Add("$input", SqliteType.Integer);
            var cached = command.Parameters.Add("$cached", SqliteType.Integer);
            var cacheCreation = command.Parameters.Add("$cacheCreation", SqliteType.Integer);
            var output = command.Parameters.Add("$output", SqliteType.Integer);
            var reasoning = command.Parameters.Add("$reasoning", SqliteType.Integer);
            var total = command.Parameters.Add("$total", SqliteType.Integer);
            var source = command.Parameters.Add("$source", SqliteType.Text);

            var inserted = 0;
            foreach (var item in items)
            {
                id.Value = item.Id;
                provider.Value = item.Provider.StorageValue();
                timestamp.Value = item.Timestamp.ToUnixTimeMilliseconds() / 1000d;
                model.Value = (object?)item.Model ?? DBNull.Value;
                session.Value = (object?)item.SessionId ?? DBNull.Value;
                input.Value = item.InputTokens;
                cached.Value = item.CachedInputTokens;
                cacheCreation.Value = item.CacheCreationTokens;
                output.Value = item.OutputTokens;
                reasoning.Value = (object?)item.ReasoningTokens ?? DBNull.Value;
                total.Value = item.TotalTokens;
                source.Value = item.Source.StorageValue();
                inserted += command.ExecuteNonQuery();
            }

            transaction.Commit();
            return inserted;
        }
    }

    public IReadOnlyList<UsageEvent> GetEvents(
        UsageProviderId? provider,
        DateTimeOffset since,
        DateTimeOffset? until = null)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                SELECT id, provider, timestamp, model, session_id, input_tokens,
                       cached_input_tokens, cache_creation_tokens, output_tokens,
                       reasoning_tokens, total_tokens, source
                FROM usage_event
                WHERE timestamp >= $since AND timestamp < $until
                """ + (provider is null ? string.Empty : " AND provider = $provider") +
                " ORDER BY timestamp ASC;";
            command.Parameters.AddWithValue("$since", since.ToUnixTimeMilliseconds() / 1000d);
            command.Parameters.AddWithValue(
                "$until",
                until is null ? double.MaxValue : until.Value.ToUnixTimeMilliseconds() / 1000d);
            if (provider is not null)
            {
                command.Parameters.AddWithValue("$provider", provider.Value.StorageValue());
            }

            using var reader = command.ExecuteReader();
            var result = new List<UsageEvent>();
            while (reader.Read())
            {
                if (!UsageProviderIdExtensions.TryParseStorageValue(reader.GetString(1), out var parsedProvider) ||
                    !UsageSourceExtensions.TryParseStorageValue(reader.GetString(11), out var source))
                {
                    continue;
                }

                result.Add(new UsageEvent(
                    reader.GetString(0),
                    parsedProvider,
                    FromUnixSeconds(reader.GetDouble(2)),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetInt64(5),
                    reader.GetInt64(6),
                    reader.GetInt64(7),
                    reader.GetInt64(8),
                    reader.IsDBNull(9) ? null : reader.GetInt64(9),
                    reader.GetInt64(10),
                    source));
            }
            return result;
        }
    }

    public long GetCursor(string path)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = "SELECT offset FROM file_cursor WHERE path = $path;";
            command.Parameters.AddWithValue("$path", path);
            return command.ExecuteScalar() is long offset ? Math.Max(0, offset) : 0;
        }
    }

    public string? GetCursorFingerprint(string path)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = "SELECT prefix_fingerprint FROM file_cursor WHERE path = $path;";
            command.Parameters.AddWithValue("$path", path);
            return command.ExecuteScalar() as string;
        }
    }

    public void SetCursor(string path, long offset, string? fingerprint = null)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                INSERT INTO file_cursor(path, offset, prefix_fingerprint)
                VALUES($path, $offset, $fingerprint)
                ON CONFLICT(path) DO UPDATE SET
                    offset = excluded.offset,
                    prefix_fingerprint = excluded.prefix_fingerprint;
                """;
            command.Parameters.AddWithValue("$path", path);
            command.Parameters.AddWithValue("$offset", Math.Max(0, offset));
            command.Parameters.AddWithValue("$fingerprint", (object?)fingerprint ?? DBNull.Value);
            command.ExecuteNonQuery();
        }
    }

    public CumulativeTotals? GetSessionTotals(string sessionId)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                SELECT input_tokens, cached_input_tokens, output_tokens,
                       reasoning_tokens, total_tokens, event_count
                FROM session_totals WHERE session_id = $session;
                """;
            command.Parameters.AddWithValue("$session", sessionId);
            using var reader = command.ExecuteReader();
            return !reader.Read()
                ? null
                : new CumulativeTotals(
                    reader.GetInt64(0), reader.GetInt64(1), reader.GetInt64(2),
                    reader.GetInt64(3), reader.GetInt64(4), reader.GetInt64(5));
        }
    }

    public IReadOnlyList<string> GetSessionModels(UsageProviderId provider, string sessionPrefix)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                SELECT session_id FROM session_totals
                WHERE provider = $provider AND session_id LIKE $prefix ESCAPE '\';
                """;
            command.Parameters.AddWithValue("$provider", provider.StorageValue());
            command.Parameters.AddWithValue("$prefix", EscapeLike(sessionPrefix) + "%");
            using var reader = command.ExecuteReader();
            var result = new List<string>();
            while (reader.Read())
            {
                var key = reader.GetString(0);
                if (key.StartsWith(sessionPrefix, StringComparison.Ordinal))
                {
                    result.Add(key[sessionPrefix.Length..]);
                }
            }
            return result;
        }
    }

    public void SetSessionTotals(string sessionId, UsageProviderId provider, CumulativeTotals totals)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                INSERT INTO session_totals
                    (session_id, provider, input_tokens, cached_input_tokens,
                     output_tokens, reasoning_tokens, total_tokens, event_count)
                VALUES($session,$provider,$input,$cached,$output,$reasoning,$total,$count)
                ON CONFLICT(session_id) DO UPDATE SET
                    provider=excluded.provider,
                    input_tokens=excluded.input_tokens,
                    cached_input_tokens=excluded.cached_input_tokens,
                    output_tokens=excluded.output_tokens,
                    reasoning_tokens=excluded.reasoning_tokens,
                    total_tokens=excluded.total_tokens,
                    event_count=excluded.event_count;
                """;
            command.Parameters.AddWithValue("$session", sessionId);
            command.Parameters.AddWithValue("$provider", provider.StorageValue());
            command.Parameters.AddWithValue("$input", totals.InputTokens);
            command.Parameters.AddWithValue("$cached", totals.CachedInputTokens);
            command.Parameters.AddWithValue("$output", totals.OutputTokens);
            command.Parameters.AddWithValue("$reasoning", totals.ReasoningTokens);
            command.Parameters.AddWithValue("$total", totals.TotalTokens);
            command.Parameters.AddWithValue("$count", totals.EventCount);
            command.ExecuteNonQuery();
        }
    }

    public void InsertLimitSample(
        UsageProviderId provider,
        DateTimeOffset timestamp,
        string kind,
        UsageWindow window,
        UsageSource source)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                INSERT OR REPLACE INTO limit_sample
                    (provider, timestamp, window_kind, used_ratio, remaining_ratio,
                     resets_at, window_minutes, source)
                VALUES($provider,$timestamp,$kind,$used,$remaining,$resets,$minutes,$source);
                """;
            command.Parameters.AddWithValue("$provider", provider.StorageValue());
            command.Parameters.AddWithValue("$timestamp", timestamp.ToUnixTimeMilliseconds() / 1000d);
            command.Parameters.AddWithValue("$kind", kind);
            command.Parameters.AddWithValue("$used", (object?)window.UsedRatio ?? DBNull.Value);
            command.Parameters.AddWithValue("$remaining", (object?)window.RemainingRatio ?? DBNull.Value);
            command.Parameters.AddWithValue(
                "$resets",
                window.ResetsAt is null
                    ? DBNull.Value
                    : window.ResetsAt.Value.ToUnixTimeMilliseconds() / 1000d);
            command.Parameters.AddWithValue("$minutes", (object?)window.WindowMinutes ?? DBNull.Value);
            command.Parameters.AddWithValue("$source", source.StorageValue());
            command.ExecuteNonQuery();
        }
    }

    public LimitSample? GetLatestLimitSample(UsageProviderId provider, string kind)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = """
                SELECT timestamp, used_ratio, remaining_ratio, resets_at,
                       window_minutes, source
                FROM limit_sample
                WHERE provider = $provider AND window_kind = $kind
                ORDER BY timestamp DESC LIMIT 1;
                """;
            command.Parameters.AddWithValue("$provider", provider.StorageValue());
            command.Parameters.AddWithValue("$kind", kind);
            using var reader = command.ExecuteReader();
            if (!reader.Read() ||
                !UsageSourceExtensions.TryParseStorageValue(reader.GetString(5), out var source))
            {
                return null;
            }

            return new LimitSample(
                new UsageWindow(
                    reader.IsDBNull(1) ? null : reader.GetDouble(1),
                    reader.IsDBNull(2) ? null : reader.GetDouble(2),
                    reader.IsDBNull(3) ? null : FromUnixSeconds(reader.GetDouble(3)),
                    reader.IsDBNull(4) ? null : reader.GetInt32(4)),
                FromUnixSeconds(reader.GetDouble(0)),
                source);
        }
    }

    public string? GetLatestModel(UsageProviderId provider) => GetLatestModel(
        "provider = $value",
        provider.StorageValue());

    public string? GetLatestModel(string sessionId) => GetLatestModel(
        "session_id = $value",
        sessionId);

    public int PruneEvents(int days)
    {
        if (days <= 0)
        {
            return 0;
        }

        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = "DELETE FROM usage_event WHERE timestamp < $cutoff;";
            command.Parameters.AddWithValue(
                "$cutoff",
                DateTimeOffset.UtcNow.AddDays(-days).ToUnixTimeMilliseconds() / 1000d);
            return command.ExecuteNonQuery();
        }
    }

    public void DeleteAllData()
    {
        lock (_gate)
        {
            ExecuteNonQuery(
                "DELETE FROM usage_event; DELETE FROM file_cursor; " +
                "DELETE FROM session_totals; DELETE FROM limit_sample; VACUUM;");
        }
    }

    public int EventCount()
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM usage_event;";
            return Convert.ToInt32(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _connection.Dispose();
    }

    private string? GetLatestModel(string predicate, string value)
    {
        lock (_gate)
        {
            using var command = _connection.CreateCommand();
            command.CommandText = $"""
                SELECT model FROM usage_event
                WHERE {predicate} AND model IS NOT NULL
                ORDER BY timestamp DESC LIMIT 1;
                """;
            command.Parameters.AddWithValue("$value", value);
            return command.ExecuteScalar() as string;
        }
    }

    private void CreateSchema()
    {
        ExecuteNonQuery("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER NOT NULL
            );
            INSERT INTO schema_version(version)
                SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version);

            CREATE TABLE IF NOT EXISTS usage_event (
                id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                timestamp REAL NOT NULL,
                model TEXT,
                session_id TEXT,
                input_tokens INTEGER NOT NULL,
                cached_input_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                reasoning_tokens INTEGER,
                total_tokens INTEGER NOT NULL,
                source TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_event_time ON usage_event(timestamp);
            CREATE INDEX IF NOT EXISTS idx_event_provider_time ON usage_event(provider, timestamp);

            CREATE TABLE IF NOT EXISTS file_cursor (
                path TEXT PRIMARY KEY,
                offset INTEGER NOT NULL,
                prefix_fingerprint TEXT
            );

            CREATE TABLE IF NOT EXISTS session_totals (
                session_id TEXT PRIMARY KEY,
                provider TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                cached_input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                reasoning_tokens INTEGER NOT NULL,
                total_tokens INTEGER NOT NULL,
                event_count INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS limit_sample (
                provider TEXT NOT NULL,
                timestamp REAL NOT NULL,
                window_kind TEXT NOT NULL,
                used_ratio REAL,
                remaining_ratio REAL,
                resets_at REAL,
                window_minutes INTEGER,
                source TEXT NOT NULL,
                PRIMARY KEY(provider, window_kind, timestamp)
            );
            """);
        if (!ColumnExists("file_cursor", "prefix_fingerprint"))
        {
            ExecuteNonQuery("ALTER TABLE file_cursor ADD COLUMN prefix_fingerprint TEXT;");
        }
        ExecuteNonQuery("UPDATE schema_version SET version = 2 WHERE version < 2;");
    }

    private bool ColumnExists(string table, string column)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info({table});";
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            if (string.Equals(reader.GetString(1), column, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private void ExecuteNonQuery(string sql)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static DateTimeOffset FromUnixSeconds(double value) =>
        DateTimeOffset.FromUnixTimeMilliseconds(checked((long)Math.Round(value * 1000d)));

    private static string EscapeLike(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("%", "\\%", StringComparison.Ordinal)
            .Replace("_", "\\_", StringComparison.Ordinal);
}
