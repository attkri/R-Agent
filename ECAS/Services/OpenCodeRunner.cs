using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace ECAS.Services;

public sealed class OpenCodeRunner
{
    private readonly string _command;
    private readonly string _workingDirectory;

    public OpenCodeRunner(string command, string workingDirectory)
    {
        _command = string.IsNullOrWhiteSpace(command) ? "opencode" : command;
        _workingDirectory = string.IsNullOrWhiteSpace(workingDirectory)
            ? Environment.CurrentDirectory
            : workingDirectory;
    }

    public async Task<OpenCodeRunResult> RunAsync(string prompt, int timeoutSeconds, CancellationToken cancellationToken)
    {
        var startedAt = DateTimeOffset.Now;
        var startInfo = new ProcessStartInfo
        {
            FileName = _command,
            WorkingDirectory = _workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        startInfo.ArgumentList.Add("run");
        startInfo.ArgumentList.Add("--format");
        startInfo.ArgumentList.Add("json");
        startInfo.ArgumentList.Add(prompt);

        using var process = new Process { StartInfo = startInfo };
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(Math.Max(1, timeoutSeconds)));

        try
        {
            process.Start();
        }
        catch (Win32Exception ex)
        {
            return OpenCodeRunResult.Failed(
                exitCode: -100,
                startedAt,
                DateTimeOffset.Now,
                string.Empty,
                $"OpenCode-CLI konnte nicht gestartet werden: {ex.Message}");
        }
        catch (Exception ex)
        {
            return OpenCodeRunResult.Failed(
                exitCode: -101,
                startedAt,
                DateTimeOffset.Now,
                string.Empty,
                $"Unerwarteter Startfehler: {ex.Message}");
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutCts.Token);
        var stderrTask = process.StandardError.ReadToEndAsync(timeoutCts.Token);

        try
        {
            await process.WaitForExitAsync(timeoutCts.Token);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            var endedAt = DateTimeOffset.Now;

            return new OpenCodeRunResult(
                process.ExitCode,
                stdout,
                stderr,
                startedAt,
                endedAt,
                TimedOut: false);
        }
        catch (OperationCanceledException)
        {
            TryKill(process);
            var stdout = stdoutTask.IsCompletedSuccessfully ? stdoutTask.Result : string.Empty;
            var stderr = stderrTask.IsCompletedSuccessfully ? stderrTask.Result : string.Empty;
            var endedAt = DateTimeOffset.Now;

            return OpenCodeRunResult.Failed(
                exitCode: -102,
                startedAt,
                endedAt,
                stdout,
                string.IsNullOrWhiteSpace(stderr)
                    ? "OpenCode-Run hat das Timeout überschritten."
                    : stderr,
                timedOut: true);
        }
        catch (Exception ex)
        {
            TryKill(process);
            var stdout = stdoutTask.IsCompletedSuccessfully ? stdoutTask.Result : string.Empty;
            var endedAt = DateTimeOffset.Now;
            return OpenCodeRunResult.Failed(
                exitCode: -103,
                startedAt,
                endedAt,
                stdout,
                $"Fehler während OpenCode-Run: {ex.Message}");
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Ignorieren, wenn Prozess bereits beendet wurde.
        }
    }
}

public sealed record OpenCodeRunResult(
    int ExitCode,
    string StandardOutput,
    string StandardError,
    DateTimeOffset StartedAt,
    DateTimeOffset EndedAt,
    bool TimedOut)
{
    public TimeSpan Duration => EndedAt - StartedAt;

    public bool IsSuccess => ExitCode == 0 && !TimedOut;

    public static OpenCodeRunResult Failed(
        int exitCode,
        DateTimeOffset startedAt,
        DateTimeOffset endedAt,
        string stdout,
        string stderr,
        bool timedOut = false)
    {
        return new OpenCodeRunResult(
            exitCode,
            stdout,
            stderr,
            startedAt,
            endedAt,
            timedOut);
    }
}
