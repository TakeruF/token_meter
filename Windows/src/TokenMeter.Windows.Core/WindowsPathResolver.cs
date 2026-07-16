namespace TokenMeter.Core;

public sealed class WindowsPathResolver : IPathResolver
{
    private readonly Func<string, string?> _environment;

    public WindowsPathResolver(
        string? userProfile = null,
        string? appDataRoot = null,
        Func<string, string?>? environment = null)
    {
        _environment = environment ?? Environment.GetEnvironmentVariable;
        UserProfile = Path.GetFullPath(
            userProfile
            ?? _environment("USERPROFILE")
            ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

        var localAppData = _environment("LOCALAPPDATA")
            ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        AppDataRoot = Path.GetFullPath(appDataRoot ?? Path.Combine(localAppData, "TokenMeter"));
    }

    public string UserProfile { get; }

    public string ClaudeHome => ResolveConfiguredDirectory("CLAUDE_CONFIG_DIR", ".claude");
    public string ClaudeProjects => Path.Combine(ClaudeHome, "projects");
    public string ClaudeCredentials => Path.Combine(ClaudeHome, ".credentials.json");
    public string CodexHome => ResolveConfiguredDirectory("CODEX_HOME", ".codex");
    public string CodexSessions => Path.Combine(CodexHome, "sessions");
    public string CopilotHome => Path.Combine(UserProfile, ".copilot");
    public string CopilotSessionState => Path.Combine(CopilotHome, "session-state");
    public string AppDataRoot { get; }
    public string DatabasePath => Path.Combine(AppDataRoot, "history.sqlite");

    public IReadOnlyList<string> EnumerateJsonlFiles(string root, int? limit = null)
    {
        if (!Directory.Exists(root))
        {
            return [];
        }

        try
        {
            var files = Directory.EnumerateFiles(root, "*.jsonl", SearchOption.AllDirectories)
                .Select(path => new FileInfo(path))
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .Select(file => file.FullName);
            return limit is null ? files.ToArray() : files.Take(limit.Value).ToArray();
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
        catch (IOException)
        {
            return [];
        }
    }

    public IReadOnlyList<string> EnumerateCopilotEventFiles(int? limit = null)
    {
        if (!Directory.Exists(CopilotSessionState))
        {
            return [];
        }

        try
        {
            var files = Directory.EnumerateDirectories(CopilotSessionState)
                .Select(directory => Path.Combine(directory, "events.jsonl"))
                .Where(File.Exists)
                .Select(path => new FileInfo(path))
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .Select(file => file.FullName);
            return limit is null ? files.ToArray() : files.Take(limit.Value).ToArray();
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
        catch (IOException)
        {
            return [];
        }
    }

    private string ResolveConfiguredDirectory(string variable, string fallbackName)
    {
        var configured = _environment(variable);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(configured));
        }

        return Path.Combine(UserProfile, fallbackName);
    }
}
