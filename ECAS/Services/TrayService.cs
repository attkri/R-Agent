using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using Forms = System.Windows.Forms;
using ECAS.Models;

namespace ECAS.Services;

public sealed partial class TrayService : IDisposable
{
    private readonly Forms.NotifyIcon _notifyIcon;
    private readonly Dictionary<StatusSignal, Icon> _iconCache;

    public TrayService()
    {
        _iconCache = new Dictionary<StatusSignal, Icon>
        {
            [StatusSignal.Info] = BuildIcon(Color.DodgerBlue),
            [StatusSignal.Green] = BuildIcon(Color.ForestGreen),
            [StatusSignal.Yellow] = BuildIcon(Color.Goldenrod),
            [StatusSignal.Red] = BuildIcon(Color.Firebrick)
        };

        _notifyIcon = new Forms.NotifyIcon
        {
            Visible = true,
            Text = "ECAS",
            Icon = _iconCache[StatusSignal.Info]
        };

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Öffnen", null, (_, _) => OpenRequested?.Invoke());
        menu.Items.Add("Beenden", null, (_, _) => ExitRequested?.Invoke());
        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.DoubleClick += (_, _) => OpenRequested?.Invoke();
    }

    public event Action? OpenRequested;

    public event Action? ExitRequested;

    public void UpdateStatus(StatusSignal status, string title)
    {
        _notifyIcon.Icon = _iconCache[status];
        _notifyIcon.Text = ShortText($"ECAS - {title}");
    }

    public void ShowNotification(string title, string message, StatusSignal status)
    {
        _notifyIcon.BalloonTipTitle = title;
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.BalloonTipIcon = status switch
        {
            StatusSignal.Red => Forms.ToolTipIcon.Error,
            StatusSignal.Yellow => Forms.ToolTipIcon.Warning,
            _ => Forms.ToolTipIcon.Info
        };
        _notifyIcon.ShowBalloonTip(3000);
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();

        foreach (var icon in _iconCache.Values)
        {
            icon.Dispose();
        }
    }

    private static Icon BuildIcon(Color color)
    {
        using var bitmap = new Bitmap(16, 16);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Color.Transparent);

        using var brush = new SolidBrush(color);
        using var pen = new Pen(Color.Black, 1f);
        graphics.FillEllipse(brush, 1f, 1f, 14f, 14f);
        graphics.DrawEllipse(pen, 1f, 1f, 14f, 14f);

        var hIcon = bitmap.GetHicon();
        try
        {
            using var fromHandle = Icon.FromHandle(hIcon);
            return (Icon)fromHandle.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    private static string ShortText(string value)
    {
        if (value.Length <= 63)
        {
            return value;
        }

        return value[..63];
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
