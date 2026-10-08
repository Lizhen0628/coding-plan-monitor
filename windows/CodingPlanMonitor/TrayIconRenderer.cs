using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace CodingPlanMonitor;

/// <summary>
/// 动态绘制系统托盘图标：有数据时为「彩色圆角方块 + 百分比数字」（颜色随用量阈值变化），
/// 无数据时为仪表盘图形。对应 macOS 版菜单栏文本的 Windows 等价形态。
/// </summary>
internal static class TrayIconRenderer
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public static void DestroyHandle(IntPtr handle) => DestroyIcon(handle);

    /// <summary>返回的 Handle 由调用方在替换/退出时通过 DestroyHandle 释放。</summary>
    public static (Icon Icon, IntPtr Handle) Create(int? percentage)
    {
        const int size = 32;
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            var bg = percentage switch
            {
                >= 80 => Color.FromArgb(0xFF, 0x3B, 0x30), // 红
                >= 50 => Color.FromArgb(0xFF, 0x95, 0x00), // 橙
                _ => Color.FromArgb(0x00, 0x7A, 0xFF),     // 蓝
            };
            using (var bgBrush = new SolidBrush(bg))
                FillRoundedRectangle(g, bgBrush, new Rectangle(0, 0, size, size), 8);

            if (percentage is int p)
            {
                var text = p.ToString();
                using var font = new Font("Segoe UI", text.Length >= 3 ? 12f : 15f, FontStyle.Bold, GraphicsUnit.Pixel);
                using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString(text, font, Brushes.White, new RectangleF(0, 1, size, size), format);
            }
            else
            {
                // 仪表盘：弧线 + 指针
                using var pen = new Pen(Color.White, 2.5f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                g.DrawArc(pen, 7, 7, size - 14, size - 14, 150, 240);
                g.DrawLine(pen, size / 2f, size / 2f + 2, size / 2f + 6, size / 2f - 6);
                using var dot = new SolidBrush(Color.White);
                g.FillEllipse(dot, size / 2f - 2, size / 2f, 4, 4);
            }
        }
        var handle = bmp.GetHicon();
        return (Icon.FromHandle(handle), handle);
    }

    private static void FillRoundedRectangle(Graphics g, Brush brush, Rectangle rect, int radius)
    {
        using var path = new GraphicsPath();
        int d = radius * 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }
}
