//! The small label a pane floats over itself: its grid size while it resizes
//! (`resize-overlay`) and the URL under the pointer (`link-previews`).
//!
//! Pure: what the label says, when the resize label shows and where the label
//! sits in its pane. `Host` owns the one popup per window that shows it
//! (`Host.showPaneLabel`), a top-level window like the tab tooltip, since a
//! child over the terminal is painted away by the pane's next frame.
const std = @import("std");
const configpkg = @import("../../config.zig");

pub const Kind = enum {
    /// "120 × 30" after the pane's grid changed; hides after
    /// `resize-overlay-duration`.
    resize,
    /// The hovered link's URL; hides when the hover ends.
    link,
};

pub const Rect = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,

    pub fn width(self: Rect) i32 {
        return self.right - self.left;
    }

    pub fn height(self: Rect) i32 {
        return self.bottom - self.top;
    }
};

pub const Size = struct { width: i32, height: i32 };

pub const Grid = struct {
    columns: u32,
    rows: u32,

    pub fn eql(a: Grid, b: Grid) bool {
        return a.columns == b.columns and a.rows == b.rows;
    }
};

/// Whether a grid change shows the resize label. `first_done` is whether the
/// pane already had a grid before this change: `after-first` (the default)
/// keeps a new pane's first layout quiet, as upstream does.
pub fn resizeShows(mode: configpkg.Config.ResizeOverlay, first_done: bool, before: Grid, after: Grid) bool {
    if (before.eql(after)) return false;
    return switch (mode) {
        .never => false,
        .always => true,
        .@"after-first" => first_done,
    };
}

/// `resize-overlay-duration` as a `SetTimer` delay. Zero shows nothing.
pub fn durationMs(ns: u64) u31 {
    return @intCast(@min(ns / std.time.ns_per_ms, std.math.maxInt(u31)));
}

/// "120 × 30": columns, then rows, as upstream's overlay writes them.
pub fn resizeText(buf: []u8, grid: Grid) []const u8 {
    return std.fmt.bufPrint(buf, "{d} \u{00D7} {d}", .{ grid.columns, grid.rows }) catch buf[0..0];
}

/// A codepoint a link's text must not carry: C0 and C1 controls, and the
/// invisible and direction-changing marks (ALM, zero-width marks, bidi
/// embeddings, overrides and isolates, line and paragraph separators, word
/// joiner, BOM) that can make a link read as something it is not. The opener
/// refuses such text (`App.isSafeLinkText`); the preview shows each as U+FFFD,
/// since hiding the link would hide exactly the spoof the reader needs to see.
pub fn isUnsafeLinkCodepoint(cp: u21) bool {
    return switch (cp) {
        0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x2028...0x2029, 0x2060, 0xFEFF => true,
        else => false,
    };
}

/// Most codepoints a link preview shows; a longer URL ends in "…".
pub const link_max_codepoints: usize = 200;

/// Room `linkText` needs: each shown codepoint as up to 4 UTF-8 bytes, and
/// the ellipsis.
pub const link_buf_len: usize = link_max_codepoints * 4 + 3;

/// The URL as the preview shows it: unsafe codepoints and invalid bytes as
/// U+FFFD, cut at `link_max_codepoints` with "…". Empty for an empty URL.
pub fn linkText(buf: *[link_buf_len]u8, url: []const u8) []const u8 {
    var len: usize = 0;
    var shown: usize = 0;
    var i: usize = 0;
    while (i < url.len) {
        if (shown == link_max_codepoints) {
            len += (std.unicode.utf8Encode(0x2026, buf[len..]) catch unreachable);
            break;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(url[i]) catch 0;
        var cp: u21 = 0xFFFD;
        var step: usize = 1;
        if (seq_len != 0 and i + seq_len <= url.len) {
            if (std.unicode.utf8Decode(url[i .. i + seq_len])) |decoded| {
                cp = if (isUnsafeLinkCodepoint(decoded)) 0xFFFD else decoded;
                step = seq_len;
            } else |_| {}
        }
        len += (std.unicode.utf8Encode(cp, buf[len..]) catch unreachable);
        shown += 1;
        i += step;
    }
    return buf[0..len];
}

/// Where the label of `size` sits in `pane` (screen pixels), `margin` in from
/// its edges. A resize label takes `resize-overlay-position`; a link preview
/// sits bottom left, where upstream's does. A pane smaller than the label
/// keeps the label's top-left corner inside the pane.
pub fn place(kind: Kind, position: configpkg.Config.ResizeOverlayPosition, pane: Rect, size: Size, margin: i32) Rect {
    const where: configpkg.Config.ResizeOverlayPosition = switch (kind) {
        .resize => position,
        .link => .@"bottom-left",
    };
    const left_x = pane.left + margin;
    const right_x = pane.right - margin - size.width;
    const center_x = pane.left + @divTrunc(pane.width() - size.width, 2);
    const top_y = pane.top + margin;
    const bottom_y = pane.bottom - margin - size.height;
    const center_y = pane.top + @divTrunc(pane.height() - size.height, 2);
    const x = switch (where) {
        .@"top-left", .@"bottom-left" => left_x,
        .center, .@"top-center", .@"bottom-center" => center_x,
        .@"top-right", .@"bottom-right" => right_x,
    };
    const y = switch (where) {
        .@"top-left", .@"top-center", .@"top-right" => top_y,
        .center => center_y,
        .@"bottom-left", .@"bottom-center", .@"bottom-right" => bottom_y,
    };
    const cx = @max(x, pane.left);
    const cy = @max(y, pane.top);
    return .{ .left = cx, .top = cy, .right = cx + size.width, .bottom = cy + size.height };
}

test "resize label shows on a grid change the mode allows" {
    const a: Grid = .{ .columns = 80, .rows = 24 };
    const b: Grid = .{ .columns = 120, .rows = 30 };
    try std.testing.expect(!resizeShows(.@"after-first", false, a, b));
    try std.testing.expect(resizeShows(.@"after-first", true, a, b));
    try std.testing.expect(resizeShows(.always, false, a, b));
    try std.testing.expect(!resizeShows(.never, true, a, b));
    // A pixel-only change keeps the grid: nothing to say.
    try std.testing.expect(!resizeShows(.always, true, a, a));
    try std.testing.expect(resizeShows(.always, true, a, .{ .columns = 80, .rows = 25 }));
}

test "resize text and duration" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("120 \u{00D7} 30", resizeText(&buf, .{ .columns = 120, .rows = 30 }));
    try std.testing.expectEqual(@as(u31, 750), durationMs(750 * std.time.ns_per_ms));
    try std.testing.expectEqual(@as(u31, 0), durationMs(999_999));
    try std.testing.expectEqual(@as(u31, std.math.maxInt(u31)), durationMs(std.math.maxInt(u64)));
}

test "link text shows spoofing marks and bad bytes as U+FFFD and cuts long URLs" {
    var buf: [link_buf_len]u8 = undefined;
    try std.testing.expectEqualStrings("", linkText(&buf, ""));
    try std.testing.expectEqualStrings("https://example.com/a", linkText(&buf, "https://example.com/a"));
    try std.testing.expectEqualStrings("https://\u{FFFD}moc.evil", linkText(&buf, "https://\u{202E}moc.evil"));
    try std.testing.expectEqualStrings("a\u{FFFD}b\u{FFFD}c", linkText(&buf, "a\x1bb\xffc"));
    try std.testing.expectEqualStrings("caf\u{00E9}", linkText(&buf, "caf\u{00E9}"));
    // A truncated multi-byte sequence at the end is one bad byte per byte.
    try std.testing.expectEqualStrings("x\u{FFFD}", linkText(&buf, "x\xe2"));

    const long = "a" ** (link_max_codepoints + 5);
    const shown = linkText(&buf, long);
    try std.testing.expect(std.mem.endsWith(u8, shown, "\u{2026}"));
    try std.testing.expectEqual(link_max_codepoints + 3, shown.len);
    // A cut never splits a codepoint: the widest input still fits the buffer.
    const wide = "\u{1F600}" ** (link_max_codepoints + 1);
    const wide_shown = linkText(&buf, wide);
    try std.testing.expect(std.unicode.utf8ValidateSlice(wide_shown));
    try std.testing.expectEqual(link_max_codepoints * 4 + 3, wide_shown.len);
}

test "the preview and the opener agree on unsafe codepoints" {
    try std.testing.expect(isUnsafeLinkCodepoint(0x202E));
    try std.testing.expect(isUnsafeLinkCodepoint(0x9F));
    try std.testing.expect(isUnsafeLinkCodepoint(0xFEFF));
    try std.testing.expect(!isUnsafeLinkCodepoint('a'));
    try std.testing.expect(!isUnsafeLinkCodepoint(0x00E9));
}

test "label placement for each position, clamped into a small pane" {
    const pane: Rect = .{ .left = 100, .top = 50, .right = 900, .bottom = 650 };
    const size: Size = .{ .width = 80, .height = 20 };
    const Case = struct { pos: configpkg.Config.ResizeOverlayPosition, left: i32, top: i32 };
    const cases = [_]Case{
        .{ .pos = .center, .left = 460, .top = 340 },
        .{ .pos = .@"top-left", .left = 108, .top = 58 },
        .{ .pos = .@"top-center", .left = 460, .top = 58 },
        .{ .pos = .@"top-right", .left = 812, .top = 58 },
        .{ .pos = .@"bottom-left", .left = 108, .top = 622 },
        .{ .pos = .@"bottom-center", .left = 460, .top = 622 },
        .{ .pos = .@"bottom-right", .left = 812, .top = 622 },
    };
    for (cases) |case| {
        const r = place(.resize, case.pos, pane, size, 8);
        try std.testing.expectEqual(case.left, r.left);
        try std.testing.expectEqual(case.top, r.top);
        try std.testing.expectEqual(size.width, r.width());
        try std.testing.expectEqual(size.height, r.height());
    }
    // A link preview ignores the resize position.
    const link = place(.link, .@"top-right", pane, size, 8);
    try std.testing.expectEqual(@as(i32, 108), link.left);
    try std.testing.expectEqual(@as(i32, 622), link.top);
    // A pane narrower than the label keeps the label's corner inside it.
    const tiny = place(.resize, .@"bottom-right", .{ .left = 10, .top = 10, .right = 40, .bottom = 20 }, size, 8);
    try std.testing.expectEqual(@as(i32, 10), tiny.left);
    try std.testing.expectEqual(@as(i32, 10), tiny.top);
}
