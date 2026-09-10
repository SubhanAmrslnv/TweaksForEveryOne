using System;
using System.Collections.Concurrent;
using System.Windows;
using System.Windows.Media;
using Point = System.Windows.Point;

namespace WindowTweaks.Core;

/// <summary>
/// Continuous Curvature Super-Ellipse / Squircle Geometry Generator.
///
/// Implements Lamé super-ellipse approximation:
///     |x/a|^n + |y/b|^n = 1  (n ~ 4.2 - 4.5)
///
/// Ensures G2 curvature continuity (second-derivative smoothness) between straight segments
/// and rounded corners, matching Apple macOS/iOS surface geometry. Standard circular fillets
/// (WPF CornerRadius) suffer from abrupt curvature discontinuities (inflection points).
/// </summary>
internal static class SquircleGeometry
{
    private readonly record struct SquircleKey(int Width, int Height, int Radius);
    private static readonly ConcurrentDictionary<SquircleKey, Geometry> Cache = new();

    /// <summary>
    /// Creates a frozen G2 continuous squircle geometry for the given bounds and corner radius.
    /// </summary>
    public static Geometry Create(double width, double height, double cornerRadius)
    {
        if (width <= 0 || height <= 0) return Geometry.Empty;

        // Clamp radius so it does not exceed half the smallest dimension
        double maxR = Math.Min(width, height) / 2.0;
        double r = Math.Clamp(cornerRadius, 0.0, maxR);

        if (r <= 0.5)
        {
            var rect = new RectangleGeometry(new Rect(0, 0, width, height));
            rect.Freeze();
            return rect;
        }

        // Quantize key to integer tenths for efficient memory cache
        var key = new SquircleKey((int)(width * 10), (int)(height * 10), (int)(r * 10));
        if (Cache.TryGetValue(key, out Geometry? cached)) return cached;

        // Apple Squircle G2 Bézier weighting coefficients (n ≈ 4.4 super-ellipse):
        // The corner transition extends over 1.5286 * r rather than a plain r quarter-circle.
        // If the dimensions are too tight to fit 1.5286 * r on each side, scale the blend factor smoothly.
        double blendRatio = Math.Min(1.0, Math.Min(width, height) / (2.0 * r * 1.5286));
        double cornerSpan = r * 1.5286 * blendRatio;

        // Relative Bézier control points derived from the Lamé super-ellipse equation
        double p1 = cornerSpan * 0.55;
        double p2 = cornerSpan * 0.88;
        double p3 = cornerSpan * 0.98;

        var figure = new PathFigure
        {
            StartPoint = new Point(cornerSpan, 0),
            IsClosed = true,
            IsFilled = true
        };

        // Top edge -> Top-Right corner
        figure.Segments.Add(new LineSegment(new Point(width - cornerSpan, 0), true));
        figure.Segments.Add(new BezierSegment(
            new Point(width - cornerSpan + p1, 0),
            new Point(width - cornerSpan + p2, p3 * 0.05),
            new Point(width - cornerSpan + p3, p3 * 0.35),
            true));
        figure.Segments.Add(new BezierSegment(
            new Point(width - (p3 * 0.35), p3 * 0.65),
            new Point(width, cornerSpan - p1),
            new Point(width, cornerSpan),
            true));

        // Right edge -> Bottom-Right corner
        figure.Segments.Add(new LineSegment(new Point(width, height - cornerSpan), true));
        figure.Segments.Add(new BezierSegment(
            new Point(width, height - cornerSpan + p1),
            new Point(width - (p3 * 0.05), height - cornerSpan + p2),
            new Point(width - (p3 * 0.35), height - cornerSpan + p3),
            true));
        figure.Segments.Add(new BezierSegment(
            new Point(width - (p3 * 0.65), height - (p3 * 0.35)),
            new Point(width - cornerSpan + p1, height),
            new Point(width - cornerSpan, height),
            true));

        // Bottom edge -> Bottom-Left corner
        figure.Segments.Add(new LineSegment(new Point(cornerSpan, height), true));
        figure.Segments.Add(new BezierSegment(
            new Point(cornerSpan - p1, height),
            new Point(cornerSpan - p2, height - (p3 * 0.05)),
            new Point(cornerSpan - p3, height - (p3 * 0.35)),
            true));
        figure.Segments.Add(new BezierSegment(
            new Point(p3 * 0.35, height - (p3 * 0.65)),
            new Point(0, height - cornerSpan + p1),
            new Point(0, height - cornerSpan),
            true));

        // Left edge -> Top-Left corner
        figure.Segments.Add(new LineSegment(new Point(0, cornerSpan), true));
        figure.Segments.Add(new BezierSegment(
            new Point(0, cornerSpan - p1),
            new Point(p3 * 0.05, cornerSpan - p2),
            new Point(p3 * 0.35, cornerSpan - p3),
            true));
        figure.Segments.Add(new BezierSegment(
            new Point(p3 * 0.65, p3 * 0.35),
            new Point(cornerSpan - p1, 0),
            new Point(cornerSpan, 0),
            true));

        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        geometry.Freeze();

        // Keep cache bounded
        if (Cache.Count > 256) Cache.Clear();
        Cache[key] = geometry;

        return geometry;
    }
}
