namespace TokenMeter.Windows.Setup;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && string.Equals(args[0], "--verify-payload", StringComparison.Ordinal))
        {
            try
            {
                _ = PackagePayload.Open();
                return 0;
            }
            catch (Exception)
            {
                return 1;
            }
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new InstallerForm());
        return 0;
    }
}
