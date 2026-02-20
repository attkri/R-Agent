namespace ECAS.Models;

public sealed class AgentPacket
{
    public int Id { get; init; }

    public string Action { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public string Reference { get; init; } = string.Empty;

    public DateTimeOffset Timestamp { get; init; }
}

public static class AgentActions
{
    public const string Notify = "notify";

    public const string ChatReply = "chat_reply";

    public const string StatusChanged = "status_changed";

    public static readonly HashSet<string> Allowed =
    [
        Notify,
        ChatReply,
        StatusChanged
    ];
}

public enum StatusSignal
{
    Info,
    Green,
    Yellow,
    Red
}
