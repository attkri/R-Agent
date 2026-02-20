namespace ECAS.Models;

public sealed class UiLogEntry
{
    public DateTimeOffset Timestamp { get; init; }

    public string Source { get; init; } = string.Empty;

    public string Action { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public string Reference { get; init; } = string.Empty;
}

public sealed class UiStatusEntry
{
    public DateTimeOffset Timestamp { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string Reference { get; init; } = string.Empty;

    public string Details { get; init; } = string.Empty;
}

public sealed class UiChatLine
{
    public DateTimeOffset Timestamp { get; init; }

    public string Role { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;
}
