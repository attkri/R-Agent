namespace ECAS.Models;

public sealed class AppConfig
{
    public int MaxParallelRuns { get; set; } = 4;

    public string OpenCodeCommand { get; set; } = "opencode";

    public string OpenCodeWorkingDirectory { get; set; } = string.Empty;

    public AutostartConfig Autostart { get; set; } = new();

    public ChatConfig Chat { get; set; } = new();

    public List<TriggerConfig> Triggers { get; set; } = [];

    public static AppConfig CreateDefault()
    {
        return new AppConfig
        {
            MaxParallelRuns = 4,
            OpenCodeCommand = "opencode",
            OpenCodeWorkingDirectory = string.Empty,
            Autostart = new AutostartConfig
            {
                Enabled = true,
                Mode = "hkcu_run"
            },
            Chat = new ChatConfig
            {
                Id = 900,
                TimeoutSeconds = 180,
                PromptTemplate =
                    """
                    Du bist der ECAS-Chat-Agent.
                    
                    Nutzer-Nachricht:
                    {{userMessage}}

                    Kontext:
                    {{payload}}

                    Antworte ausschließlich als ein JSON-Objekt mit genau diesen Feldern:
                    id, action, title, message, reference, timestamp

                    Regeln:
                    - action ist eine der folgenden Aktionen: notify, chat_reply, status_changed
                    - timestamp im ISO-8601-Format mit Zeitzone
                    - Für status_changed muss message genau einer dieser Werte sein: rot, gelb, grün, info
                    - Keine zusätzlichen Felder
                    - Keine Markdown-Ausgabe
                    """
            },
            Triggers =
            [
                new TriggerConfig
                {
                    Id = 1,
                    Name = "telegram_poll",
                    Enabled = true,
                    IntervalSeconds = 10,
                    TimeoutSeconds = 90,
                    PromptTemplate =
                        """
                        Du bist der ECAS-Event-Agent für Telegram-Empfang.

                        Trigger-Paket:
                        {{payload}}

                        Antworte ausschließlich als ein JSON-Objekt mit genau diesen Feldern:
                        id, action, title, message, reference, timestamp

                        Regeln:
                        - action ist eine der folgenden Aktionen: notify, chat_reply, status_changed
                        - timestamp im ISO-8601-Format mit Zeitzone
                        - Für status_changed muss message genau einer dieser Werte sein: rot, gelb, grün, info
                        - Keine zusätzlichen Felder
                        - Keine Markdown-Ausgabe
                        """
                },
                new TriggerConfig
                {
                    Id = 2,
                    Name = "rclone_sync_timer",
                    Enabled = true,
                    IntervalSeconds = 1800,
                    TimeoutSeconds = 3600,
                    PromptTemplate =
                        """
                        Du bist der ECAS-Event-Agent für RClone-Sync.

                        Trigger-Paket:
                        {{payload}}

                        Antworte ausschließlich als ein JSON-Objekt mit genau diesen Feldern:
                        id, action, title, message, reference, timestamp

                        Regeln:
                        - action ist eine der folgenden Aktionen: notify, chat_reply, status_changed
                        - timestamp im ISO-8601-Format mit Zeitzone
                        - Für status_changed muss message genau einer dieser Werte sein: rot, gelb, grün, info
                        - Keine zusätzlichen Felder
                        - Keine Markdown-Ausgabe
                        """
                }
            ]
        };
    }
}

public sealed class TriggerConfig
{
    public int Id { get; set; }

    public string Name { get; set; } = string.Empty;

    public bool Enabled { get; set; } = true;

    public int IntervalSeconds { get; set; } = 60;

    public int TimeoutSeconds { get; set; } = 120;

    public string PromptTemplate { get; set; } = string.Empty;
}

public sealed class ChatConfig
{
    public int Id { get; set; } = 900;

    public int TimeoutSeconds { get; set; } = 180;

    public string PromptTemplate { get; set; } = string.Empty;
}

public sealed class AutostartConfig
{
    public bool Enabled { get; set; } = true;

    public string Mode { get; set; } = "hkcu_run";
}
