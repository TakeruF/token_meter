using System.Net;
using System.Text;

namespace TokenMeter.Core.Tests;

public sealed class ClaudeUsageParityTests
{
    [Fact]
    public async Task Credential_decodes_normal_json()
    {
        using var fixture = CredentialFixture("{\"claudeAiOauth\":{\"accessToken\":\"secret\"}}");
        Assert.Equal("secret", (await fixture.Provider.GetCredentialAsync()).AccessToken);
    }

    [Fact]
    public async Task Credential_finds_nested_oauth_section()
    {
        using var fixture = CredentialFixture("{\"container\":{\"items\":[{\"claudeAiOauth\":{\"accessToken\":\"nested\"}}]}}");
        Assert.Equal("nested", (await fixture.Provider.GetCredentialAsync()).AccessToken);
    }

    [Fact]
    public async Task Missing_oauth_section_is_explicit()
    {
        using var fixture = CredentialFixture("{\"other\":{}}");
        var error = await Assert.ThrowsAsync<CredentialException>(() => fixture.Provider.GetCredentialAsync());
        Assert.Equal(CredentialFailure.OauthSectionMissing, error.Failure);
    }

    [Fact]
    public async Task Missing_access_token_is_explicit()
    {
        using var fixture = CredentialFixture("{\"claudeAiOauth\":{}}");
        var error = await Assert.ThrowsAsync<CredentialException>(() => fixture.Provider.GetCredentialAsync());
        Assert.Equal(CredentialFailure.AccessTokenMissing, error.Failure);
    }

    [Fact]
    public async Task Expiry_decodes_epoch_milliseconds()
    {
        using var fixture = CredentialFixture("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"expiresAt\":1789000000000}}");
        Assert.Equal(DateTimeOffset.FromUnixTimeMilliseconds(1_789_000_000_000), (await fixture.Provider.GetCredentialAsync()).ExpiresAt);
    }

    [Fact]
    public async Task Expiry_accepts_numeric_string()
    {
        using var fixture = CredentialFixture("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"expiresAt\":\"1789000000000\"}}");
        Assert.Equal(DateTimeOffset.FromUnixTimeMilliseconds(1_789_000_000_000), (await fixture.Provider.GetCredentialAsync()).ExpiresAt);
    }

    [Fact]
    public async Task Missing_expiry_stays_unknown()
    {
        using var fixture = CredentialFixture("{\"claudeAiOauth\":{\"accessToken\":\"x\"}}");
        Assert.Null((await fixture.Provider.GetCredentialAsync()).ExpiresAt);
    }

    [Fact]
    public async Task Malformed_credentials_are_classified()
    {
        using var fixture = CredentialFixture("{");
        var error = await Assert.ThrowsAsync<CredentialException>(() => fixture.Provider.GetCredentialAsync());
        Assert.Equal(CredentialFailure.Malformed, error.Failure);
    }

    [Fact]
    public async Task Missing_credential_file_is_classified()
    {
        using var directory = new TempDirectory();
        var paths = Paths(directory.Path);
        var error = await Assert.ThrowsAsync<CredentialException>(
            () => new FileClaudeCredentialProvider(paths).GetCredentialAsync());
        Assert.Equal(CredentialFailure.NotFound, error.Failure);
    }

    [Theory]
    [InlineData(-10, 0, 1)]
    [InlineData(120, 1, 0)]
    public void Usage_utilization_is_clamped(double utilization, double used, double remaining)
    {
        var window = new ClaudeUsageWindow(utilization, null).AsUsageWindow(300)!;
        Assert.Equal(used, window.UsedRatio);
        Assert.Equal(remaining, window.RemainingRatio);
    }

    [Fact]
    public void Reset_only_window_is_preserved()
    {
        var reset = DateTimeOffset.UtcNow;
        var window = new ClaudeUsageWindow(null, reset).AsUsageWindow(300)!;
        Assert.Null(window.UsedRatio);
        Assert.Equal(reset, window.ResetsAt);
    }

    [Fact]
    public async Task Client_uses_fixed_endpoint_and_headers()
    {
        var called = false;
        var client = Client(request =>
        {
            called = true;
            Assert.Equal(ClaudeUsageClient.Endpoint, request.RequestUri);
            Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
            Assert.Equal("token", request.Headers.Authorization.Parameter);
            Assert.Contains("oauth-2025-04-20", request.Headers.GetValues("anthropic-beta"));
            return Json("{\"five_hour\":{\"utilization\":10}}");
        });
        await client.FetchAsync("token");
        Assert.True(called);
    }

    [Theory]
    [InlineData(401, ClaudeUsageError.Unauthorized)]
    [InlineData(403, ClaudeUsageError.Forbidden)]
    [InlineData(429, ClaudeUsageError.RateLimited)]
    [InlineData(500, ClaudeUsageError.ServerError)]
    public async Task Http_status_is_classified(int status, ClaudeUsageError expected)
    {
        var client = Client(_ => new HttpResponseMessage((HttpStatusCode)status));
        var error = await Assert.ThrowsAsync<ClaudeUsageClientException>(() => client.FetchAsync("x"));
        Assert.Equal(expected, error.Error);
    }

    [Fact]
    public async Task Invalid_json_is_format_error()
    {
        var error = await Assert.ThrowsAsync<ClaudeUsageClientException>(
            () => Client(_ => Json("{")).FetchAsync("x"));
        Assert.Equal(ClaudeUsageError.InvalidResponse, error.Error);
    }

    [Fact]
    public async Task Empty_success_payload_is_format_error()
    {
        var error = await Assert.ThrowsAsync<ClaudeUsageClientException>(
            () => Client(_ => Json("{}")).FetchAsync("x"));
        Assert.Equal(ClaudeUsageError.InvalidResponse, error.Error);
    }

    [Fact]
    public async Task All_usage_windows_and_dates_decode()
    {
        var body = "{\"five_hour\":{\"utilization\":12.5,\"resets_at\":\"2026-07-15T10:00:00Z\"},\"seven_day\":{\"utilization\":20},\"seven_day_sonnet\":{\"utilization\":30}}";
        var result = await Client(_ => Json(body)).FetchAsync("x");
        Assert.Equal(12.5, result.FiveHour!.Utilization);
        Assert.Equal(DateTimeOffset.Parse("2026-07-15T10:00:00Z"), result.FiveHour.ResetsAt);
        Assert.NotNull(result.SevenDay);
        Assert.NotNull(result.SevenDaySonnet);
    }

    [Fact]
    public async Task Fresh_memory_cache_avoids_second_request()
    {
        var api = new FakeUsageClient();
        var service = Service(api);
        await service.GetUsageAsync();
        var second = await service.GetUsageAsync();
        Assert.Equal(1, api.Calls);
        Assert.True(second.IsCached);
    }

    [Fact]
    public async Task Force_refresh_bypasses_memory_cache()
    {
        var api = new FakeUsageClient();
        var service = Service(api);
        await service.GetUsageAsync();
        await service.GetUsageAsync(true);
        Assert.Equal(2, api.Calls);
    }

    [Fact]
    public async Task Failure_falls_back_to_last_success()
    {
        var api = new FakeUsageClient();
        var service = Service(api);
        await service.GetUsageAsync();
        api.Error = ClaudeUsageError.RateLimited;
        var fallback = await service.GetUsageAsync(true);
        Assert.NotNull(fallback.Usage);
        Assert.True(fallback.IsCached);
        Assert.Equal(ClaudeUsageError.RateLimited, fallback.Error);
    }

    [Fact]
    public async Task Expired_token_fails_without_network()
    {
        var api = new FakeUsageClient();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-07-15T10:00:00Z"));
        var credentials = new FakeCredentialProvider(
            new ClaudeCredential("x", clock.UtcNow.AddSeconds(-1)));
        var result = await new ClaudeUsageService(credentials, api, clock).GetUsageAsync();
        Assert.Equal(ClaudeUsageError.SessionExpired, result.Error);
        Assert.Equal(0, api.Calls);
    }

    [Fact]
    public async Task Missing_credential_does_not_call_network()
    {
        var api = new FakeUsageClient();
        var credentials = new FakeCredentialProvider(
            new CredentialException(CredentialFailure.NotFound, "missing"));
        var result = await new ClaudeUsageService(credentials, api).GetUsageAsync();
        Assert.Equal(ClaudeUsageError.CredentialsNotFound, result.Error);
        Assert.Equal(0, api.Calls);
    }

    private static ClaudeUsageService Service(FakeUsageClient api) => new(
        new FakeCredentialProvider(new ClaudeCredential("x", DateTimeOffset.UtcNow.AddDays(1))),
        api,
        new FixedClock(DateTimeOffset.UtcNow));

    private static CredentialFixtureHolder CredentialFixture(string json)
    {
        var directory = new TempDirectory();
        var paths = Paths(directory.Path);
        Directory.CreateDirectory(paths.ClaudeHome);
        File.WriteAllText(paths.ClaudeCredentials, json);
        return new CredentialFixtureHolder(directory, new FileClaudeCredentialProvider(paths));
    }

    private static WindowsPathResolver Paths(string root) => new(
        System.IO.Path.Combine(root, "user"),
        System.IO.Path.Combine(root, "app"),
        name => name == "CLAUDE_CONFIG_DIR" ? System.IO.Path.Combine(root, "claude") : null);

    private static ClaudeUsageClient Client(Func<HttpRequestMessage, HttpResponseMessage> response) =>
        new(new HttpClient(new StubHandler(response)));

    private static HttpResponseMessage Json(string body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json"),
    };

    private sealed class CredentialFixtureHolder(TempDirectory directory, FileClaudeCredentialProvider provider) : IDisposable
    {
        public FileClaudeCredentialProvider Provider { get; } = provider;
        public void Dispose() => directory.Dispose();
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(response(request));
    }

    private sealed class FakeCredentialProvider : ICredentialProvider
    {
        private readonly ClaudeCredential? _credential;
        private readonly Exception? _error;
        public FakeCredentialProvider(ClaudeCredential credential) => _credential = credential;
        public FakeCredentialProvider(Exception error) => _error = error;
        public Task<ClaudeCredential> GetCredentialAsync(CancellationToken cancellationToken = default) =>
            _error is null ? Task.FromResult(_credential!) : Task.FromException<ClaudeCredential>(_error);
    }

    private sealed class FakeUsageClient : IClaudeUsageClient
    {
        public int Calls { get; private set; }
        public ClaudeUsageError? Error { get; set; }
        public Task<ClaudeUsageResponse> FetchAsync(string accessToken, CancellationToken cancellationToken = default)
        {
            Calls++;
            return Error is null
                ? Task.FromResult(new ClaudeUsageResponse(new ClaudeUsageWindow(10, null), null, null))
                : Task.FromException<ClaudeUsageResponse>(new ClaudeUsageClientException(Error.Value, "error"));
        }
    }
}
