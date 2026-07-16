using System.Diagnostics;
using Windows.Management.Deployment;

namespace TokenMeter.Windows.Setup;

internal sealed class InstallerForm : Form
{
    private readonly SetupStrings _strings = SetupStrings.Current;
    private readonly Label _headingLabel = new();
    private readonly Label _statusLabel = new();
    private readonly Label _changesLabel = new();
    private readonly LinkLabel _privacyLink = new();
    private readonly LinkLabel _uninstallLink = new();
    private readonly ProgressBar _progressBar = new();
    private readonly Button _primaryButton = new();
    private readonly Button _secondaryButton = new();
    private readonly CancellationTokenSource _cancellation = new();

    private PackagePayload? _payload;
    private global::Windows.Foundation.IAsyncOperationWithProgress<DeploymentResult, DeploymentProgress>? _operation;
    private bool _installing;
    private bool _installed;

    public InstallerForm()
    {
        Text = _strings.WindowTitle;
        ClientSize = new Size(600, 440);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = true;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);

        BuildLayout();
        Shown += OnShown;
        FormClosing += OnFormClosing;
    }

    private void BuildLayout()
    {
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(28, 24, 28, 20),
            ColumnCount = 1,
            RowCount = 6,
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        _headingLabel.AutoSize = true;
        _headingLabel.Font = new Font(Font.FontFamily, 18F, FontStyle.Bold, GraphicsUnit.Point);
        _headingLabel.Margin = new Padding(0, 0, 0, 14);

        _statusLabel.AutoSize = true;
        _statusLabel.Dock = DockStyle.Fill;
        _statusLabel.MaximumSize = new Size(540, 0);
        _statusLabel.Margin = new Padding(0, 0, 0, 14);

        _changesLabel.AutoSize = true;
        _changesLabel.Dock = DockStyle.Fill;
        _changesLabel.MaximumSize = new Size(540, 0);
        _changesLabel.Text = _strings.SystemChangesAndPrivacy;
        _changesLabel.AccessibleName = _strings.SystemChangesAndPrivacy;
        _changesLabel.Margin = new Padding(0, 0, 0, 12);

        var policyLinks = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            Margin = new Padding(0, 0, 0, 16),
        };
        ConfigureLink(
            _privacyLink,
            _strings.PrivacyPolicy,
            "https://github.com/TakeruF/token_meter/blob/main/docs/privacy.md");
        ConfigureLink(
            _uninstallLink,
            _strings.UninstallInstructions,
            "https://github.com/TakeruF/token_meter/blob/main/docs/windows-uninstall.md");
        policyLinks.Controls.Add(_privacyLink);
        policyLinks.Controls.Add(_uninstallLink);

        _progressBar.Dock = DockStyle.Fill;
        _progressBar.Minimum = 0;
        _progressBar.Maximum = 100;
        _progressBar.Style = ProgressBarStyle.Continuous;
        _progressBar.Margin = new Padding(0, 0, 0, 20);
        _progressBar.AccessibleName = _strings.Installing;

        var buttons = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            Margin = Padding.Empty,
        };

        _primaryButton.AutoSize = true;
        _primaryButton.MinimumSize = new Size(132, 36);
        _primaryButton.Text = _strings.Install;
        _primaryButton.AccessibleName = _strings.Install;
        _primaryButton.Click += OnPrimaryButtonClick;

        _secondaryButton.AutoSize = true;
        _secondaryButton.MinimumSize = new Size(100, 36);
        _secondaryButton.Text = _strings.Cancel;
        _secondaryButton.AccessibleName = _strings.Cancel;
        _secondaryButton.DialogResult = DialogResult.Cancel;
        _secondaryButton.Click += (_, _) => Close();

        buttons.Controls.Add(_primaryButton);
        buttons.Controls.Add(_secondaryButton);
        layout.Controls.Add(_headingLabel, 0, 0);
        layout.Controls.Add(_statusLabel, 0, 1);
        layout.Controls.Add(_changesLabel, 0, 2);
        layout.Controls.Add(policyLinks, 0, 3);
        layout.Controls.Add(_progressBar, 0, 4);
        layout.Controls.Add(buttons, 0, 5);
        Controls.Add(layout);

        AcceptButton = _primaryButton;
        CancelButton = _secondaryButton;
    }

    private static void ConfigureLink(LinkLabel link, string text, string destination)
    {
        link.AutoSize = true;
        link.Text = text;
        link.AccessibleName = text;
        link.Margin = new Padding(0, 0, 24, 0);
        link.TabStop = true;
        link.LinkClicked += (_, _) =>
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = destination,
                UseShellExecute = true,
            });
        };
    }

    private void OnShown(object? sender, EventArgs e)
    {
        try
        {
            _payload = PackagePayload.Open();
            _headingLabel.Text = string.Format(
                System.Globalization.CultureInfo.CurrentCulture,
                _strings.Heading,
                _payload.Metadata.Version.ToString(3));
            _statusLabel.Text = _strings.Ready;
            _progressBar.Value = 0;

            var installedPackage = FindInstalledPackage();
            if (installedPackage is not null)
            {
                var installedVersion = ToVersion(installedPackage.Id.Version);
                if (installedVersion >= _payload.Metadata.Version)
                {
                    SetInstalledState(installedVersion == _payload.Metadata.Version
                        ? _strings.AlreadyInstalled
                        : _strings.NewerVersionInstalled);
                }
            }
        }
        catch (Exception exception)
        {
            _headingLabel.Text = _strings.WindowTitle;
            SetFailure(_strings.PayloadError, exception);
        }
    }

    private async void OnPrimaryButtonClick(object? sender, EventArgs e)
    {
        if (_installed)
        {
            LaunchInstalledApp();
            Close();
            return;
        }

        if (_payload is null || _installing)
        {
            return;
        }

        _installing = true;
        _primaryButton.Enabled = false;
        _secondaryButton.Enabled = false;
        _statusLabel.Text = _strings.Installing;
        _progressBar.Style = ProgressBarStyle.Continuous;
        _progressBar.Value = 0;

        var temporaryDirectory = Path.Combine(
            Path.GetTempPath(),
            $"TokenMeterSetup-{Guid.NewGuid():N}");

        try
        {
            var packagePath = await _payload.ExtractAsync(temporaryDirectory, _cancellation.Token);
            var options = new AddPackageOptions
            {
                ForceAppShutdown = true,
                ForceUpdateFromAnyVersion = false,
                RetainFilesOnFailure = false,
            };
            var packageManager = new PackageManager();
            _operation = packageManager.AddPackageByUriAsync(new Uri(packagePath), options);
            _operation.Progress = (_, progress) => UpdateProgress(progress.percentage);
            var result = await _operation;

            if (result.ExtendedErrorCode is not null)
            {
                throw new InvalidOperationException(result.ErrorText, result.ExtendedErrorCode);
            }

            SetInstalledState(_strings.Installed);
        }
        catch (OperationCanceledException)
        {
            Close();
        }
        catch (Exception exception)
        {
            SetFailure(_strings.InstallError, exception, includeSignatureHint: true);
        }
        finally
        {
            _operation = null;
            _installing = false;
            TryDeleteDirectory(temporaryDirectory);
        }
    }

    private void UpdateProgress(uint percentage)
    {
        if (IsDisposed || !IsHandleCreated)
        {
            return;
        }

        BeginInvoke(new Action(() =>
        {
            if (!IsDisposed)
            {
                _progressBar.Value = Math.Clamp((int)percentage, 0, 100);
            }
        }));
    }

    private void LaunchInstalledApp()
    {
        if (_payload is null)
        {
            return;
        }

        try
        {
            var package = FindInstalledPackage();
            if (package is null)
            {
                return;
            }

            var application = $"shell:AppsFolder\\{package.Id.FamilyName}!{_payload.Metadata.ApplicationId}";
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = application,
                UseShellExecute = true,
            });
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, exception.Message, _strings.WindowTitle, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private global::Windows.ApplicationModel.Package? FindInstalledPackage()
    {
        if (_payload is null)
        {
            return null;
        }

        var manager = new PackageManager();
        return manager
            .FindPackagesForUser(string.Empty, _payload.Metadata.IdentityName)
            .Where(item => string.Equals(
                item.Id.Publisher,
                _payload.Metadata.Publisher,
                StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(item => item.Id.Version.Major)
            .ThenByDescending(item => item.Id.Version.Minor)
            .ThenByDescending(item => item.Id.Version.Build)
            .ThenByDescending(item => item.Id.Version.Revision)
            .FirstOrDefault();
    }

    private void SetInstalledState(string status)
    {
        _installed = true;
        _statusLabel.Text = status;
        _progressBar.Value = 100;
        _primaryButton.Text = _strings.Launch;
        _primaryButton.AccessibleName = _strings.Launch;
        _primaryButton.Enabled = true;
        _secondaryButton.Text = _strings.Close;
        _secondaryButton.AccessibleName = _strings.Close;
        _secondaryButton.Enabled = true;
    }

    private static Version ToVersion(global::Windows.ApplicationModel.PackageVersion version)
    {
        return new Version(version.Major, version.Minor, version.Build, version.Revision);
    }

    private void SetFailure(string message, Exception exception, bool includeSignatureHint = false)
    {
        var hresult = $"0x{exception.HResult:X8}";
        var hint = includeSignatureHint ? $"\n\n{_strings.SignatureHint}" : string.Empty;
        _statusLabel.Text = $"{message}\n\n{exception.Message} ({hresult}){hint}";
        _progressBar.Value = 0;
        _primaryButton.Enabled = false;
        _secondaryButton.Text = _strings.Close;
        _secondaryButton.AccessibleName = _strings.Close;
        _secondaryButton.Enabled = true;
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (!_installing)
        {
            return;
        }

        _cancellation.Cancel();
        _operation?.Cancel();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _operation?.Cancel();
            _cancellation.Dispose();
        }

        base.Dispose(disposing);
    }

    private static void TryDeleteDirectory(string directory)
    {
        try
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
        catch (IOException)
        {
            // A failed installation must not be hidden by best-effort temporary-file cleanup.
        }
        catch (UnauthorizedAccessException)
        {
            // Windows can briefly retain a handle after package deployment completes.
        }
    }
}
