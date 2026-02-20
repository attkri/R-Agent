using System.Diagnostics;
using ECAS.Models;
using ECAS.Services;

namespace ECAS;

public partial class App : System.Windows.Application
{
    private CancellationTokenSource? _appCancellation;
    private TrayService? _trayService;
    private OrchestratorService? _orchestrator;
    private MainWindow? _mainWindow;
    private bool _isShuttingDown;

    public AppConfig? Config { get; private set; }

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);

        var baseDirectory = AppContext.BaseDirectory;
        var configService = new ConfigService(baseDirectory);
        var config = configService.LoadOrCreate();

        Config = config;

        var logService = new LogService(baseDirectory);
        var runner = new OpenCodeRunner(config.OpenCodeCommand, config.OpenCodeWorkingDirectory);
        var parser = new AgentPacketParser();
        var orchestrator = new OrchestratorService(config, logService, runner, parser);

        _appCancellation = new CancellationTokenSource();
        _orchestrator = orchestrator;

        var tray = new TrayService();
        tray.OpenRequested += HandleTrayOpenRequested;
        tray.ExitRequested += HandleTrayExitRequested;
        _trayService = tray;

        orchestrator.StatusSignalChanged += (signal, title) =>
            Dispatcher.Invoke(() => _trayService?.UpdateStatus(signal, title));
        orchestrator.NotificationRequested += (title, message, signal) =>
            Dispatcher.Invoke(() => _trayService?.ShowNotification(title, message, signal));

        var window = new MainWindow(orchestrator, logService);
        _mainWindow = window;
        MainWindow = window;
        window.Show();

        orchestrator.Start(_appCancellation.Token);

        ApplyAutostart(config, logService);
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        ShutdownRuntime();
        base.OnExit(e);
    }

    private void HandleTrayOpenRequested()
    {
        Dispatcher.Invoke(() =>
        {
            if (_mainWindow is null)
            {
                return;
            }

            if (!_mainWindow.IsVisible)
            {
                _mainWindow.Show();
            }

            if (_mainWindow.WindowState == System.Windows.WindowState.Minimized)
            {
                _mainWindow.WindowState = System.Windows.WindowState.Normal;
            }

            _mainWindow.Activate();
        });
    }

    private void HandleTrayExitRequested()
    {
        Dispatcher.Invoke(() =>
        {
            if (_isShuttingDown)
            {
                return;
            }

            _isShuttingDown = true;
            _mainWindow?.EnableShutdown();
            Shutdown();
        });
    }

    private void ApplyAutostart(AppConfig config, LogService logService)
    {
        try
        {
            var executablePath = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(executablePath))
            {
                executablePath = Process.GetCurrentProcess().MainModule?.FileName;
            }

            if (string.IsNullOrWhiteSpace(executablePath))
            {
                logService.WriteSystem("Autostart konnte nicht gesetzt werden: Prozesspfad nicht verfügbar.");
                return;
            }

            var autostartService = new AutostartService("ECAS");
            autostartService.Apply(config.Autostart, executablePath);
        }
        catch (Exception ex)
        {
            logService.WriteSystem($"Autostart-Fehler: {ex.Message}");
        }
    }

    private void ShutdownRuntime()
    {
        _appCancellation?.Cancel();

        try
        {
            _orchestrator?.StopAsync().GetAwaiter().GetResult();
        }
        catch
        {
            // Shutdown darf nicht scheitern.
        }

        _trayService?.Dispose();
        _appCancellation?.Dispose();
    }
}

