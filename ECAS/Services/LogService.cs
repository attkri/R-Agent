using System.Globalization;
using System.IO;
using System.Text;
using ECAS.Models;

namespace ECAS.Services;

public sealed class LogService
{
    private readonly object _gate = new();
    private readonly string _logsDirectory;
    private readonly string _chatDirectory;

    public LogService(string baseDirectory)
    {
        _logsDirectory = Path.Combine(baseDirectory, "logs");
        _chatDirectory = Path.Combine(baseDirectory, "chat");

        Directory.CreateDirectory(_logsDirectory);
        Directory.CreateDirectory(_chatDirectory);

        RunLogPath = Path.Combine(
            _logsDirectory,
            $"{DateTime.Now:yyyyMMdd_HHmmss}_ecas.log");

        KeepLastRunLogs(10);
        WriteSystem("ECAS gestartet.");
    }

    public string RunLogPath { get; }

    public void WriteSystem(string message)
    {
        WriteLine("system", message);
    }

    public void WritePacket(UiLogEntry entry)
    {
        var message =
            $"[{entry.Source}] action={entry.Action}; title={entry.Title}; message={entry.Message}; reference={entry.Reference}";
        WriteLine("packet", message, entry.Timestamp);
    }

    public void WriteStatus(UiStatusEntry entry)
    {
        var message =
            $"status={entry.Status}; title={entry.Title}; details={entry.Details}; reference={entry.Reference}";
        WriteLine("status", message, entry.Timestamp);
    }

    public void WriteChat(UiChatLine line)
    {
        var path = Path.Combine(_chatDirectory, $"{DateTime.Now:yyyyMMdd}_chat.log");
        var ts = line.Timestamp.ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture);
        var text = $"[{ts}] ({line.Role}) {line.Message}{Environment.NewLine}";

        lock (_gate)
        {
            File.AppendAllText(path, text, Encoding.UTF8);
        }
    }

    private void WriteLine(string kind, string message, DateTimeOffset? timestamp = null)
    {
        var ts = (timestamp ?? DateTimeOffset.Now).ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture);
        var line = $"[{ts}] [{kind}] {message}{Environment.NewLine}";

        lock (_gate)
        {
            File.AppendAllText(RunLogPath, line, Encoding.UTF8);
        }
    }

    private void KeepLastRunLogs(int keep)
    {
        var files = new DirectoryInfo(_logsDirectory)
            .GetFiles("*_ecas.log")
            .OrderByDescending(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .Skip(keep)
            .ToList();

        foreach (var file in files)
        {
            try
            {
                file.Delete();
            }
            catch
            {
                // Ignorieren, wenn Datei gerade gesperrt ist.
            }
        }
    }
}
