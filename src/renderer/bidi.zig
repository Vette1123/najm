//! Right-to-left display order for one terminal row.
//!
//! The terminal stores a row in logical order, the order a program wrote it,
//! and everything that reads text (copy, search, links, mouse selection)
//! keeps working on that order. Only what is drawn moves: `Layout` says which
//! logical cell each column shows. The renderer and the mouse both go through
//! it, so what is drawn and what a click hits cannot disagree.
//!
//! The bidirectional algorithm is Windows' own, Uniscribe's `ScriptItemize`.
//! usp10.dll loads on the first row that has right-to-left text, so a session
//! without any never pays for it (see the 2026-10-17 OpenGL32 entry in
//! docs/agents/log/renderer.md for what a static import costs a CLI action).

const std = @import("std");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;
const Cell = @import("../terminal/main.zig").page.Cell;

pub const Direction = enum { ltr, rtl };

/// A cell the bidi algorithm can make right-to-left: the Hebrew, Arabic,
/// Syriac, Thaana, NKo, Samaritan and Mandaic blocks, their presentation
/// forms, and the supplementary right-to-left blocks. A row with none of
/// these keeps logical order and skips everything below.
pub fn isRtl(cp: u21) bool {
    return switch (cp) {
        0x0590...0x08FF,
        0xFB1D...0xFDFF,
        0xFE70...0xFEFF,
        0x10800...0x10FFF,
        0x1E800...0x1EFFF,
        => true,
        else => false,
    };
}

pub fn hasRtl(cells: []const Cell) bool {
    for (cells) |*cell| {
        if (isRtl(cell.codepoint())) return true;
    }
    return false;
}

/// The paragraph direction of the row that starts a line.
///
/// Right-to-left only when the first thing on the line is right-to-left text,
/// so plain Arabic output reads from the right edge, while a shell prompt, a
/// bullet or a box border holds its place on the left with the Arabic after
/// it reordered in place. The alternate screen is always left-to-right: a
/// full-screen program has placed every cell itself, and mirroring its
/// columns would scramble them.
pub fn direction(head: []const Cell, alternate_screen: bool) Direction {
    if (alternate_screen) return .ltr;
    for (head) |*cell| {
        const cp = cell.codepoint();
        if (cp == 0 or cp == ' ') continue;
        return if (isRtl(cp)) .rtl else .ltr;
    }
    return .ltr;
}

/// The columns of one row. All three lists are `cells.len` long after an
/// `update` that returned true.
pub const Layout = struct {
    /// The logical cell each column shows.
    visual_to_logical: std.ArrayListUnmanaged(u16) = .empty,
    /// The column each logical cell is shown in.
    logical_to_visual: std.ArrayListUnmanaged(u16) = .empty,
    /// Whether each column holds right-to-left text.
    rtl: std.ArrayListUnmanaged(bool) = .empty,

    text: std.ArrayListUnmanaged(u16) = .empty,
    text_unit: std.ArrayListUnmanaged(u16) = .empty,
    units: std.ArrayListUnmanaged(Unit) = .empty,
    levels: std.ArrayListUnmanaged(u8) = .empty,
    order: std.ArrayListUnmanaged(u16) = .empty,
    items: std.ArrayListUnmanaged(ScriptItem) = .empty,

    /// What moves: one cell, or a wide cell with its tail, which never split.
    const Unit = struct { cell: u16, width: u16 };

    pub fn deinit(self: *Layout, alloc: Allocator) void {
        self.visual_to_logical.deinit(alloc);
        self.logical_to_visual.deinit(alloc);
        self.rtl.deinit(alloc);
        self.text.deinit(alloc);
        self.text_unit.deinit(alloc);
        self.units.deinit(alloc);
        self.levels.deinit(alloc);
        self.order.deinit(alloc);
        self.items.deinit(alloc);
    }

    /// Lay out `cells`. False leaves the row in logical order: it has no
    /// right-to-left text, or Uniscribe is missing or refused it.
    pub fn update(
        self: *Layout,
        alloc: Allocator,
        cells: []const Cell,
        paragraph: Direction,
    ) Allocator.Error!bool {
        if (!hasRtl(cells)) return false;
        const itemize = scriptItemize() orelse return false;

        // A left-to-right line lays out what it holds, and the blank cells
        // past it stay put. A right-to-left one lays out the whole row, so
        // those blanks fall on the left and the text sits at the right edge.
        const end: usize = switch (paragraph) {
            .rtl => cells.len,
            .ltr => end: {
                var last = cells.len;
                while (last > 0 and cells[last - 1].isEmpty()) last -= 1;
                break :end last;
            },
        };

        self.units.clearRetainingCapacity();
        self.text.clearRetainingCapacity();
        self.text_unit.clearRetainingCapacity();
        for (cells[0..end], 0..) |*cell, i| {
            if (cell.wide == .spacer_tail) continue;
            const unit: u16 = @intCast(self.units.items.len);
            const wide = cell.wide == .wide and i + 1 < end;
            try self.units.append(alloc, .{ .cell = @intCast(i), .width = if (wide) 2 else 1 });

            // Only the base codepoint: combining marks follow their base.
            const cp: u21 = switch (cell.codepoint()) {
                0 => ' ',
                else => |v| v,
            };
            var utf16: [2]u16 = undefined;
            const utf16_len: usize = if (cp < 0x10000) one: {
                utf16[0] = @intCast(cp);
                break :one 1;
            } else two: {
                const v: u32 = cp - 0x10000;
                utf16[0] = @intCast(0xD800 + (v >> 10));
                utf16[1] = @intCast(0xDC00 + (v & 0x3FF));
                break :two 2;
            };
            try self.text.appendSlice(alloc, utf16[0..utf16_len]);
            try self.text_unit.appendNTimes(alloc, unit, utf16_len);
        }
        if (self.text.items.len == 0) return false;

        // ScriptItemize writes a closing item past the count it reports.
        const max_items = self.text.items.len + 2;
        try self.items.resize(alloc, max_items + 1);
        const control: ScriptControl = .{};
        const state: ScriptState = .{ .bidi_level = if (paragraph == .rtl) 1 else 0 };
        var count: c_int = 0;
        const hr = itemize(
            self.text.items.ptr,
            @intCast(self.text.items.len),
            @intCast(max_items),
            &control,
            &state,
            self.items.items.ptr,
            &count,
        );
        if (hr < 0 or count <= 0) return false;

        try self.levels.resize(alloc, self.units.items.len);
        for (self.items.items[0..@intCast(count)], 1..) |item, next| {
            const level = item.analysis.state.bidi_level;
            const stop: usize = @intCast(self.items.items[next].char_pos);
            for (self.text_unit.items[@intCast(item.char_pos)..stop]) |unit| {
                self.levels.items[unit] = level;
            }
        }

        try self.order.resize(alloc, self.units.items.len);
        reorder(self.levels.items, self.order.items);

        try self.visual_to_logical.resize(alloc, cells.len);
        try self.logical_to_visual.resize(alloc, cells.len);
        try self.rtl.resize(alloc, cells.len);
        for (self.visual_to_logical.items, self.logical_to_visual.items, 0..) |*logical, *visual, x| {
            logical.* = @intCast(x);
            visual.* = @intCast(x);
        }
        @memset(self.rtl.items, false);

        var x: usize = 0;
        for (self.order.items) |unit_index| {
            const unit = self.units.items[unit_index];
            for (0..unit.width) |offset| {
                self.visual_to_logical.items[x] = unit.cell + @as(u16, @intCast(offset));
                self.rtl.items[x] = self.levels.items[unit_index] % 2 == 1;
                x += 1;
            }
        }
        for (self.visual_to_logical.items, 0..) |logical, visual| {
            self.logical_to_visual.items[logical] = @intCast(visual);
        }
        return true;
    }
};

/// Rule L2 of UAX #9: from the highest level down to the lowest odd one,
/// reverse every run at that level or above.
fn reorder(levels: []const u8, order: []u16) void {
    for (order, 0..) |*index, i| index.* = @intCast(i);
    var highest: u8 = 0;
    var lowest_odd: u8 = std.math.maxInt(u8);
    for (levels) |level| {
        highest = @max(highest, level);
        if (level % 2 == 1) lowest_odd = @min(lowest_odd, level);
    }
    if (lowest_odd == std.math.maxInt(u8)) return;

    var level = highest;
    while (level >= lowest_odd) : (level -= 1) {
        var i: usize = 0;
        while (i < order.len) {
            if (levels[order[i]] < level) {
                i += 1;
                continue;
            }
            var stop = i;
            while (stop < order.len and levels[order[stop]] >= level) stop += 1;
            std.mem.reverse(u16, order[i..stop]);
            i = stop;
        }
    }
}

// Mirrors of usp10.h. `SCRIPT_CONTROL` is one DWORD of bit fields and
// `SCRIPT_ANALYSIS` two WORDs; only `uBidiLevel`, the low five bits of
// `SCRIPT_STATE`, is used. The sizes are pinned in a test.
const ScriptControl = extern struct { bits: u32 = 0 };
const ScriptState = packed struct(u16) { bidi_level: u5 = 0, reserved: u11 = 0 };
const ScriptAnalysis = extern struct { flags: u16 = 0, state: ScriptState = .{} };
const ScriptItem = extern struct { char_pos: i32 = 0, analysis: ScriptAnalysis = .{} };

const ScriptItemizeFn = *const fn (
    text: [*]const u16,
    text_len: c_int,
    max_items: c_int,
    control: *const ScriptControl,
    state: *const ScriptState,
    items: [*]ScriptItem,
    count: *c_int,
) callconv(.winapi) windows.HRESULT;

var script_itemize: ?ScriptItemizeFn = null;
var script_itemize_once = std.once(loadScriptItemize);

fn scriptItemize() ?ScriptItemizeFn {
    script_itemize_once.call();
    return script_itemize;
}

/// From System32 only, and kept until the process exits.
fn loadScriptItemize() void {
    const module = windows.kernel32.LoadLibraryExW(
        std.unicode.utf8ToUtf16LeStringLiteral("usp10.dll"),
        null,
        0x00000800, // LOAD_LIBRARY_SEARCH_SYSTEM32
    ) orelse return;
    const proc = windows.kernel32.GetProcAddress(module, "ScriptItemize") orelse return;
    script_itemize = @ptrCast(@alignCast(proc));
}

const testing = std.testing;

/// `text` as a row of `cols` cells; a blank past the text is an empty cell.
fn testRow(cols: usize, text: []const u8) ![]Cell {
    const cells = try testing.allocator.alloc(Cell, cols);
    @memset(cells, .init(0));
    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var i: usize = 0;
    while (it.nextCodepoint()) |cp| : (i += 1) cells[i] = .init(cp);
    return cells;
}

/// What each column shows, one character per column, blanks as spaces.
fn expectShown(layout: *const Layout, cells: []const Cell, expected: []const u8) !void {
    var view = try std.unicode.Utf8View.init(expected);
    var it = view.iterator();
    for (layout.visual_to_logical.items) |logical| {
        const want = it.nextCodepoint() orelse ' ';
        const got = cells[logical].codepoint();
        try testing.expectEqual(want, if (got == 0) ' ' else got);
    }
    try testing.expect(it.nextCodepoint() == null);
}

fn expectLayout(
    cols: usize,
    text: []const u8,
    paragraph: Direction,
    expected: []const u8,
) !void {
    const cells = try testRow(cols, text);
    defer testing.allocator.free(cells);
    var layout: Layout = .{};
    defer layout.deinit(testing.allocator);
    try testing.expect(try layout.update(testing.allocator, cells, paragraph));
    try expectShown(&layout, cells, expected);
    // The two maps are inverses, which is what a click relies on.
    for (layout.visual_to_logical.items, 0..) |logical, visual| {
        try testing.expectEqual(visual, layout.logical_to_visual.items[logical]);
    }
}

test "usp10 mirrors have the SDK's sizes" {
    try testing.expectEqual(@as(usize, 4), @sizeOf(ScriptControl));
    try testing.expectEqual(@as(usize, 2), @sizeOf(ScriptState));
    try testing.expectEqual(@as(usize, 4), @sizeOf(ScriptAnalysis));
    try testing.expectEqual(@as(usize, 8), @sizeOf(ScriptItem));
}

test "bidi leaves a row with no right-to-left text alone" {
    const cells = try testRow(8, "hello");
    defer testing.allocator.free(cells);
    var layout: Layout = .{};
    defer layout.deinit(testing.allocator);
    try testing.expect(!try layout.update(testing.allocator, cells, .ltr));
}

test "bidi paragraph direction comes from the first thing on the line" {
    const cases = [_]struct { text: []const u8, alternate: bool, expected: Direction }{
        .{ .text = "\u{0633}\u{0644}\u{0627}\u{0645}", .alternate = false, .expected = .rtl },
        .{ .text = "  \u{0633}\u{0644}", .alternate = false, .expected = .rtl },
        .{ .text = "\u{0633}\u{0644}", .alternate = true, .expected = .ltr },
        .{ .text = "C:\\> \u{0633}\u{0644}", .alternate = false, .expected = .ltr },
        .{ .text = "\u{2502} \u{0633}\u{0644}", .alternate = false, .expected = .ltr },
        .{ .text = "- \u{0633}\u{0644}", .alternate = false, .expected = .ltr },
        .{ .text = "", .alternate = false, .expected = .ltr },
    };
    for (cases) |case| {
        const cells = try testRow(12, case.text);
        defer testing.allocator.free(cells);
        try testing.expectEqual(case.expected, direction(cells, case.alternate));
    }
}

test "bidi reverses Arabic and sets it against the right edge of its line" {
    try expectLayout(
        6,
        "\u{0633}\u{0644}\u{0627}\u{0645}",
        .rtl,
        "  \u{0645}\u{0627}\u{0644}\u{0633}",
    );
}

test "bidi keeps a prompt in place and reverses the Arabic after it" {
    try expectLayout(
        9,
        "ab> \u{0633}\u{0644}\u{0645}",
        .ltr,
        "ab> \u{0645}\u{0644}\u{0633}",
    );
}

test "bidi keeps Latin and numbers reading forwards inside Arabic" {
    try expectLayout(
        12,
        "\u{0633}\u{0644} abc 123 \u{0645}",
        .rtl,
        "\u{0645} abc 123 \u{0644}\u{0633}",
    );
}

test "bidi puts closing punctuation on the left of a right-to-left line" {
    try expectLayout(5, "\u{0633}\u{0644}?", .rtl, "  ?\u{0644}\u{0633}");
}

test "bidi keeps a box border in place" {
    try expectLayout(
        6,
        "\u{2502} \u{0633}\u{0644} \u{2502}",
        .ltr,
        "\u{2502} \u{0644}\u{0633} \u{2502}",
    );
}

test "bidi moves a wide cell with its tail" {
    // An ideograph, wide with its tail, between Arabic on a right-to-left line.
    var cells = [_]Cell{
        .init(0x0633),
        .init(' '),
        .init(0x4E00),
        .init(0),
        .init(' '),
        .init(0x0644),
    };
    cells[2].wide = .wide;
    cells[3].wide = .spacer_tail;
    var layout: Layout = .{};
    defer layout.deinit(testing.allocator);
    try testing.expect(try layout.update(testing.allocator, &cells, .rtl));
    const visual = layout.logical_to_visual.items;
    try testing.expectEqual(visual[2] + 1, visual[3]);
    try testing.expectEqual(@as(u16, 5), visual[0]);
    try testing.expectEqual(@as(u16, 0), visual[5]);
}

test "bidi reorder follows rule L2 across nested levels" {
    // Level 2 numbers inside level 1 Arabic, inside a level 0 line.
    const levels = [_]u8{ 0, 1, 1, 2, 2, 1, 0 };
    var order: [levels.len]u16 = undefined;
    reorder(&levels, &order);
    try testing.expectEqualSlices(u16, &.{ 0, 5, 3, 4, 2, 1, 6 }, &order);
}
