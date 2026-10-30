//! Ctrl+Backspace in the app's single-line text fields: the docked search,
//! the palette's query and the Settings fields. A stock EDIT has no word
//! delete; it types U+007F, drawn as a box.

const std = @import("std");
const c = @import("consts.zig");
const sys = @import("sys.zig");

const HWND = sys.HWND;
const EM_REPLACESEL: sys.UINT = 0x00C2;

/// The character Ctrl+Backspace translates to. A proc that took the key
/// down after `TranslateMessage` swallows it.
pub const delete_word_char: usize = 0x7F;

/// Ctrl+Backspace, without Alt (which AltGr also holds).
pub fn isDeleteWordKey(vk: usize, ctrl: bool, alt: bool) bool {
    return vk == c.VK_BACK and ctrl and !alt;
}

/// Where Ctrl+Backspace at `caret` deletes back to: the spaces before the
/// caret, then a run of word characters, or else a run of punctuation.
pub fn previousWordStart(text: []const u16, caret: usize) usize {
    var i = @min(caret, text.len);
    while (i > 0 and isSpace(text[i - 1])) i -= 1;
    if (i == 0) return 0;
    const word = isWord(text[i - 1]);
    while (i > 0 and !isSpace(text[i - 1]) and isWord(text[i - 1]) == word) i -= 1;
    return i;
}

fn isSpace(unit: u16) bool {
    return unit == ' ' or unit == '\t';
}

/// Letters, digits and `_`; anything past ASCII counts as a letter, so a
/// non-Latin word goes in one press.
fn isWord(unit: u16) bool {
    if (unit >= 0x80) return true;
    const byte: u8 = @intCast(unit);
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// Delete the selection, or else the word before the caret, as one
/// replacement the field's own undo takes back. False when the text is too
/// long to read here; the key then goes to the field as before.
pub fn deletePreviousWord(hwnd: HWND) bool {
    var start: u32 = 0;
    var end: u32 = 0;
    _ = sys.SendMessageW(hwnd, c.EM_GETSEL, @intFromPtr(&start), @bitCast(@intFromPtr(&end)));
    if (start == end) {
        var buf: [2048]u16 = undefined;
        if (sys.GetWindowTextLengthW(hwnd) >= buf.len) return false;
        const len = sys.GetWindowTextW(hwnd, &buf, buf.len);
        const text = buf[0..@intCast(@max(0, len))];
        start = @intCast(previousWordStart(text, end));
        if (start == end) return true;
        _ = sys.SendMessageW(hwnd, c.EM_SETSEL, start, @intCast(end));
    }
    const empty = [_:0]u16{};
    _ = sys.SendMessageW(hwnd, EM_REPLACESEL, 1, @bitCast(@intFromPtr(&empty)));
    return true;
}

test "Ctrl+Backspace deletes back to the start of the word, then over the spaces before it" {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    try std.testing.expectEqual(@as(usize, 4), previousWordStart(L("git status"), 10));
    try std.testing.expectEqual(@as(usize, 0), previousWordStart(L("git  "), 5));
    try std.testing.expectEqual(@as(usize, 0), previousWordStart(L(""), 0));
    // Punctuation is its own run, so a regex loses one piece at a time.
    try std.testing.expectEqual(@as(usize, 3), previousWordStart(L("foo.*"), 5));
    try std.testing.expectEqual(@as(usize, 0), previousWordStart(L("foo.*"), 3));
    try std.testing.expectEqual(@as(usize, 0), previousWordStart(L("snake_case"), 10));
    // A non-Latin word goes in one press.
    try std.testing.expectEqual(@as(usize, 4), previousWordStart(L("abc \u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"), 9));
    // A caret mid-word deletes only what is before it.
    try std.testing.expectEqual(@as(usize, 4), previousWordStart(L("git status"), 7));
    try std.testing.expect(isDeleteWordKey(c.VK_BACK, true, false));
    try std.testing.expect(!isDeleteWordKey(c.VK_BACK, true, true));
    try std.testing.expect(!isDeleteWordKey(c.VK_BACK, false, false));
}

test "Ctrl+Backspace in an EDIT deletes the word as one undoable change" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const edit = sys.CreateWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("EDIT"),
        std.unicode.utf8ToUtf16LeStringLiteral("find this word"),
        0,
        0,
        0,
        200,
        20,
        null,
        null,
        null,
        null,
    ) orelse return error.SkipZigTest;
    defer _ = sys.DestroyWindow(edit);
    _ = sys.SendMessageW(edit, c.EM_SETSEL, 14, 14);
    try std.testing.expect(deletePreviousWord(edit));
    var buf: [64]u16 = undefined;
    const len = sys.GetWindowTextW(edit, &buf, buf.len);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("find this "), buf[0..@intCast(len)]);
}
