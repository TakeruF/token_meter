using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text.Json;

namespace TokenMeter.Core;

public sealed record ClaudeCredential(string AccessToken, DateTimeOffset? ExpiresAt)
{
    public bool IsExpired(DateTimeOffset now, TimeSpan? skew = null) =>
        ExpiresAt is not null && ExpiresAt.Value - (skew ?? TimeSpan.FromSeconds(30)) <= now;
}

public enum CredentialFailure
{
    NotFound,
    AccessDenied,
    Malformed,
    OauthSectionMissing,
    AccessTokenMissing,
}

public sealed class CredentialException : Exception
{
    public CredentialException(CredentialFailure failure, string message) : base(message)
    {
        Failure = failure;
    }

    public CredentialException(CredentialFailure failure, string message, Exception innerException)
        : base(message, innerException)
    {
        Failure = failure;
    }

    public CredentialFailure Failure { get; }
}

public sealed class FileClaudeCredentialProvider : ICredentialProvider
{
    private readonly IPathResolver _paths;

    public FileClaudeCredentialProvider(IPathResolver paths)
    {
        _paths = paths;
    }

    public async Task<ClaudeCredential> GetCredentialAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await using var stream = new FileStream(
                _paths.ClaudeCredentials,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                bufferSize: 4096,
                useAsync: true);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken)
                .ConfigureAwait(false);
            var oauth = FindObject(document.RootElement, "claudeAiOauth");
            if (oauth is null)
            {
                throw new CredentialException(
                    CredentialFailure.OauthSectionMissing,
                    "Claude Code OAuth credentials were not found.");
            }

            var token = oauth.Value.PropertyOrNull("accessToken").StringOrNull();
            if (string.IsNullOrWhiteSpace(token))
            {
                throw new CredentialException(
                    CredentialFailure.AccessTokenMissing,
                    "Claude Code OAuth access token was not found.");
            }

            DateTimeOffset? expiresAt = null;
            var rawExpiry = oauth.Value.PropertyOrNull("expiresAt");
            double? milliseconds = rawExpiry?.ValueKind switch
            {
                JsonValueKind.Number => rawExpiry.Value.DoubleOrNull(),
                JsonValueKind.String when double.TryParse(
                    rawExpiry.Value.GetString(),
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var parsed) => parsed,
                _ => null,
            };
            if (milliseconds is > 0)
            {
                expiresAt = DateTimeOffset.FromUnixTimeMilliseconds(checked((long)milliseconds.Value));
            }

            return new ClaudeCredential(token, expiresAt);
        }
        catch (FileNotFoundException error)
        {
            throw new CredentialException(CredentialFailure.NotFound, "Claude credentials were not found.", error);
        }
        catch (DirectoryNotFoundException error)
        {
            throw new CredentialException(CredentialFailure.NotFound, "Claude credentials were not found.", error);
        }
        catch (UnauthorizedAccessException error)
        {
            throw new CredentialException(CredentialFailure.AccessDenied, "Claude credentials are not readable.", error);
        }
        catch (JsonException error)
        {
            throw new CredentialException(CredentialFailure.Malformed, "Claude credentials contain invalid JSON.", error);
        }
    }

    private static JsonElement? FindObject(JsonElement value, string key)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            if (value.TryGetProperty(key, out var direct) && direct.ValueKind == JsonValueKind.Object)
            {
                return direct;
            }

            foreach (var property in value.EnumerateObject())
            {
                var result = FindObject(property.Value, key);
                if (result is not null)
                {
                    return result;
                }
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                var result = FindObject(item, key);
                if (result is not null)
                {
                    return result;
                }
            }
        }
        return null;
    }
}

public sealed record ClaudeUsageWindow(double? Utilization, DateTimeOffset? ResetsAt)
{
    public UsageWindow? AsUsageWindow(int windowMinutes)
    {
        if (Utilization is null && ResetsAt is null)
        {
            return null;
        }
        if (Utilization is null)
        {
            return new UsageWindow(null, null, ResetsAt, windowMinutes);
        }
        var used = Math.Clamp(Utilization.Value / 100d, 0d, 1d);
        return new UsageWindow(used, 1d - used, ResetsAt, windowMinutes);
    }
}

public sealed record ClaudeUsageResponse(
    ClaudeUsageWindow? FiveHour,
    ClaudeUsageWindow? SevenDay,
    ClaudeUsageWindow? SevenDaySonnet)
{
    public bool HasAnyWindow => FiveHour is not null || SevenDay is not null || SevenDaySonnet is not null;
}

public sealed class ClaudeUsageClientException : Exception
{
    public ClaudeUsageClientException(ClaudeUsageError error, string message, string? retryAfter = null)
        : base(message)
    {
        Error = error;
        RetryAfter = retryAfter;
    }

    public ClaudeUsageClientException(ClaudeUsageError error, string message, Exception innerException)
        : base(message, innerException)
    {
        Error = error;
    }

    public ClaudeUsageError Error { get; }
    public string? RetryAfter { get; }
}

public sealed class ClaudeUsageClient : IClaudeUsageClient
{
    public static readonly Uri Endpoint = new("https://api.anthropic.com/api/oauth/usage");
    private readonly HttpClient _client;

    public ClaudeUsageClient(HttpClient? client = null)
    {
        _client = client ?? new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression = DecompressionMethods.All,
            PooledConnectionLifetime = TimeSpan.FromMinutes(10),
        })
        {
            Timeout = TimeSpan.FromSeconds(15),
        };
    }

    public async Task<ClaudeUsageResponse> FetchAsync(
        string accessToken,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        HttpResponseMessage response;
        try
        {
            response = await _client.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ClaudeUsageClientException(ClaudeUsageError.NetworkUnavailable, "Claude usage request timed out.");
        }
        catch (HttpRequestException error) when (error.InnerException is SocketException)
        {
            throw new ClaudeUsageClientException(ClaudeUsageError.NetworkUnavailable, "Claude usage is unavailable offline.", error);
        }
        catch (HttpRequestException error)
        {
            throw new ClaudeUsageClientException(ClaudeUsageError.RequestFailed, "Claude usage request failed.", error);
        }

        using (response)
        {
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                throw new ClaudeUsageClientException(ClaudeUsageError.Unauthorized, "Claude credentials were rejected.");
            }
            if (response.StatusCode == HttpStatusCode.Forbidden)
            {
                throw new ClaudeUsageClientException(ClaudeUsageError.Forbidden, "Claude usage access is forbidden.");
            }
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                throw new ClaudeUsageClientException(
                    ClaudeUsageError.RateLimited,
                    "Claude usage is rate limited.",
                    response.Headers.RetryAfter?.ToString());
            }
            if ((int)response.StatusCode >= 500)
            {
                throw new ClaudeUsageClientException(ClaudeUsageError.ServerError, "Anthropic usage service failed.");
            }
            if (!response.IsSuccessStatusCode)
            {
                throw new ClaudeUsageClientException(ClaudeUsageError.RequestFailed, "Claude usage request failed.");
            }

            try
            {
                await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
                using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken)
                    .ConfigureAwait(false);
                var root = document.RootElement;
                var result = new ClaudeUsageResponse(
                    ParseWindow(root.PropertyOrNull("five_hour")),
                    ParseWindow(root.PropertyOrNull("seven_day")),
                    ParseWindow(root.PropertyOrNull("seven_day_sonnet")));
                if (!result.HasAnyWindow)
                {
                    throw new ClaudeUsageClientException(
                        ClaudeUsageError.InvalidResponse,
                        "Claude usage response contains no recognized windows.");
                }
                return result;
            }
            catch (JsonException error)
            {
                throw new ClaudeUsageClientException(
                    ClaudeUsageError.InvalidResponse,
                    "Claude usage response contains invalid JSON.",
                    error);
            }
        }
    }

    private static ClaudeUsageWindow? ParseWindow(JsonElement? element)
    {
        if (element is not { ValueKind: JsonValueKind.Object })
        {
            return null;
        }
        var utilization = element.Value.PropertyOrNull("utilization").DoubleOrNull();
        var resetsAt = LogDate.Parse(element.Value.PropertyOrNull("resets_at").StringOrNull());
        return utilization is null && resetsAt is null
            ? null
            : new ClaudeUsageWindow(utilization, resetsAt);
    }
}

public sealed record ClaudeUsageFetchResult(
    ClaudeUsageResponse? Usage,
    DateTimeOffset? FetchedAt,
    bool IsCached,
    ClaudeUsageError? Error);

public sealed class ClaudeUsageService
{
    private readonly ICredentialProvider _credentials;
    private readonly IClaudeUsageClient _client;
    private readonly IClock _clock;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private ClaudeUsageResponse? _lastUsage;
    private DateTimeOffset? _lastFetchedAt;
    private readonly TimeSpan _cacheDuration;

    public ClaudeUsageService(
        ICredentialProvider credentials,
        IClaudeUsageClient? client = null,
        IClock? clock = null,
        TimeSpan? cacheDuration = null)
    {
        _credentials = credentials;
        _client = client ?? new ClaudeUsageClient();
        _clock = clock ?? SystemClock.Instance;
        _cacheDuration = cacheDuration ?? TimeSpan.FromMinutes(5);
    }

    public async Task<ClaudeUsageFetchResult> GetUsageAsync(
        bool forceRefresh = false,
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!forceRefresh && _lastUsage is not null && _lastFetchedAt is not null &&
                _clock.UtcNow - _lastFetchedAt < _cacheDuration)
            {
                return new ClaudeUsageFetchResult(_lastUsage, _lastFetchedAt, true, null);
            }

            try
            {
                var credential = await _credentials.GetCredentialAsync(cancellationToken).ConfigureAwait(false);
                if (credential.IsExpired(_clock.UtcNow))
                {
                    return Failure(ClaudeUsageError.SessionExpired);
                }
                var usage = await _client.FetchAsync(credential.AccessToken, cancellationToken).ConfigureAwait(false);
                _lastUsage = usage;
                _lastFetchedAt = _clock.UtcNow;
                return new ClaudeUsageFetchResult(usage, _lastFetchedAt, false, null);
            }
            catch (CredentialException error)
            {
                return Failure(error.Failure switch
                {
                    CredentialFailure.NotFound => ClaudeUsageError.CredentialsNotFound,
                    CredentialFailure.AccessDenied => ClaudeUsageError.CredentialAccessDenied,
                    _ => ClaudeUsageError.InvalidCredentials,
                });
            }
            catch (ClaudeUsageClientException error)
            {
                return Failure(error.Error);
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    private ClaudeUsageFetchResult Failure(ClaudeUsageError error) =>
        new(_lastUsage, _lastFetchedAt, _lastUsage is not null, error);
}
