//! Per-tab visual polish: the close-button fade.
//!
//! Each tab's close button is invisible at rest (alpha 0). On hover-enter
//! the alpha fades to 1 over `close_fade_ms`; on hover-leave it fades back
//! to 0 over the same duration. The hit-zone width scales in lockstep so
//! that clicks at partial alpha land correctly.
//!
//! The state machine is allocation-free, Win32-free, and testable in
//! isolation. The paint layer calls `alphaAt` each frame and pre-composites
//! the close glyph's colour with the result. The fade uses a cubic
//! ease-in-out curve (slow start, fast middle, slow end).

const std = @import("std");
const geometry = @import("win32_geometry.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Duration for close-button fade-in or fade-out, in milliseconds.
pub const close_fade_ms: u64 = 120;

// ---------------------------------------------------------------------------
// Easing
// ---------------------------------------------------------------------------

/// Standard cubic ease-in-out: 0 at t=0, 1 at t=1, smooth at both ends.
/// t is clamped to [0, 1].
///
/// Formula: t < 0.5 => 4*t^3  else  1 - (-2*t + 2)^3 / 2
pub fn easeInOutCubic(t: f32) f32 {
    const s = std.math.clamp(t, 0.0, 1.0);
    if (s < 0.5) {
        return 4.0 * s * s * s;
    } else {
        const p = -2.0 * s + 2.0;
        return 1.0 - (p * p * p) / 2.0;
    }
}

// ---------------------------------------------------------------------------
// CloseState
// ---------------------------------------------------------------------------

/// Per-tab close-button hover fade state.
pub const CloseState = struct {
    /// Current animated alpha (updated lazily via `alphaAt`).
    alpha: f32 = 0.0,
    /// Animation target: 0 = hidden, 1 = visible.
    target: f32 = 0.0,
    /// Timestamp when the current fade began.
    fade_started_ms: u64 = 0,
    /// Alpha at the moment the current fade was initiated. This lets a
    /// mid-fade reversal start from the current visual alpha rather than
    /// snapping to 0 or 1.
    start_alpha: f32 = 0.0,

    /// Trigger a fade-in (hovered=true) or fade-out (hovered=false).
    /// Captures the current visual alpha so mid-fade reversals are smooth.
    pub fn setHovered(self: *CloseState, hovered: bool, now_ms: u64) void {
        const new_target: f32 = if (hovered) 1.0 else 0.0;
        if (new_target == self.target) return;
        self.start_alpha = self.alphaAt(now_ms);
        self.target = new_target;
        self.fade_started_ms = now_ms;
    }

    /// Apply the host's effective motion policy to this fade.
    pub fn setHoveredWithMotion(self: *CloseState, hovered: bool, now_ms: u64, animate: bool) void {
        self.setHovered(hovered, now_ms);
        if (!animate) {
            self.alpha = self.target;
            self.start_alpha = self.target;
            self.fade_started_ms = 0;
        }
    }

    /// Compute the current alpha based on fade progress. Clamps to [0, 1].
    pub fn alphaAt(self: CloseState, now_ms: u64) f32 {
        if (self.fade_started_ms == 0) return self.alpha;
        if (now_ms <= self.fade_started_ms) return self.start_alpha;
        const elapsed = now_ms - self.fade_started_ms;
        if (elapsed >= close_fade_ms) return self.target;
        const t: f32 = @as(f32, @floatFromInt(elapsed)) /
            @as(f32, @floatFromInt(close_fade_ms));
        const eased = easeInOutCubic(t);
        return self.start_alpha + (self.target - self.start_alpha) * eased;
    }

    /// True while the animation is mid-fade; the caller should schedule
    /// another repaint tick.
    pub fn animating(self: CloseState, now_ms: u64) bool {
        if (self.fade_started_ms == 0) return false;
        if (now_ms <= self.fade_started_ms) return true;
        return (now_ms - self.fade_started_ms) < close_fade_ms;
    }
};

// ---------------------------------------------------------------------------
// Sliding cap
// ---------------------------------------------------------------------------

/// Duration of the active tab's cap sliding to a new tab, in milliseconds.
pub const cap_slide_ms: u64 = 240;

/// The leading edge reaches its place in this share of the slide, so the
/// cap stretches toward the new tab and the trailing edge catches up.
const cap_lead_share: f32 = 0.6;

/// Exponential-feel ease-out (quint), DESIGN.md's curve for motion.
pub fn easeOutQuint(t: f32) f32 {
    const inv = 1.0 - std.math.clamp(t, 0.0, 1.0);
    return 1.0 - inv * inv * inv * inv * inv;
}

pub const Span = struct { left: i32, right: i32 };

fn lerpEdge(from: i32, to: i32, t: f32) i32 {
    const span: f32 = @floatFromInt(to - from);
    return from + @as(i32, @intFromFloat(@round(span * t)));
}

/// The active tab's cap on its way between two tabs. Edges are in the
/// window's client coordinates: the tabs are separate child windows, so
/// each paints the part of the bar that crosses it.
pub const CapSlide = struct {
    from: Span = .{ .left = 0, .right = 0 },
    to: Span = .{ .left = 0, .right = 0 },
    /// 0 when no slide is running.
    started_ms: u64 = 0,

    /// Start toward `to`. A slide already running continues from where the
    /// bar is now, so quick tab switching never jumps.
    pub fn start(self: *CapSlide, from: Span, to: Span, now_ms: u64) void {
        self.from = if (self.animating(now_ms)) self.edgesAt(now_ms) else from;
        self.to = to;
        self.started_ms = now_ms;
    }

    pub fn animating(self: CapSlide, now_ms: u64) bool {
        if (self.started_ms == 0) return false;
        return now_ms < self.started_ms + cap_slide_ms;
    }

    /// 0 at the start, 1 at the end; what the two tabs' surfaces fade by.
    pub fn progressAt(self: CapSlide, now_ms: u64) f32 {
        if (self.started_ms == 0 or now_ms >= self.started_ms + cap_slide_ms) return 1;
        const elapsed: f32 = @floatFromInt(now_ms -| self.started_ms);
        return easeOutQuint(elapsed / @as(f32, @floatFromInt(cap_slide_ms)));
    }

    pub fn edgesAt(self: CapSlide, now_ms: u64) Span {
        if (self.started_ms == 0 or now_ms >= self.started_ms + cap_slide_ms) return self.to;
        const elapsed: f32 = @floatFromInt(now_ms -| self.started_ms);
        const t = elapsed / @as(f32, @floatFromInt(cap_slide_ms));
        const lead = easeOutQuint(t / cap_lead_share);
        const trail = easeOutQuint(t);
        const rightward = self.to.left >= self.from.left;
        return .{
            .left = lerpEdge(self.from.left, self.to.left, if (rightward) trail else lead),
            .right = lerpEdge(self.from.right, self.to.right, if (rightward) lead else trail),
        };
    }
};

/// The hover line: it grows out of the tab's center as the hover fades in
/// and withdraws into it as the hover fades out.
pub fn hoverLineSpan(left: i32, right: i32, fade: f32) Span {
    const half: f32 = @as(f32, @floatFromInt(right - left)) / 2.0;
    const reach: i32 = @intFromFloat(@round(half * easeOutQuint(fade)));
    const center = left + @divTrunc(right - left, 2);
    return .{ .left = center - reach, .right = center + reach };
}

// ---------------------------------------------------------------------------
// Hit-zone helper
// ---------------------------------------------------------------------------

pub const Rect = geometry.Rect;

/// Given a tab button's full rect and the current close-button alpha,
/// return the close-button hit rect. When alpha == 0 the hit zone has
/// zero width (clicks fall through to the tab body). When alpha == 1
/// the hit zone is a right-aligned square of side `close_zone_width_px`.
/// Intermediate alphas scale the width linearly.
pub fn closeHitRect(tab_rect: Rect, alpha: f32, close_zone_width_px: i32) Rect {
    const a = std.math.clamp(alpha, 0.0, 1.0);
    const w: i32 = @intFromFloat(@as(f32, @floatFromInt(close_zone_width_px)) * a);
    return .{
        .left = tab_rect.right - w,
        .top = tab_rect.top,
        .right = tab_rect.right,
        .bottom = tab_rect.bottom,
    };
}

/// The air, in DIPs, between a tab's close X and the button's right edge:
/// past the active tab's flare (4 DIP), where its body ends, and 4 DIP
/// more, so the X never touches the tab's side.
pub const close_edge: i32 = 8;

/// The chip behind a tab's close X: a `chip_px` square centered in the close
/// zone less its `edge_px` of air on the right, below `top_inset` (the rows a
/// flush tab keeps out of the close zone). A tab too short for the chip gets
/// as much of it as fits.
pub fn closeChipRect(button: Rect, zone_px: i32, chip_px: i32, top_inset: i32, edge_px: i32) Rect {
    const top = button.top + top_inset;
    const room = @max(0, zone_px - edge_px);
    const side = @max(0, @min(chip_px, @min(room, button.bottom - top)));
    const left = button.right - zone_px + @divTrunc(room - side, 2);
    const y = top + @divTrunc(button.bottom - top - side, 2);
    return .{ .left = left, .top = y, .right = left + side, .bottom = y + side };
}

/// How far the chip's fill moves from the tab toward the label color: none
/// at rest, a soft fill under the pointer, firmer while pressed, and only as
/// visible as the X itself mid-fade. A press that slid off the zone reads as
/// released, as the mouse-up will.
pub fn closeChipStrength(hot: bool, pressed: bool, alpha: f32) f32 {
    if (!hot) return 0;
    const full: f32 = if (pressed) 0.26 else 0.15;
    return full * std.math.clamp(alpha, 0.0, 1.0);
}

/// Whether the hairline at a tab's right edge shows. It separates two resting
/// tabs; a lit tab (active, hovered or pressed) already has its own shape, so
/// a line against either side of one would read as a stray tick.
pub fn dividerVisible(lit_here: bool, lit_next: bool) bool {
    return !lit_here and !lit_next;
}

// ---------------------------------------------------------------------------
// Active tab silhouette
// ---------------------------------------------------------------------------

/// How far a quarter-circle corner of `radius` px sits in from its shape's
/// straight edge on `row`, where row 0 is the row farthest from the corner's
/// centre (a tab's top row, a flare's bottom row). Measured on the row's
/// centre line, so the painter can blend the one pixel the curve cuts. Rows
/// past the corner are 0.
pub fn cornerInset(radius: i32, row: i32) f32 {
    if (radius <= 0 or row < 0 or row >= radius) return 0;
    const r: f32 = @floatFromInt(radius);
    const d = r - @as(f32, @floatFromInt(row)) - 0.5;
    return r - @sqrt(r * r - d * d);
}

/// The active tab's outline inside its button: a body inset by `flare` on
/// each side with rounded upper corners, whose bottom `flare` rows widen in
/// concave curves to the button's edges, so the tab flows into the row below
/// it instead of dropping into it at a right angle.
pub const Silhouette = struct {
    top: i32,
    bottom: i32,
    body_left: i32,
    body_right: i32,
    radius: i32,
    flare: i32,

    /// Exact left and right edges of `y`'s row, or null outside the shape.
    pub const Row = struct { left: f32, right: f32 };

    pub fn row(self: Silhouette, y: i32) ?Row {
        if (y < self.top or y >= self.bottom) return null;
        const left: f32 = @floatFromInt(self.body_left);
        const right: f32 = @floatFromInt(self.body_right);
        const from_top = y - self.top;
        if (from_top < self.radius) {
            const inset = cornerInset(self.radius, from_top);
            return .{ .left = left + inset, .right = right - inset };
        }
        const reach = cornerInset(self.flare, self.bottom - 1 - y);
        return .{ .left = left - reach, .right = right + reach };
    }

    /// The same shape `px` inside this one on its top and both sides,
    /// corners and flares included; the bottom stays open, so filling it
    /// over this one leaves a `px` outline that runs down into the join.
    pub fn insetBy(self: Silhouette, px: i32) Silhouette {
        return .{
            .top = self.top + px,
            .bottom = self.bottom,
            .body_left = self.body_left + px,
            .body_right = self.body_right - px,
            .radius = @max(0, self.radius - px),
            .flare = self.flare,
        };
    }
};

/// The silhouette of a `button` whose shape starts at row `top`, with
/// `radius` px upper corners and `flare` px bottom flares. Both shrink on a
/// narrow or short button so the body keeps its width and the corners never
/// meet the flares; null when nothing is left to draw.
pub fn silhouette(button: Rect, top: i32, radius: i32, flare: i32) ?Silhouette {
    const height = button.bottom - top;
    const width = button.right - button.left;
    if (height <= 0 or width <= 2) return null;
    const f = std.math.clamp(flare, 0, @min(@divTrunc(width, 6), @divTrunc(height, 3)));
    const body = width - 2 * f;
    const r = std.math.clamp(radius, 0, @min(@divTrunc(body, 2), height - f));
    return .{
        .top = top,
        .bottom = button.bottom,
        .body_left = button.left + f,
        .body_right = button.right - f,
        .radius = r,
        .flare = f,
    };
}

// ===========================================================================
// Tests
// ===========================================================================

test "easeInOutCubic: f(0) = 0" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), easeInOutCubic(0.0), 1e-6);
}

test "easeInOutCubic: f(1) = 1" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), easeInOutCubic(1.0), 1e-6);
}

test "easeInOutCubic: f(0.5) = 0.5" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), easeInOutCubic(0.5), 1e-6);
}

test "easeInOutCubic: f(0.25) < 0.25 — slow start" {
    try std.testing.expect(easeInOutCubic(0.25) < 0.25);
}

test "easeInOutCubic: f(0.75) > 0.75 — slow end" {
    try std.testing.expect(easeInOutCubic(0.75) > 0.75);
}

// ---------------------------------------------------------------------------
// CloseState tests
// ---------------------------------------------------------------------------

test "CHROME57 reduced-motion close reveal snaps both directions and mid-fade" {
    var state: CloseState = .{};
    state.setHoveredWithMotion(true, 1000, false);
    try std.testing.expectEqual(@as(f32, 1), state.alphaAt(1000));
    try std.testing.expect(!state.animating(1000));
    state.setHoveredWithMotion(false, 1001, false);
    try std.testing.expectEqual(@as(f32, 0), state.alphaAt(1001));
    state.setHoveredWithMotion(true, 1100, true);
    state.setHoveredWithMotion(true, 1140, false);
    try std.testing.expectEqual(@as(f32, 1), state.alphaAt(1140));
    try std.testing.expect(!state.animating(1140));
}

test "CloseState: default is hidden" {
    const cs: CloseState = .{};
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cs.alpha, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cs.target, 1e-6);
}

test "CloseState: setHovered(true) triggers fade-in" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cs.target, 1e-6);
    try std.testing.expect(cs.animating(1000));
}

test "CloseState: alphaAt at start of fade" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    // At the exact start time, alpha should be the start value (0).
    const a = cs.alphaAt(1000);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), a, 0.01);
}

test "CloseState: alphaAt after fade_ms" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    const a = cs.alphaAt(1000 + close_fade_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), a, 1e-6);
}

test "CloseState: alphaAt at mid-fade" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    const a = cs.alphaAt(1000 + close_fade_ms / 2);
    // easeInOutCubic(0.5) == 0.5, so mid-fade from 0->1 gives ~0.5.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), a, 0.05);
}

test "CloseState: setHovered(false) mid-fade reverses" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    // At 25% into the fade-in, reverse.
    const mid_time = 1000 + close_fade_ms / 4;
    const captured_alpha = cs.alphaAt(mid_time);
    cs.setHovered(false, mid_time);
    // start_alpha should be the captured mid-fade alpha, target should be 0.
    try std.testing.expectApproxEqAbs(captured_alpha, cs.start_alpha, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cs.target, 1e-6);
    try std.testing.expect(cs.animating(mid_time));
}

test "CloseState: animating false after completion" {
    var cs: CloseState = .{};
    cs.setHovered(true, 1000);
    try std.testing.expect(!cs.animating(1000 + close_fade_ms + 1));
}

// ---------------------------------------------------------------------------
// closeHitRect tests
// ---------------------------------------------------------------------------

test "closeHitRect: alpha=0 gives zero-width" {
    const tab: Rect = .{ .left = 10, .top = 0, .right = 110, .bottom = 30 };
    const r = closeHitRect(tab, 0.0, 20);
    try std.testing.expectEqual(r.left, r.right);
}

test "closeHitRect: alpha=1 gives full-width square" {
    const tab: Rect = .{ .left = 10, .top = 0, .right = 110, .bottom = 30 };
    const r = closeHitRect(tab, 1.0, 20);
    try std.testing.expectEqual(@as(i32, 90), r.left);
    try std.testing.expectEqual(@as(i32, 110), r.right);
    try std.testing.expectEqual(@as(i32, 0), r.top);
    try std.testing.expectEqual(@as(i32, 30), r.bottom);
}

test "closeHitRect: alpha=0.5 gives half-width" {
    const tab: Rect = .{ .left = 10, .top = 0, .right = 110, .bottom = 30 };
    const r = closeHitRect(tab, 0.5, 20);
    try std.testing.expectEqual(@as(i32, 100), r.left);
    try std.testing.expectEqual(@as(i32, 110), r.right);
}

// ---------------------------------------------------------------------------
// Close chip and divider tests
// ---------------------------------------------------------------------------

test "closeChipRect centers the chip in the close zone at every DPI" {
    for ([_]i32{ 1, 2, 3 }) |scale| {
        const tab: Rect = .{ .left = 0, .top = 0, .right = 200 * scale, .bottom = 32 * scale };
        const chip = closeChipRect(tab, 30 * scale, 18 * scale, 0, 8 * scale);
        try std.testing.expectEqual(18 * scale, chip.right - chip.left);
        try std.testing.expectEqual(18 * scale, chip.bottom - chip.top);
        try std.testing.expectEqual(tab.right - 10 * scale, chip.right);
        try std.testing.expectEqual(chip.top, tab.bottom - chip.bottom);
    }
}

test "closeChipRect keeps the X off the active tab's side at every DPI" {
    // Regression: the chip was centered in a zone flush with the button's
    // edge, so the X ran into the silhouette's side 4 DIP inside it.
    for ([_]i32{ 1, 2, 3 }) |scale| {
        const tab: Rect = .{ .left = 0, .top = 0, .right = 200 * scale, .bottom = 32 * scale };
        const shape = silhouette(tab, 0, 6 * scale, 4 * scale).?;
        const chip = closeChipRect(tab, 30 * scale, 18 * scale, 0, close_edge * scale);
        try std.testing.expect(shape.body_right - chip.right >= 4 * scale);
    }
}

test "Silhouette.insetBy leaves a one pixel outline on the top, sides and flares, open at the bottom" {
    const tab: Rect = .{ .left = 0, .top = 0, .right = 200, .bottom = 32 };
    const outer = silhouette(tab, 0, 6, 4).?;
    const inner = outer.insetBy(1);
    try std.testing.expect(inner.row(0) == null);
    var y: i32 = 1;
    while (y < outer.bottom) : (y += 1) {
        const o = outer.row(y).?;
        const i = inner.row(y).?;
        try std.testing.expect(i.left - o.left >= 1 - 1e-4);
        try std.testing.expect(o.right - i.right >= 1 - 1e-4);
    }
    try std.testing.expectEqual(outer.bottom, inner.bottom);
}

test "closeChipRect stays below a flush tab's top inset and inside a short tab" {
    const tab: Rect = .{ .left = 0, .top = 0, .right = 200, .bottom = 34 };
    const flush = closeChipRect(tab, 30, 18, 3, 8);
    try std.testing.expect(flush.top >= 3);
    const short: Rect = .{ .left = 0, .top = 0, .right = 200, .bottom = 12 };
    const squeezed = closeChipRect(short, 30, 18, 0, 8);
    try std.testing.expectEqual(@as(i32, 12), squeezed.bottom - squeezed.top);
    try std.testing.expectEqual(squeezed.right - squeezed.left, squeezed.bottom - squeezed.top);
}

test "closeChipStrength: nothing at rest, firmer when pressed, follows the X's fade" {
    try std.testing.expectEqual(@as(f32, 0), closeChipStrength(false, true, 1.0));
    const hover = closeChipStrength(true, false, 1.0);
    try std.testing.expect(hover > 0);
    try std.testing.expect(closeChipStrength(true, true, 1.0) > hover);
    try std.testing.expectApproxEqAbs(hover / 2, closeChipStrength(true, false, 0.5), 1e-6);
}

test "dividerVisible: only between two resting tabs" {
    try std.testing.expect(dividerVisible(false, false));
    try std.testing.expect(!dividerVisible(true, false));
    try std.testing.expect(!dividerVisible(false, true));
    try std.testing.expect(!dividerVisible(true, true));
}

// ---------------------------------------------------------------------------
// Sliding cap tests
// ---------------------------------------------------------------------------

test "CapSlide: the leading edge stretches ahead and both edges land exactly" {
    var slide: CapSlide = .{};
    const a: Span = .{ .left = 10, .right = 200 };
    const b: Span = .{ .left = 410, .right = 600 };
    slide.start(a, b, 1000);
    try std.testing.expectEqual(a, slide.edgesAt(1000));
    const mid = slide.edgesAt(1000 + cap_slide_ms / 4);
    // Rightward: the bar is wider than either tab while it travels.
    try std.testing.expect(mid.right - mid.left > a.right - a.left);
    try std.testing.expectEqual(b, slide.edgesAt(1000 + cap_slide_ms));
    try std.testing.expect(!slide.animating(1000 + cap_slide_ms));
    try std.testing.expectEqual(@as(f32, 1), slide.progressAt(1000 + cap_slide_ms));
}

test "CapSlide: leftward the left edge leads" {
    var slide: CapSlide = .{};
    const a: Span = .{ .left = 410, .right = 600 };
    const b: Span = .{ .left = 10, .right = 200 };
    slide.start(a, b, 1000);
    const mid = slide.edgesAt(1000 + cap_slide_ms / 4);
    try std.testing.expect(a.left - mid.left > a.right - mid.right);
}

test "CapSlide: a slide retargeted midway starts from where the bar is" {
    var slide: CapSlide = .{};
    const a: Span = .{ .left = 0, .right = 100 };
    const b: Span = .{ .left = 300, .right = 400 };
    const c: Span = .{ .left = 600, .right = 700 };
    slide.start(a, b, 1000);
    const halfway = 1000 + cap_slide_ms / 4;
    const bar = slide.edgesAt(halfway);
    slide.start(b, c, halfway);
    try std.testing.expectEqual(bar, slide.edgesAt(halfway));
}

test "CapSlide: idle reports its resting edges and is not animating" {
    const slide: CapSlide = .{};
    try std.testing.expect(!slide.animating(5000));
    try std.testing.expectEqual(@as(f32, 1), slide.progressAt(5000));
}

test "hoverLineSpan grows from the center and reaches the edges" {
    const none = hoverLineSpan(10, 110, 0);
    try std.testing.expectEqual(none.left, none.right);
    try std.testing.expectEqual(@as(i32, 60), none.left);
    const full = hoverLineSpan(10, 110, 1);
    try std.testing.expectEqual(@as(i32, 10), full.left);
    try std.testing.expectEqual(@as(i32, 110), full.right);
    const part = hoverLineSpan(10, 110, 0.25);
    try std.testing.expect(part.left > 10 and part.left < 60);
    try std.testing.expectEqual(120 - part.left, part.right);
}

test "cornerInset curves from the radius toward zero and is zero past the corner" {
    // Row 0 of a 6 px corner sits about 3.6 px in; the last row about 0.
    try std.testing.expectApproxEqAbs(@as(f32, 3.6), cornerInset(6, 0), 0.05);
    try std.testing.expect(cornerInset(6, 5) < 0.05);
    var previous = cornerInset(6, 0);
    for (1..6) |r| {
        const now = cornerInset(6, @intCast(r));
        try std.testing.expect(now < previous);
        previous = now;
    }
    try std.testing.expectEqual(@as(f32, 0), cornerInset(6, 6));
    try std.testing.expectEqual(@as(f32, 0), cornerInset(6, -1));
    try std.testing.expectEqual(@as(f32, 0), cornerInset(0, 0));
}

test "the active tab rounds its top, runs straight, and flares out to the button at the bottom" {
    const button: Rect = .{ .left = 64, .top = 0, .right = 282, .bottom = 39 };
    const s = silhouette(button, 0, 6, 4).?;
    try std.testing.expectEqual(@as(i32, 68), s.body_left);
    try std.testing.expectEqual(@as(i32, 278), s.body_right);
    // The top row is pulled in by the corner, symmetrically.
    const top = s.row(0).?;
    try std.testing.expect(top.left > 70 and top.left < 72);
    try std.testing.expectApproxEqAbs(@as(f32, 282 - 64) - (top.right - 64), top.left - 64, 0.001);
    // The middle is the straight body.
    const middle = s.row(20).?;
    try std.testing.expectEqual(@as(f32, 68), middle.left);
    try std.testing.expectEqual(@as(f32, 278), middle.right);
    // The flare widens toward the bottom and stays inside the button.
    const flare_top = s.row(35).?;
    const last = s.row(38).?;
    try std.testing.expect(flare_top.left <= 68 and flare_top.left > 67);
    try std.testing.expect(last.left < flare_top.left);
    try std.testing.expect(last.left >= 64 and last.right <= 282);
    try std.testing.expect(s.row(39) == null);
    try std.testing.expect(s.row(-1) == null);
}

test "a narrow or short tab shrinks its corners and flares instead of crossing them" {
    // The narrowest tab: a 40 px button keeps a body at least two thirds wide.
    const narrow = silhouette(.{ .left = 0, .top = 0, .right = 40, .bottom = 39 }, 0, 12, 8).?;
    try std.testing.expectEqual(@as(i32, 6), narrow.flare);
    try std.testing.expect(narrow.body_right - narrow.body_left >= 2 * narrow.radius);
    // A short button keeps the corner above the flare.
    const short = silhouette(.{ .left = 0, .top = 0, .right = 200, .bottom = 9 }, 0, 12, 8).?;
    try std.testing.expect(short.radius + short.flare <= 9);
    for (0..9) |y| {
        const r = short.row(@intCast(y)).?;
        try std.testing.expect(r.left >= 0 and r.right <= 200 and r.left < r.right);
    }
    // A restored window starts the shape one row down.
    const restored = silhouette(.{ .left = 0, .top = 0, .right = 200, .bottom = 39 }, 1, 6, 4).?;
    try std.testing.expect(restored.row(0) == null);
    try std.testing.expect(restored.row(1) != null);
    // Nothing to draw.
    try std.testing.expect(silhouette(.{ .left = 0, .top = 0, .right = 2, .bottom = 39 }, 0, 6, 4) == null);
    try std.testing.expect(silhouette(.{ .left = 0, .top = 5, .right = 200, .bottom = 5 }, 5, 6, 4) == null);
}
