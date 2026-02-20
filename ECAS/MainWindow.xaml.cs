using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using ECAS.Models;
using ECAS.Services;

namespace ECAS;

public partial class MainWindow : Window
{
    private readonly OrchestratorService _orchestrator;
    private readonly LogService _logService;
    private readonly CancellationTokenSource _uiCancellation;
    private bool _allowShutdown;

    public MainWindow(OrchestratorService orchestrator, LogService logService)
    {
        _orchestrator = orchestrator;
        _logService = logService;
        _uiCancellation = new CancellationTokenSource();

        ChatLines = [];
        LogEntries = [];
        StatusEntries = [];

        InitializeComponent();
        DataContext = this;

        _orchestrator.ChatLineReceived += OrchestratorOnChatLineReceived;
        _orchestrator.LogEntryReceived += OrchestratorOnLogEntryReceived;
        _orchestrator.StatusEntryReceived += OrchestratorOnStatusEntryReceived;

        Closing += MainWindow_OnClosing;
        Closed += MainWindow_OnClosed;

        _logService.WriteSystem("GUI bereit.");
    }

    public ObservableCollection<UiChatLine> ChatLines { get; }

    public ObservableCollection<UiLogEntry> LogEntries { get; }

    public ObservableCollection<UiStatusEntry> StatusEntries { get; }

    public void EnableShutdown()
    {
        _allowShutdown = true;
    }

    private void SendChatButton_OnClick(object sender, RoutedEventArgs e)
    {
        _ = SendChatAsync();
    }

    private void ChatInputTextBox_OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        if ((Keyboard.Modifiers & ModifierKeys.Shift) == ModifierKeys.Shift)
        {
            return;
        }

        e.Handled = true;
        _ = SendChatAsync();
    }

    private async Task SendChatAsync()
    {
        var text = ChatInputTextBox.Text;
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        ChatInputTextBox.Clear();

        try
        {
            await _orchestrator.EnqueueChatAsync(text, _uiCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            // Beim Schließen ignorieren.
        }
        catch (Exception ex)
        {
            _logService.WriteSystem($"Chat-Sende-Fehler: {ex.Message}");
            AppendStatus(
                new UiStatusEntry
                {
                    Timestamp = DateTimeOffset.Now,
                    Status = "rot",
                    Title = "Chat-Sende-Fehler",
                    Reference = "chat/send",
                    Details = ex.Message
                });
        }
    }

    private void MainWindow_OnClosing(object? sender, CancelEventArgs e)
    {
        if (_allowShutdown)
        {
            return;
        }

        e.Cancel = true;
        Hide();
    }

    private void MainWindow_OnClosed(object? sender, EventArgs e)
    {
        _uiCancellation.Cancel();
        _uiCancellation.Dispose();

        _orchestrator.ChatLineReceived -= OrchestratorOnChatLineReceived;
        _orchestrator.LogEntryReceived -= OrchestratorOnLogEntryReceived;
        _orchestrator.StatusEntryReceived -= OrchestratorOnStatusEntryReceived;
    }

    private void OrchestratorOnChatLineReceived(UiChatLine line)
    {
        if (Dispatcher.CheckAccess())
        {
            AppendChat(line);
            return;
        }

        Dispatcher.Invoke(() => AppendChat(line));
    }

    private void OrchestratorOnLogEntryReceived(UiLogEntry entry)
    {
        if (Dispatcher.CheckAccess())
        {
            AppendLog(entry);
            return;
        }

        Dispatcher.Invoke(() => AppendLog(entry));
    }

    private void OrchestratorOnStatusEntryReceived(UiStatusEntry entry)
    {
        if (Dispatcher.CheckAccess())
        {
            AppendStatus(entry);
            return;
        }

        Dispatcher.Invoke(() => AppendStatus(entry));
    }

    private void AppendChat(UiChatLine line)
    {
        ChatLines.Add(line);

        if (ChatListBox.Items.Count > 0)
        {
            ChatListBox.ScrollIntoView(ChatListBox.Items[^1]);
        }
    }

    private void AppendLog(UiLogEntry entry)
    {
        LogEntries.Add(entry);

        if (LogEntries.Count > 1500)
        {
            LogEntries.RemoveAt(0);
        }
    }

    private void AppendStatus(UiStatusEntry entry)
    {
        StatusEntries.Add(entry);

        if (StatusEntries.Count > 500)
        {
            StatusEntries.RemoveAt(0);
        }
    }
}
