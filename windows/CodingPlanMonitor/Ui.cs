using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace CodingPlanMonitor;

/// <summary>共享画刷与控件构造（面板与设置页共用）</summary>
internal static class Ui
{
    public static readonly SolidColorBrush Accent = Freeze(new SolidColorBrush(Color.FromRgb(0x00, 0x7A, 0xFF)));
    public static readonly SolidColorBrush Orange = Freeze(new SolidColorBrush(Color.FromRgb(0xFF, 0x95, 0x00)));
    public static readonly SolidColorBrush Red = Freeze(new SolidColorBrush(Color.FromRgb(0xFF, 0x3B, 0x30)));
    public static readonly SolidColorBrush Green = Freeze(new SolidColorBrush(Color.FromRgb(0x34, 0xC7, 0x59)));
    public static readonly SolidColorBrush Gray = Freeze(new SolidColorBrush(Color.FromRgb(0x8E, 0x8E, 0x93)));
    public static readonly SolidColorBrush PrimaryText = Freeze(new SolidColorBrush(Color.FromRgb(0x1D, 0x1D, 0x1F)));
    public static readonly SolidColorBrush SecondaryText = Freeze(new SolidColorBrush(Color.FromRgb(0x6E, 0x6E, 0x73)));
    public static readonly SolidColorBrush TertiaryText = Freeze(new SolidColorBrush(Color.FromRgb(0x8E, 0x8E, 0x93)));
    public static readonly SolidColorBrush Hover = Freeze(new SolidColorBrush(Color.FromArgb(0x12, 0, 0, 0)));
    public static readonly SolidColorBrush TrackBg = Freeze(new SolidColorBrush(Color.FromRgb(0xE9, 0xE9, 0xEB)));
    public static readonly SolidColorBrush Separator = Freeze(new SolidColorBrush(Color.FromRgb(0xE6, 0xE6, 0xEA)));

    private static SolidColorBrush Freeze(SolidColorBrush brush)
    {
        brush.Freeze();
        return brush;
    }

    /// <summary>用量阈值配色：&gt;=80 红，&gt;=50 橙，其余蓝</summary>
    public static Brush TintFor(double? percentage) => percentage switch
    {
        >= 80 => Red,
        >= 50 => Orange,
        _ => Accent,
    };

    /// <summary>供应商徽标（圆角彩色方块 + 前缀字母）</summary>
    public static Border Badge(Provider provider, double size)
    {
        var border = new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size * 0.27),
            Background = new SolidColorBrush(ProviderInfo.TintColor(provider)),
        };
        border.Child = new TextBlock
        {
            Text = ProviderInfo.ShortLabel(provider),
            Foreground = Brushes.White,
            FontWeight = FontWeights.Bold,
            FontSize = Math.Max(8, size * 0.40),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        return border;
    }

    /// <summary>操作行（悬停高亮，点击触发）</summary>
    public static Border ActionRow(string title, string glyph, string shortcut, Action action,
        bool isDestructive = false)
    {
        var border = new Border
        {
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(0, 1, 0, 1),
            Cursor = Cursors.Hand,
            Background = Brushes.Transparent,
        };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var color = isDestructive ? Red : PrimaryText;
        var icon = new TextBlock
        {
            Text = glyph,
            Width = 18,
            FontSize = 12,
            Foreground = isDestructive ? Red : SecondaryText,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var text = new TextBlock
        {
            Text = title,
            FontSize = 13,
            Margin = new Thickness(8, 0, 0, 0),
            Foreground = color,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var hint = new TextBlock
        {
            Text = shortcut,
            FontSize = 11,
            Foreground = TertiaryText,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(text, 1);
        Grid.SetColumn(hint, 2);
        grid.Children.Add(icon);
        grid.Children.Add(text);
        grid.Children.Add(hint);
        border.Child = grid;

        border.MouseEnter += (_, _) => border.Background = Hover;
        border.MouseLeave += (_, _) => border.Background = Brushes.Transparent;
        border.MouseLeftButtonUp += (_, _) => action();
        return border;
    }

    public static Border SeparatorLine(Thickness margin) => new()
    {
        Height = 1,
        Background = Separator,
        Margin = margin,
    };
}
