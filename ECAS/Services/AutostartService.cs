using ECAS.Models;
using Microsoft.Win32;

namespace ECAS.Services;

public sealed class AutostartService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly string _valueName;

    public AutostartService(string valueName)
    {
        _valueName = valueName;
    }

    public void Apply(AutostartConfig config, string executablePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        if (!string.Equals(config.Mode, "hkcu_run", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (key is null)
        {
            return;
        }

        if (!config.Enabled)
        {
            key.DeleteValue(_valueName, throwOnMissingValue: false);
            return;
        }

        key.SetValue(_valueName, Quote(executablePath));
    }

    private static string Quote(string value)
    {
        return value.StartsWith('"') ? value : $"\"{value}\"";
    }
}
