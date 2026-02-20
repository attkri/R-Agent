using System.Text.Json;
using ECAS.Models;

namespace ECAS.Services;

public sealed class AgentPacketParser
{
    private static readonly HashSet<string> RequiredProperties =
    [
        "id",
        "action",
        "title",
        "message",
        "reference",
        "timestamp"
    ];

    public bool TryParse(string rawOutput, out AgentPacket? packet, out string error)
    {
        packet = null;
        error = string.Empty;

        if (string.IsNullOrWhiteSpace(rawOutput))
        {
            error = "Leere OpenCode-Ausgabe.";
            return false;
        }

        var candidates = EnumerateCandidates(rawOutput).ToList();
        if (candidates.Count == 0)
        {
            error = "Kein JSON-Objekt in der OpenCode-Ausgabe gefunden.";
            return false;
        }

        foreach (var candidate in candidates)
        {
            if (TryParseStrictObject(candidate, out packet, out _))
            {
                return true;
            }
        }

        error = "Kein strikt valides Agent-JSON gefunden (Schema/Typen/Aktionen ungültig).";
        return false;
    }

    private static IEnumerable<string> EnumerateCandidates(string rawOutput)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<string>();

        void Add(string? candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate))
            {
                return;
            }

            var trimmedCandidate = candidate.Trim();
            if (!LooksLikeJsonObject(trimmedCandidate))
            {
                return;
            }

            if (!seen.Add(trimmedCandidate))
            {
                return;
            }

            result.Add(trimmedCandidate);
        }

        void CollectRecursive(JsonElement element)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.Object:
                    Add(element.GetRawText());
                    foreach (var property in element.EnumerateObject())
                    {
                        CollectRecursive(property.Value);
                    }
                    break;

                case JsonValueKind.Array:
                    foreach (var item in element.EnumerateArray())
                    {
                        CollectRecursive(item);
                    }
                    break;

                case JsonValueKind.String:
                    Add(element.GetString());
                    break;
            }
        }

        void ParseAndCollect(string candidate)
        {
            try
            {
                using var doc = JsonDocument.Parse(candidate);
                CollectRecursive(doc.RootElement);
            }
            catch
            {
                // Ignorieren: Candidate ist kein parsebares JSON.
            }
        }

        var trimmed = rawOutput.Trim();
        if (LooksLikeJsonObject(trimmed))
        {
            Add(trimmed);
            ParseAndCollect(trimmed);
        }

        foreach (var line in rawOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = line.Trim();
            if (!LooksLikeJsonObject(candidate))
            {
                continue;
            }

            Add(candidate);
            ParseAndCollect(candidate);
        }

        return result;
    }

    private static bool TryParseStrictObject(string json, out AgentPacket? packet, out string error)
    {
        packet = null;
        error = string.Empty;

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                error = "Root ist kein JSON-Objekt.";
                return false;
            }

            var properties = root.EnumerateObject().Select(x => x.Name).ToHashSet(StringComparer.Ordinal);
            if (!properties.SetEquals(RequiredProperties))
            {
                error = "JSON-Felder passen nicht exakt zum ECAS-Schema.";
                return false;
            }

            if (!root.TryGetProperty("id", out var idElement) || idElement.ValueKind != JsonValueKind.Number)
            {
                error = "Feld id fehlt oder ist kein Integer.";
                return false;
            }

            if (!idElement.TryGetInt32(out var id) || id < 1)
            {
                error = "Feld id muss numerisch >= 1 sein.";
                return false;
            }

            var action = ReadString(root, "action", ref error);
            if (action is null)
            {
                return false;
            }

            if (!AgentActions.Allowed.Contains(action))
            {
                error = "Feld action enthält einen unzulässigen Wert.";
                return false;
            }

            var title = ReadString(root, "title", ref error);
            var message = ReadString(root, "message", ref error);
            var reference = ReadString(root, "reference", ref error);
            var timestampRaw = ReadString(root, "timestamp", ref error);
            if (title is null || message is null || reference is null || timestampRaw is null)
            {
                return false;
            }

            if (!DateTimeOffset.TryParse(timestampRaw, out var timestamp))
            {
                error = "Feld timestamp ist kein gültiges ISO-8601-Datum.";
                return false;
            }

            packet = new AgentPacket
            {
                Id = id,
                Action = action,
                Title = title,
                Message = message,
                Reference = reference,
                Timestamp = timestamp
            };

            return true;
        }
        catch (JsonException)
        {
            error = "JSON ist syntaktisch ungültig.";
            return false;
        }
        catch (Exception ex)
        {
            error = $"Unerwarteter Parse-Fehler: {ex.Message}";
            return false;
        }
    }

    private static string? ReadString(JsonElement root, string name, ref string error)
    {
        if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
        {
            error = $"Feld {name} fehlt oder ist kein String.";
            return null;
        }

        return element.GetString() ?? string.Empty;
    }

    private static bool LooksLikeJsonObject(string text)
    {
        return text.Length >= 2 && text[0] == '{' && text[^1] == '}';
    }
}
