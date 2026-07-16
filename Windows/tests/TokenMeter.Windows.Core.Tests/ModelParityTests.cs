namespace TokenMeter.Core.Tests;

public sealed class ModelParityTests
{
    [Fact]
    public void Primary_window_chooses_tightest_remaining_quota()
    {
        var snapshot = UsageSnapshot.Create(
            UsageProviderId.ClaudeCode,
            DateTimeOffset.UtcNow,
            UsageSource.OfficialApi,
            shortWindow: new UsageWindow(.2, .8, null, 300),
            weeklyWindow: new UsageWindow(.7, .3, null, 10080));
        Assert.Equal(.3, snapshot.PrimaryWindow!.RemainingRatio);
    }
}
