using System.IO;
using System.Text.Json;
using ECAS.Models;

namespace ECAS.Services;

public sealed class ConfigService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    private readonly string _configPath;

    public ConfigService(string baseDirectory)
    {
        _configPath = Path.Combine(baseDirectory, "app.config.json");
    }

    public string ConfigPath => _configPath;

    public AppConfig LoadOrCreate()
    {
        if (!File.Exists(_configPath))
        {
            var created = AppConfig.CreateDefault();
            Save(created);
            return created;
        }

        try
        {
            var json = File.ReadAllText(_configPath);
            var config = JsonSerializer.Deserialize<AppConfig>(json, JsonOptions);
            if (config is null)
            {
                throw new InvalidDataException("Konfiguration ist leer.");
            }

            return config;
        }
        catch
        {
            BackupInvalidConfig();
            var fallback = AppConfig.CreateDefault();
            Save(fallback);
            return fallback;
        }
    }

    public void Save(AppConfig config)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_configPath) ?? AppContext.BaseDirectory);
        var json = JsonSerializer.Serialize(config, JsonOptions);
        File.WriteAllText(_configPath, json);
    }

    private void BackupInvalidConfig()
    {
        if (!File.Exists(_configPath))
        {
            return;
        }

        var backupPath = _configPath + ".invalid_" + DateTime.Now.ToString("yyyyMMdd_HHmmss");
        File.Copy(_configPath, backupPath, overwrite: true);
    }
}
