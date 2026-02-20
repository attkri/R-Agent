using System.Text.Json;
using ECAS.Models;

namespace ECAS.Services;

public sealed class OrchestratorService
{
    private readonly AppConfig _config;
    private readonly LogService _logService;
    private readonly OpenCodeRunner _runner;
    private readonly AgentPacketParser _parser;

    private readonly object _queueGate = new();
    private readonly SemaphoreSlim _queueSignal = new(0);
    private readonly PriorityQueue<QueuedWorkItem, (int Id, long Sequence)> _queue = new();
    private readonly List<Task> _workerTasks = [];
    private readonly List<Task> _triggerTasks = [];

    private long _sequence;
    private bool _started;
    private CancellationTokenSource? _internalCts;

    public OrchestratorService(
        AppConfig config,
        LogService logService,
        OpenCodeRunner runner,
        AgentPacketParser parser)
    {
        _config = config;
        _logService = logService;
        _runner = runner;
        _parser = parser;
    }

    public event Action<UiLogEntry>? LogEntryReceived;

    public event Action<UiStatusEntry>? StatusEntryReceived;

    public event Action<StatusSignal, string>? StatusSignalChanged;

    public event Action<UiChatLine>? ChatLineReceived;

    public event Action<string, string, StatusSignal>? NotificationRequested;

    public void Start(CancellationToken appToken)
    {
        if (_started)
        {
            return;
        }

        _started = true;
        _internalCts = CancellationTokenSource.CreateLinkedTokenSource(appToken);
        var token = _internalCts.Token;

        var workers = Math.Max(1, _config.MaxParallelRuns);
        for (var i = 0; i < workers; i++)
        {
            _workerTasks.Add(Task.Run(() => WorkerLoopAsync(token), token));
        }

        foreach (var trigger in _config.Triggers.Where(x => x.Enabled).OrderBy(x => x.Id))
        {
            _triggerTasks.Add(Task.Run(() => TriggerLoopAsync(trigger, token), token));
        }

        EmitStatus(
            new UiStatusEntry
            {
                Timestamp = DateTimeOffset.Now,
                Status = "info",
                Title = "Orchestrator läuft",
                Reference = "system/start",
                Details = "ECAS hat Trigger und Worker gestartet."
            },
            StatusSignal.Info,
            notify: false);
    }

    public async Task StopAsync()
    {
        if (!_started)
        {
            return;
        }

        _started = false;

        if (_internalCts is not null)
        {
            _internalCts.Cancel();
        }

        var workers = Math.Max(1, _config.MaxParallelRuns);
        _queueSignal.Release(workers);

        try
        {
            await Task.WhenAll(_triggerTasks.Concat(_workerTasks));
        }
        catch
        {
            // Beim Shutdown keine weitere Eskalation.
        }
        finally
        {
            _triggerTasks.Clear();
            _workerTasks.Clear();

            if (_internalCts is not null)
            {
                _internalCts.Dispose();
                _internalCts = null;
            }
        }
    }

    public Task EnqueueChatAsync(string userMessage, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(userMessage))
        {
            return Task.CompletedTask;
        }

        var trimmed = userMessage.Trim();
        var userLine = new UiChatLine
        {
            Timestamp = DateTimeOffset.Now,
            Role = "user",
            Message = trimmed
        };

        EmitChat(userLine);

        if (cancellationToken.IsCancellationRequested)
        {
            return Task.CompletedTask;
        }

        var payload = JsonSerializer.Serialize(
            new
            {
                source = "chat",
                timestamp = DateTimeOffset.Now,
                userMessage = trimmed
            });

        var prompt = ApplyTemplate(
            _config.Chat.PromptTemplate,
            payload,
            trimmed);

        EnqueueWork(
            new QueuedWorkItem(
                Id: Math.Max(1, _config.Chat.Id),
                Source: "chat",
                Reference: "chat/input",
                Prompt: prompt,
                TimeoutSeconds: Math.Max(1, _config.Chat.TimeoutSeconds)));

        return Task.CompletedTask;
    }

    private async Task TriggerLoopAsync(TriggerConfig trigger, CancellationToken token)
    {
        try
        {
            QueueTrigger(trigger);

            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(Math.Max(1, trigger.IntervalSeconds)));
            while (await timer.WaitForNextTickAsync(token))
            {
                QueueTrigger(trigger);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal beim Beenden.
        }
        catch (Exception ex)
        {
            if (!token.IsCancellationRequested)
            {
                RaiseCritical(
                    source: $"trigger:{trigger.Name}",
                    title: "Trigger-Loop Fehler",
                    message: ex.Message,
                    reference: $"trigger/{trigger.Name}");
            }
        }
    }

    private void QueueTrigger(TriggerConfig trigger)
    {
        var payload = JsonSerializer.Serialize(
            new
            {
                source = trigger.Name,
                triggerId = trigger.Id,
                generatedAt = DateTimeOffset.Now
            });

        var prompt = ApplyTemplate(trigger.PromptTemplate, payload, string.Empty);

        EnqueueWork(
            new QueuedWorkItem(
                Id: Math.Max(1, trigger.Id),
                Source: $"trigger:{trigger.Name}",
                Reference: $"trigger/{trigger.Name}",
                Prompt: prompt,
                TimeoutSeconds: Math.Max(1, trigger.TimeoutSeconds)));
    }

    private void EnqueueWork(QueuedWorkItem item)
    {
        lock (_queueGate)
        {
            var nextSequence = Interlocked.Increment(ref _sequence);
            _queue.Enqueue(item, (item.Id, nextSequence));
        }

        _queueSignal.Release();
    }

    private async Task WorkerLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                await _queueSignal.WaitAsync(token);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (token.IsCancellationRequested)
            {
                break;
            }

            QueuedWorkItem item;
            lock (_queueGate)
            {
                if (_queue.Count == 0)
                {
                    continue;
                }

                item = _queue.Dequeue();
            }

            try
            {
                await ProcessWorkItemAsync(item, token);
            }
            catch (OperationCanceledException)
            {
                // Normal beim Beenden.
            }
            catch (Exception ex)
            {
                if (!token.IsCancellationRequested)
                {
                    RaiseCritical(
                        item.Source,
                        "Worker-Fehler",
                        ex.Message,
                        item.Reference);
                }
            }
        }
    }

    private async Task ProcessWorkItemAsync(QueuedWorkItem item, CancellationToken token)
    {
        var runResult = await _runner.RunAsync(item.Prompt, item.TimeoutSeconds, token);
        if (!runResult.IsSuccess)
        {
            if (token.IsCancellationRequested)
            {
                return;
            }

            var detail = string.IsNullOrWhiteSpace(runResult.StandardError)
                ? $"OpenCode ExitCode={runResult.ExitCode}; Dauer={runResult.Duration.TotalSeconds:F1}s"
                : $"OpenCode ExitCode={runResult.ExitCode}; {Compact(runResult.StandardError)}";

            RaiseCritical(
                item.Source,
                "OpenCode-Run fehlgeschlagen",
                detail,
                item.Reference);
            return;
        }

        if (!_parser.TryParse(runResult.StandardOutput, out var packet, out var parseError) || packet is null)
        {
            if (token.IsCancellationRequested)
            {
                return;
            }

            var detail = $"Parse-Fehler: {parseError}";
            RaiseCritical(
                item.Source,
                "Ungültige Agent-Antwort",
                detail,
                item.Reference);
            return;
        }

        HandlePacket(item.Source, packet);
    }

    private void HandlePacket(string source, AgentPacket packet)
    {
        switch (packet.Action)
        {
            case AgentActions.Notify:
                EmitNotify(source, packet.Title, packet.Message, packet.Reference, StatusSignal.Info);
                return;

            case AgentActions.ChatReply:
                EmitChat(
                    new UiChatLine
                    {
                        Timestamp = packet.Timestamp,
                        Role = "agent",
                        Message = packet.Message
                    });
                return;

            case AgentActions.StatusChanged:
                if (!TryMapStatus(packet.Message, out var mappedStatus))
                {
                    RaiseCritical(
                        source,
                        "Ungültiger Statuswert",
                        $"status_changed.message={packet.Message}",
                        packet.Reference);
                    return;
                }

                EmitStatus(
                    new UiStatusEntry
                    {
                        Timestamp = packet.Timestamp,
                        Status = ToStatusLabel(mappedStatus),
                        Title = packet.Title,
                        Reference = packet.Reference,
                        Details = $"Quelle: {source}"
                    },
                    mappedStatus,
                    notify: false);

                if (mappedStatus == StatusSignal.Red)
                {
                    EmitNotify(
                        source,
                        packet.Title,
                        "Agent hat Rot-Status gesetzt.",
                        packet.Reference,
                        StatusSignal.Red,
                        packet.Timestamp);
                }

                return;

            default:
                RaiseCritical(
                    source,
                    "Unbekannte Aktion",
                    packet.Action,
                    packet.Reference);
                return;
        }
    }

    private void RaiseCritical(string source, string title, string message, string reference)
    {
        var timestamp = DateTimeOffset.Now;

        EmitStatus(
            new UiStatusEntry
            {
                Timestamp = timestamp,
                Status = "rot",
                Title = title,
                Reference = reference,
                Details = message
            },
            StatusSignal.Red,
            notify: false);

        EmitNotify(source, title, message, reference, StatusSignal.Red, timestamp);
    }

    private void EmitNotify(
        string source,
        string title,
        string message,
        string reference,
        StatusSignal signal,
        DateTimeOffset? timestamp = null)
    {
        var entry = new UiLogEntry
        {
            Timestamp = timestamp ?? DateTimeOffset.Now,
            Source = source,
            Action = AgentActions.Notify,
            Title = title,
            Message = message,
            Reference = reference
        };

        LogEntryReceived?.Invoke(entry);
        _logService.WritePacket(entry);
        NotificationRequested?.Invoke(title, message, signal);
    }

    private void EmitStatus(UiStatusEntry entry, StatusSignal signal, bool notify)
    {
        StatusEntryReceived?.Invoke(entry);
        _logService.WriteStatus(entry);
        StatusSignalChanged?.Invoke(signal, entry.Title);

        if (notify)
        {
            NotificationRequested?.Invoke(entry.Title, entry.Details, signal);
        }
    }

    private void EmitChat(UiChatLine line)
    {
        ChatLineReceived?.Invoke(line);
        _logService.WriteChat(line);
    }

    private static bool TryMapStatus(string value, out StatusSignal signal)
    {
        switch (value.Trim().ToLowerInvariant())
        {
            case "rot":
                signal = StatusSignal.Red;
                return true;
            case "grün":
            case "gruen":
                signal = StatusSignal.Green;
                return true;
            case "gelb":
                signal = StatusSignal.Yellow;
                return true;
            case "info":
                signal = StatusSignal.Info;
                return true;
            default:
                signal = StatusSignal.Info;
                return false;
        }
    }

    private static string ToStatusLabel(StatusSignal signal)
    {
        return signal switch
        {
            StatusSignal.Red => "rot",
            StatusSignal.Yellow => "gelb",
            StatusSignal.Green => "grün",
            _ => "info"
        };
    }

    private static string ApplyTemplate(string template, string payloadJson, string userMessage)
    {
        var effectiveTemplate = string.IsNullOrWhiteSpace(template)
            ? "{{payload}}"
            : template;

        return effectiveTemplate
            .Replace("{{payload}}", payloadJson, StringComparison.Ordinal)
            .Replace("{{userMessage}}", userMessage, StringComparison.Ordinal);
    }

    private static string Compact(string value)
    {
        var oneLine = value.Replace("\r", " ", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal)
            .Trim();

        if (oneLine.Length <= 300)
        {
            return oneLine;
        }

        return oneLine[..300] + "...";
    }

    private sealed record QueuedWorkItem(
        int Id,
        string Source,
        string Reference,
        string Prompt,
        int TimeoutSeconds);
}
