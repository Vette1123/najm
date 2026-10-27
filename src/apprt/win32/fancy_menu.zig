//! Najm's popup menus. Every `TrackPopupMenu` the app opens goes through
//! `track`, which keeps a real Win32 menu underneath (keyboard, submenus,
//! dismissal, the system open animation and screen readers all stay native)
//! and draws each row itself: an elevated card in the app's theme with
//! rounded corners, an accent edge along the top, a rounded highlight,
//! Fluent icons, and shortcuts as keycaps.
//!
//! The owner window forwards `WM_MEASUREITEM`, `WM_DRAWITEM` and
//! `WM_MENUCHAR` to `measureItem`, `drawItem` and `menuChar`; each returns
//! null for anything that is not one of these menus. High Contrast gets the
//! plain system menu, which already uses the system colours.

const std = @import("std");

const c = @import("consts.zig");
const gdi = @import("gdi.zig");
const sys = @import("sys.zig");
const win32_theme = @import("../win32_theme.zig");
const win32_types = @import("../win32_types.zig");

const BOOL = win32_types.BOOL;
const DWORD = win32_types.DWORD;
const HDC = win32_types.HDC;
const HMENU = win32_types.HMENU;
const HWND = win32_types.HWND;
const LPARAM = win32_types.LPARAM;
const LRESULT = win32_types.LRESULT;
const RECT = sys.RECT;
const UINT = win32_types.UINT;
const WPARAM = win32_types.WPARAM;

/// Segoe Fluent Icons / Segoe MDL2 Assets code points. Both faces carry
/// every glyph here; a machine with neither draws no icons.
pub const Icon = enum(u16) {
    copy = 0xE8C8,
    paste = 0xE77F,
    select_all = 0xE8B3,
    find = 0xE721,
    command = 0xE765,
    add = 0xE710,
    split = 0xE8A9,
    right = 0xE72A,
    down = 0xE74B,
    left = 0xE72B,
    up = 0xE74A,
    window = 0xE78B,
    rename = 0xE8AC,
    close = 0xE711,
    close_others = 0xE8E6,
    inspector = 0xE9D9,
    reset = 0xE72C,
    shell = 0xE756,
};
const glyph_check: u16 = 0xE73E;
const glyph_chevron: u16 = 0xE76C;

pub const Item = struct {
    id: usize = 0,
    label: []const u8 = "",
    /// "Ctrl+Shift+C"; drawn as one keycap per key.
    shortcut: ?[]const u8 = null,
    icon: ?Icon = null,
    enabled: bool = true,
    checked: bool = false,
    destructive: bool = false,
    separator: bool = false,
    submenu: ?[]const Item = null,

    pub fn sep() Item {
        return .{ .separator = true };
    }
};

pub const Style = struct {
    bg: u32,
    border: u32,
    text: u32,
    text_secondary: u32,
    text_disabled: u32,
    accent: u32,
    error_fg: u32,
    is_dark: bool,
    dpi: u32,
    high_contrast: bool,
};

/// A terminal window's menus: the palette's elevated surface.
pub fn styleFromTheme(theme: *const win32_theme.ThemeColors, dpi: u32, high_contrast: bool) Style {
    return .{
        .bg = theme.overlay_bg,
        .border = theme.overlay_border,
        .text = theme.text_primary,
        .text_secondary = theme.text_secondary,
        .text_disabled = theme.text_disabled,
        .accent = theme.accent,
        .error_fg = theme.error_fg,
        .is_dark = theme.is_dark,
        .dpi = dpi,
        .high_contrast = high_contrast,
    };
}

/// Settings' menus: its own pane colours.
pub fn styleFromSettings(colors: *const win32_theme.SettingsColors, dpi: u32) Style {
    return .{
        .bg = colors.window_bg,
        .border = colors.field_border,
        .text = colors.text,
        .text_secondary = colors.secondary_text,
        .text_disabled = colors.disabled_text,
        .accent = colors.accent,
        .error_fg = colors.error_text,
        .is_dark = colors.is_dark,
        .dpi = dpi,
        .high_contrast = colors.high_contrast,
    };
}

pub const Origin = enum { pointer, keyboard };

/// Opens the menu at the screen point and returns the chosen id, or 0 when
/// it was dismissed, exactly like `TrackPopupMenu(TPM_RETURNCMD)`.
pub fn track(
    alloc: std.mem.Allocator,
    owner: HWND,
    items: []const Item,
    x: i32,
    y: i32,
    style: Style,
    origin: Origin,
) BOOL {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    var session: Session = .{ .arena = arena_state.allocator(), .style = style, .owner = owner };
    defer session.deinit();

    const menu = session.build(items, !style.high_contrast) catch return 0;
    defer _ = sys.DestroyMenu(menu);
    if (!style.high_contrast) session.prepare(menu);

    const previous = active;
    active = &session;
    defer active = previous;

    const hook = if (style.high_contrast) null else SetWindowsHookExW(WH_CALLWNDPROC, menuWindowHook, null, sys.GetCurrentThreadId());
    defer if (hook) |h| {
        _ = UnhookWindowsHookEx(h);
    };

    // The system animation (fade, or slide where it is on) honours the
    // user's own motion setting. A keyboard opening shows at once: it is
    // repeated too often to wait on.
    const motion: UINT = switch (origin) {
        .pointer => TPM_VERPOSANIMATION,
        .keyboard => TPM_NOANIMATION,
    };
    return sys.TrackPopupMenu(menu, c.TPM_RETURNCMD | c.TPM_RIGHTBUTTON | c.TPM_LEFTALIGN | c.TPM_TOPALIGN | motion, x, y, 0, owner, null);
}

/// `WM_MEASUREITEM` from the owner. Null when it is not ours.
pub fn measureItem(lParam: LPARAM) ?LRESULT {
    const session = active orelse return null;
    const mis: *MEASUREITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
    if (mis.CtlType != ODT_MENU) return null;
    const entry = session.entryOf(mis.itemData) orelse return null;
    const size = session.measure(entry);
    mis.itemWidth = size.width;
    mis.itemHeight = size.height;
    return 1;
}

/// `WM_DRAWITEM` from the owner. Null when it is not ours.
pub fn drawItem(lParam: LPARAM) ?LRESULT {
    const session = active orelse return null;
    const dis: *const sys.DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
    if (dis.CtlType != ODT_MENU) return null;
    const entry = session.entryOf(dis.itemData) orelse return null;
    session.draw(entry, dis);
    return 1;
}

/// `WM_MENUCHAR`: owner-drawn items lose their `&` mnemonics unless the
/// owner answers for them. Null when it is not ours.
pub fn menuChar(wParam: WPARAM, lParam: LPARAM) ?LRESULT {
    const session = active orelse return null;
    const menu: HMENU = @ptrFromInt(@as(usize, @bitCast(lParam)));
    const typed: u16 = @truncate(wParam & 0xFFFF);
    var position: usize = 0;
    for (session.entries.items) |entry| {
        if (entry.menu != menu) continue;
        defer position += 1;
        const key = mnemonicOf(entry.item.label) orelse continue;
        if (std.ascii.toLower(key) == std.ascii.toLower(@truncate(typed))) {
            return (MNC_EXECUTE << 16) | @as(LRESULT, @intCast(position));
        }
    }
    return null;
}

/// The letter after the first single `&`, as Win32 menus mark mnemonics.
pub fn mnemonicOf(label: []const u8) ?u8 {
    var i: usize = 0;
    while (i + 1 < label.len) : (i += 1) {
        if (label[i] != '&') continue;
        if (label[i + 1] == '&') {
            i += 1;
            continue;
        }
        return label[i + 1];
    }
    return null;
}

/// Splits "Ctrl+Shift+C" into its keys. A trailing "+" key ("Ctrl++")
/// stays a key. Returns how many of `out` it filled.
pub fn splitShortcut(text: []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len and n < out.len) : (i += 1) {
        if (text[i] != '+' or i == start) continue;
        out[n] = text[start..i];
        n += 1;
        start = i + 1;
    }
    if (start < text.len and n < out.len) {
        out[n] = text[start..];
        n += 1;
    }
    return n;
}

/// Horizontal positions inside one row, in physical pixels.
pub const RowLayout = struct {
    icon_left: i32,
    label_left: i32,
    /// The label is clipped here, a gap before the keycaps or chevron.
    label_right: i32,
    trailing_right: i32,
};

/// Sizes that follow the menu text, which follows Windows' "Text size"
/// setting: a larger font grows the rows, icons and keycaps with it.
pub const Metrics = struct {
    text_px: i32,
    small_px: i32,
    icon_px: i32,
    row: i32,
    cap: i32,
};

/// `menu_font_px` is the system menu font's height at `dpi`; the text never
/// drops below 14 px (at 96 dpi) and grows past it with the user's setting.
pub fn metricsFor(menu_font_px: i32, dpi: u32) Metrics {
    const floor = scale(14, dpi);
    const text: i32 = @max(floor, menu_font_px);
    const small: i32 = @max(scale(12, dpi), @divTrunc(text * 6, 7));
    const icon = @divTrunc(scale(16, dpi) * text, floor);
    return .{
        .text_px = text,
        .small_px = small,
        .icon_px = icon,
        .row = @max(scale(32, dpi), text + scale(18, dpi)),
        .cap = small + scale(8, dpi),
    };
}

pub fn rowLayout(left: i32, right: i32, icon_column: bool, trailing_width: i32, icon: i32, dpi: u32) RowLayout {
    const pad = scale(12, dpi);
    const gap = scale(12, dpi);
    const label_left = if (icon_column) left + pad + icon + gap else left + pad + scale(4, dpi);
    const trailing_right = right - pad;
    const label_right = if (trailing_width > 0) trailing_right - trailing_width - scale(24, dpi) else trailing_right;
    return .{
        .icon_left = left + pad,
        .label_left = label_left,
        .label_right = @max(label_left, label_right),
        .trailing_right = trailing_right,
    };
}

pub fn scale(value: i32, dpi: u32) i32 {
    return @intCast(@divTrunc(@as(i64, value) * dpi + 48, 96));
}

const Entry = extern struct {
    /// First, so screen readers find the label (MSAA reads `itemData`
    /// as an MSAAMENUINFO when it starts with the signature).
    msaa: MSAAMENUINFO,
    index: usize,
};

const EntryInfo = struct {
    item: Item,
    menu: HMENU,
    label_w: [:0]u16,
    icon_column: bool,
    first: bool,
    last: bool,
    data: *Entry,
};

const Session = struct {
    arena: std.mem.Allocator,
    style: Style,
    owner: HWND,
    entries: std.ArrayListUnmanaged(EntryInfo) = .empty,
    brush: ?*anyopaque = null,
    font: ?*anyopaque = null,
    small_font: ?*anyopaque = null,
    icon_font: ?*anyopaque = null,
    metrics: Metrics = metricsFor(0, 96),

    fn deinit(self: *Session) void {
        for ([_]?*anyopaque{ self.brush, self.font, self.small_font, self.icon_font }) |object| {
            if (object) |o| _ = sys.DeleteObject(o);
        }
    }

    fn build(self: *Session, items: []const Item, owner_draw: bool) !*anyopaque {
        const menu = sys.CreatePopupMenu() orelse return error.CreateMenuFailed;
        errdefer _ = sys.DestroyMenu(menu);
        var icon_column = false;
        for (items) |item| {
            if (item.icon != null or item.checked) icon_column = true;
        }
        var visible_last: usize = 0;
        for (items, 0..) |item, i| {
            if (!item.separator) visible_last = i;
        }
        for (items, 0..) |item, i| {
            var flags: UINT = 0;
            var id: usize = item.id;
            if (item.separator) flags |= c.MF_SEPARATOR;
            if (!item.enabled) flags |= c.MF_GRAYED;
            if (item.checked) flags |= c.MF_CHECKED;
            if (item.submenu) |children| {
                flags |= c.MF_POPUP;
                id = @intFromPtr(try self.build(children, owner_draw));
            }
            const label_w = try self.plainLabel(item);
            if (!owner_draw) {
                _ = sys.AppendMenuW(menu, flags, id, if (item.separator) null else label_w.ptr);
                continue;
            }
            const data = try self.arena.create(Entry);
            data.* = .{
                .msaa = .{ .dwMSAASignature = MSAA_MENU_SIG, .cchWText = @intCast(label_w.len), .pszWText = label_w.ptr },
                .index = self.entries.items.len,
            };
            try self.entries.append(self.arena, .{
                .item = item,
                .menu = menu,
                .label_w = try std.unicode.utf8ToUtf16LeAllocZ(self.arena, item.label),
                .icon_column = icon_column,
                .first = i == 0,
                .last = i == visible_last,
                .data = data,
            });
            // An owner-drawn item's "string" is its item data.
            _ = sys.AppendMenuW(menu, flags | MF_OWNERDRAW, id, @ptrFromInt(@intFromPtr(data)));
        }
        return menu;
    }

    /// The label as a plain menu shows it, and as a screen reader reads it:
    /// the shortcut after a tab.
    fn plainLabel(self: *Session, item: Item) ![:0]u16 {
        const text = if (item.shortcut) |s|
            try std.fmt.allocPrint(self.arena, "{s}\t{s}", .{ item.label, s })
        else
            item.label;
        return std.unicode.utf8ToUtf16LeAllocZ(self.arena, text);
    }

    fn prepare(self: *Session, menu: *anyopaque) void {
        const dpi = self.style.dpi;
        self.brush = sys.CreateSolidBrush(self.style.bg);
        var info: MENUINFO = .{ .fMask = MIM_BACKGROUND | MIM_APPLYTOSUBMENUS, .hbrBack = self.brush };
        _ = SetMenuInfo(menu, &info);

        var lf: sys.LOGFONTW = .{};
        var ncm: sys.NONCLIENTMETRICSW = undefined;
        ncm.cbSize = @sizeOf(sys.NONCLIENTMETRICSW);
        // At this window's DPI, with the user's text scaling in it.
        if (SystemParametersInfoForDpi(c.SPI_GETNONCLIENTMETRICS, @sizeOf(sys.NONCLIENTMETRICSW), @ptrCast(&ncm), 0, dpi) != 0) lf = ncm.lfMenuFont;
        self.metrics = metricsFor(@intCast(@abs(lf.lfHeight)), dpi);
        lf.lfQuality = c.CLEARTYPE_QUALITY;
        lf.lfHeight = -self.metrics.text_px;
        lf.lfWeight = c.FW_NORMAL;
        self.font = sys.CreateFontIndirectW(&lf);
        lf.lfHeight = -self.metrics.small_px;
        self.small_font = sys.CreateFontIndirectW(&lf);

        const win32 = @import("../win32.zig");
        var glyphs: [@typeInfo(Icon).@"enum".fields.len + 2]u16 = undefined;
        inline for (@typeInfo(Icon).@"enum".fields, 0..) |field, i| glyphs[i] = field.value;
        glyphs[glyphs.len - 2] = glyph_check;
        glyphs[glyphs.len - 1] = glyph_chevron;
        self.icon_font = win32.createIconFontWithGlyphs(&win32.titlebar_icon_faces, &glyphs, self.metrics.icon_px).font;
    }

    fn entryOf(self: *Session, item_data: usize) ?*const EntryInfo {
        for (self.entries.items) |*entry| {
            if (@intFromPtr(entry.data) == item_data) return entry;
        }
        return null;
    }

    const Size = struct { width: u32, height: u32 };

    fn measure(self: *Session, entry: *const EntryInfo) Size {
        const dpi = self.style.dpi;
        const edge = self.edgePadding(entry);
        if (entry.item.separator) return .{ .width = 0, .height = @intCast(scale(9, dpi) + edge) };

        const hdc = sys.GetDC(self.owner);
        defer _ = sys.ReleaseDC(self.owner, hdc);
        const label_width = self.textWidth(hdc, self.font, entry.label_w);
        const layout = rowLayout(0, 10_000, entry.icon_column, self.trailingWidth(hdc, entry), self.metrics.icon_px, dpi);
        const content = layout.label_left + label_width + (10_000 - layout.label_right);
        // The system adds a check-mark width of its own to every row.
        const system_extra = sys.GetSystemMetricsForDpi(SM_CXMENUCHECK, dpi) - 1;
        const width = @max(scale(220, dpi), content) - system_extra;
        return .{ .width = @intCast(@max(1, width)), .height = @intCast(self.metrics.row + edge) };
    }

    /// Breathing room above the first row (where the accent edge sits) and
    /// below the last.
    fn edgePadding(self: *Session, entry: *const EntryInfo) i32 {
        var extra: i32 = 0;
        if (entry.first) extra += scale(6, self.style.dpi);
        if (entry.last) extra += scale(4, self.style.dpi);
        return extra;
    }

    fn trailingWidth(self: *Session, hdc: HDC, entry: *const EntryInfo) i32 {
        if (entry.item.submenu != null) return self.metrics.icon_px;
        const shortcut = entry.item.shortcut orelse return 0;
        return keycapsWidth(hdc, self.keycaps(false, false), shortcut);
    }

    fn textWidth(_: *Session, hdc: HDC, font: ?*anyopaque, text: []const u16) i32 {
        return textWidthIn(hdc, font, text);
    }

    fn keycaps(self: *Session, selected: bool, disabled: bool) Keycaps {
        const style = self.style;
        return .{
            .base = if (selected and !disabled) highlightColor(style.bg, style.accent, style.is_dark) else style.bg,
            .text = style.text,
            .fg = if (disabled) style.text_disabled else style.text_secondary,
            .is_dark = style.is_dark,
            .dpi = style.dpi,
            .font = self.small_font,
            .height = self.metrics.cap,
        };
    }

    fn draw(self: *Session, entry: *const EntryInfo, dis: *const sys.DRAWITEMSTRUCT) void {
        const hdc = dis.hDC;
        const style = self.style;
        const dpi = style.dpi;
        var rect = dis.rcItem;
        gdi.fillSolidRect(hdc, rect, style.bg);

        if (entry.first) {
            // The accent edge across the top of the card.
            const inset = scale(6, dpi);
            const bar: RECT = .{ .left = rect.left + inset, .top = rect.top + scale(2, dpi), .right = rect.right - inset, .bottom = rect.top + scale(2, dpi) + @max(2, scale(2, dpi)) };
            fillRound(hdc, bar, style.accent, @max(2, scale(2, dpi)));
            rect.top += scale(6, dpi);
        }
        if (entry.last) rect.bottom -= scale(4, dpi);

        if (entry.item.separator) {
            const mid = @divTrunc(rect.top + rect.bottom, 2);
            gdi.fillSolidRect(hdc, .{ .left = rect.left + scale(12, dpi), .top = mid, .right = rect.right - scale(12, dpi), .bottom = mid + @max(1, scale(1, dpi)) }, style.border);
            excludeItem(hdc, dis.rcItem);
            return;
        }

        const disabled = dis.itemState & (ODS_GRAYED | c.ODS_DISABLED) != 0;
        const selected = dis.itemState & c.ODS_SELECTED != 0;
        if (selected) {
            const pill: RECT = .{ .left = rect.left + scale(4, dpi), .top = rect.top + scale(1, dpi), .right = rect.right - scale(4, dpi), .bottom = rect.bottom - scale(1, dpi) };
            const fill = if (disabled)
                gdi.blendColorRGB(style.bg, style.text, 0.06)
            else
                highlightColor(style.bg, style.accent, style.is_dark);
            fillRound(hdc, pill, fill, scale(6, dpi));
        }

        const fg = rowTextColor(style, entry.item.destructive, disabled);
        const quiet = if (disabled) style.text_disabled else style.text_secondary;
        const layout = rowLayout(rect.left, rect.right, entry.icon_column, self.trailingWidth(hdc, entry), self.metrics.icon_px, dpi);
        _ = sys.SetBkMode(hdc, c.TRANSPARENT);

        // Icon, or the check mark in its place.
        if (self.icon_font) |icon_font| {
            const glyph: ?u16 = if (entry.item.checked) glyph_check else if (entry.item.icon) |i| @intFromEnum(i) else null;
            if (glyph) |g| {
                const color = if (entry.item.checked and !disabled) style.accent else if (selected and !disabled) style.text else quiet;
                drawGlyphSized(hdc, icon_font, g, .{ .left = layout.icon_left, .top = rect.top, .right = layout.icon_left + self.metrics.icon_px, .bottom = rect.bottom }, color);
            }
        } else if (entry.item.checked) {
            drawCheck(hdc, layout.icon_left, rect, style.accent, dpi);
        }

        // Label.
        if (self.font) |f| _ = sys.SelectObject(hdc, f);
        _ = sys.SetTextColor(hdc, fg);
        var label_rect: RECT = .{ .left = layout.label_left, .top = rect.top, .right = layout.label_right, .bottom = rect.bottom };
        const prefix: UINT = if (dis.itemState & ODS_NOACCEL != 0) DT_HIDEPREFIX else 0;
        gdi.drawTextWz(hdc, entry.label_w, &label_rect, c.DT_LEFT | c.DT_VCENTER | c.DT_SINGLELINE | c.DT_END_ELLIPSIS | prefix);

        // Trailing: a submenu chevron, or the shortcut as keycaps.
        if (entry.item.submenu != null) {
            const box: RECT = .{ .left = layout.trailing_right - self.metrics.icon_px, .top = rect.top, .right = layout.trailing_right, .bottom = rect.bottom };
            if (self.icon_font) |icon_font| {
                drawGlyphSized(hdc, icon_font, glyph_chevron, box, quiet);
            } else {
                drawChevron(hdc, box, quiet, dpi);
            }
        } else if (entry.item.shortcut) |shortcut| {
            drawKeycaps(hdc, self.keycaps(selected, disabled), shortcut, layout.trailing_right, rect);
        }

        // The system draws its own submenu arrow and check after this
        // returns; keep it off the row.
        excludeItem(hdc, dis.rcItem);
    }
};

/// The highlighted row's fill: the accent washed into the surface. Menus and
/// the command palette share it.
pub fn highlightColor(bg: u32, accent: u32, is_dark: bool) u32 {
    return gdi.blendColorRGB(bg, accent, if (is_dark) 0.24 else 0.16);
}

/// How a run of keycaps is drawn. `base` is what they sit on (the row, or
/// its highlight), so their fill and border stay a step off it.
pub const Keycaps = struct {
    base: u32,
    text: u32,
    fg: u32,
    is_dark: bool,
    dpi: u32,
    font: ?*anyopaque,
    height: i32,
};

/// Keys whose names are longer than what is printed on them.
const key_symbols = [_]struct { []const u8, []const u8 }{
    .{ "backslash", "\\" },      .{ "slash", "/" },         .{ "comma", "," },
    .{ "period", "." },          .{ "minus", "-" },         .{ "equal", "=" },
    .{ "plus", "+" },            .{ "semicolon", ";" },     .{ "apostrophe", "'" },
    .{ "grave_accent", "`" },    .{ "bracket_left", "[" },  .{ "bracket_right", "]" },
    .{ "left_bracket", "[" },    .{ "right_bracket", "]" }, .{ "page_up", "PgUp" },
    .{ "page_down", "PgDn" },    .{ "escape", "Esc" },      .{ "backspace", "Bksp" },
    .{ "arrow_up", "Up" },       .{ "arrow_down", "Down" }, .{ "arrow_left", "Left" },
    .{ "arrow_right", "Right" }, .{ "delete", "Del" },      .{ "insert", "Ins" },
};

/// "ctrl" and "p" show as "Ctrl" and "P", and "backslash" as "\\", the way
/// the keys are printed.
pub fn keycapLabel(key: []const u8, buf: []u8) []const u8 {
    for (key_symbols) |pair| {
        if (std.ascii.eqlIgnoreCase(key, pair[0])) return pair[1];
    }
    const n = @min(key.len, buf.len);
    @memcpy(buf[0..n], key[0..n]);
    if (n > 0) buf[0] = std.ascii.toUpper(buf[0]);
    return buf[0..n];
}

fn keycapWidth(hdc: HDC, caps: Keycaps, key: []const u8) i32 {
    var label_buf: [16]u8 = undefined;
    var buf: [32]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, keycapLabel(key, &label_buf)) catch return 0;
    return @max(textWidthIn(hdc, caps.font, buf[0..len]) + scale(12, caps.dpi), caps.height + scale(2, caps.dpi));
}

pub fn keycapsWidth(hdc: HDC, caps: Keycaps, shortcut: []const u8) i32 {
    var keys_buf: [6][]const u8 = undefined;
    const keys = keys_buf[0..splitShortcut(shortcut, &keys_buf)];
    var width: i32 = 0;
    for (keys, 0..) |key, i| {
        if (i > 0) width += scale(4, caps.dpi);
        width += keycapWidth(hdc, caps, key);
    }
    return width;
}

/// Draws `shortcut` as keycaps ending at `right`, centred in `row`.
pub fn drawKeycaps(hdc: HDC, caps: Keycaps, shortcut: []const u8, right: i32, row: RECT) void {
    var keys_buf: [6][]const u8 = undefined;
    const keys = keys_buf[0..splitShortcut(shortcut, &keys_buf)];
    const top = row.top + @divTrunc(row.bottom - row.top - caps.height, 2);
    const cap_bg = gdi.blendColorRGB(caps.base, caps.text, if (caps.is_dark) 0.08 else 0.05);
    const cap_border = gdi.blendColorRGB(caps.base, caps.text, if (caps.is_dark) 0.18 else 0.16);
    const old_font = if (caps.font) |f| sys.SelectObject(hdc, f) else null;
    defer if (old_font) |f| {
        _ = sys.SelectObject(hdc, f);
    };
    _ = sys.SetBkMode(hdc, c.TRANSPARENT);
    _ = sys.SetTextColor(hdc, caps.fg);

    var x = right;
    var i = keys.len;
    while (i > 0) {
        i -= 1;
        const w = keycapWidth(hdc, caps, keys[i]);
        const cap: RECT = .{ .left = x - w, .top = top, .right = x, .bottom = top + caps.height };
        gdi.drawRoundedRect(hdc, cap, cap_bg, cap_border, scale(5, caps.dpi));
        var label_buf: [16]u8 = undefined;
        var buf: [32:0]u16 = undefined;
        const len = std.unicode.utf8ToUtf16Le(&buf, keycapLabel(keys[i], &label_buf)) catch 0;
        buf[len] = 0;
        var text_rect = cap;
        gdi.drawTextWz(hdc, buf[0..len :0], &text_rect, c.DT_CENTER | c.DT_VCENTER | c.DT_SINGLELINE | c.DT_NOPREFIX);
        x -= w + scale(4, caps.dpi);
    }
}

fn textWidthIn(hdc: HDC, font: ?*anyopaque, text: []const u16) i32 {
    if (text.len == 0) return 0;
    const old = if (font) |f| sys.SelectObject(hdc, f) else null;
    defer if (old) |o| {
        _ = sys.SelectObject(hdc, o);
    };
    var size: SIZE = .{};
    _ = GetTextExtentPoint32W(hdc, text.ptr, @intCast(text.len), &size);
    return size.cx;
}

fn rowTextColor(style: Style, destructive: bool, disabled: bool) u32 {
    if (disabled) return style.text_disabled;
    if (destructive) return style.error_fg;
    return style.text;
}

pub fn fillRound(hdc: HDC, rect: RECT, color: u32, radius: i32) void {
    const brush = sys.GetStockObject(c.DC_BRUSH) orelse return;
    const pen = sys.GetStockObject(c.NULL_PEN) orelse return;
    _ = sys.SetDCBrushColor(hdc, color);
    const old_brush = sys.SelectObject(hdc, brush);
    defer _ = sys.SelectObject(hdc, old_brush);
    const old_pen = sys.SelectObject(hdc, pen);
    defer _ = sys.SelectObject(hdc, old_pen);
    // A null pen leaves the right and bottom edge one pixel short.
    _ = sys.RoundRect(hdc, rect.left, rect.top, rect.right + 1, rect.bottom + 1, radius, radius);
}

fn drawGlyphSized(hdc: HDC, font: *anyopaque, glyph: u16, box: RECT, color: u32) void {
    const old = sys.SelectObject(hdc, font);
    defer _ = sys.SelectObject(hdc, old);
    _ = sys.SetTextColor(hdc, color);
    var text = [_:0]u16{glyph};
    var rect = box;
    gdi.drawTextWz(hdc, &text, &rect, c.DT_CENTER | c.DT_VCENTER | c.DT_SINGLELINE | c.DT_NOPREFIX);
}

fn drawCheck(hdc: HDC, left: i32, row: RECT, color: u32, dpi: u32) void {
    const pen = sys.CreatePen(c.PS_SOLID, @max(1, scale(2, dpi)), color) orelse return;
    defer _ = sys.DeleteObject(pen);
    const old = sys.SelectObject(hdc, pen);
    defer _ = sys.SelectObject(hdc, old);
    const mid = @divTrunc(row.top + row.bottom, 2);
    _ = sys.MoveToEx(hdc, left + scale(2, dpi), mid, null);
    _ = sys.LineTo(hdc, left + scale(6, dpi), mid + scale(4, dpi));
    _ = sys.LineTo(hdc, left + scale(14, dpi), mid - scale(4, dpi));
}

fn drawChevron(hdc: HDC, box: RECT, color: u32, dpi: u32) void {
    const pen = sys.CreatePen(c.PS_SOLID, @max(1, scale(1, dpi)), color) orelse return;
    defer _ = sys.DeleteObject(pen);
    const old = sys.SelectObject(hdc, pen);
    defer _ = sys.SelectObject(hdc, old);
    const mid_y = @divTrunc(box.top + box.bottom, 2);
    const mid_x = @divTrunc(box.left + box.right, 2);
    _ = sys.MoveToEx(hdc, mid_x - scale(2, dpi), mid_y - scale(4, dpi), null);
    _ = sys.LineTo(hdc, mid_x + scale(2, dpi), mid_y);
    _ = sys.LineTo(hdc, mid_x - scale(2, dpi), mid_y + scale(4, dpi) + 1);
}

fn excludeItem(hdc: HDC, rect: RECT) void {
    _ = ExcludeClipRect(hdc, rect.left, rect.top, rect.right, rect.bottom);
}

/// Rounds the menu window and gives it the card's border, the moment
/// Windows creates it. Windows 10 has neither attribute and ignores both.
fn menuWindowHook(code: i32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT {
    if (code >= 0) {
        const cwp: *const CWPSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
        if ((cwp.message == WM_CREATE or cwp.message == WM_SHOWWINDOW) and isMenuWindow(cwp.hwnd)) {
            if (active) |session| styleMenuWindow(cwp.hwnd, session.style);
        }
    }
    return CallNextHookEx(null, code, wParam, lParam);
}

fn isMenuWindow(hwnd: HWND) bool {
    var name: [16]u16 = undefined;
    const len = GetClassNameW(hwnd, &name, name.len);
    return len > 0 and std.mem.eql(u16, name[0..@intCast(len)], std.unicode.utf8ToUtf16LeStringLiteral("#32768"));
}

fn styleMenuWindow(hwnd: HWND, style: Style) void {
    const dark: BOOL = if (style.is_dark) 1 else 0;
    _ = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @ptrCast(&dark), @sizeOf(BOOL));
    const corner: u32 = DWMWCP_ROUND;
    _ = DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, @ptrCast(&corner), @sizeOf(u32));
    const border: u32 = style.border;
    _ = DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, @ptrCast(&border), @sizeOf(u32));
}

threadlocal var active: ?*Session = null;

// Win32 bits this module alone uses.
const ODT_MENU: UINT = 1;
const SM_CXMENUCHECK: i32 = 71;
const ODS_GRAYED: UINT = 0x0002;
const ODS_NOACCEL: UINT = 0x0100;
const DT_HIDEPREFIX: UINT = 0x00100000;
const MF_OWNERDRAW: UINT = 0x00000100;
const MNC_EXECUTE: isize = 2;
const MIM_BACKGROUND: DWORD = 0x00000002;
const MIM_APPLYTOSUBMENUS: DWORD = 0x80000000;
const MSAA_MENU_SIG: DWORD = 0xAA0DF00D;
const TPM_VERPOSANIMATION: UINT = 0x1000;
const TPM_NOANIMATION: UINT = 0x4000;
const WH_CALLWNDPROC: i32 = 4;
const WM_CREATE: UINT = 0x0001;
const WM_SHOWWINDOW: UINT = 0x0018;
const DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20;
const DWMWA_WINDOW_CORNER_PREFERENCE: DWORD = 33;
const DWMWA_BORDER_COLOR: DWORD = 34;
const DWMWCP_ROUND: u32 = 2;

const MSAAMENUINFO = extern struct {
    dwMSAASignature: DWORD,
    cchWText: DWORD,
    pszWText: [*:0]u16,
};

const MEASUREITEMSTRUCT = extern struct {
    CtlType: UINT,
    CtlID: UINT,
    itemID: UINT,
    itemWidth: UINT,
    itemHeight: UINT,
    itemData: usize,
};

const MENUINFO = extern struct {
    cbSize: DWORD = @sizeOf(MENUINFO),
    fMask: DWORD = 0,
    dwStyle: DWORD = 0,
    cyMax: UINT = 0,
    hbrBack: ?*anyopaque = null,
    dwContextHelpID: DWORD = 0,
    dwMenuData: usize = 0,
};

const CWPSTRUCT = extern struct {
    lParam: LPARAM,
    wParam: WPARAM,
    message: UINT,
    hwnd: HWND,
};

const SIZE = extern struct { cx: i32 = 0, cy: i32 = 0 };

const HOOKPROC = *const fn (i32, WPARAM, LPARAM) callconv(.winapi) LRESULT;

extern "user32" fn SetMenuInfo(hMenu: ?*anyopaque, lpcmi: *const MENUINFO) callconv(.winapi) BOOL;
extern "user32" fn SetWindowsHookExW(idHook: i32, lpfn: HOOKPROC, hmod: ?*anyopaque, dwThreadId: DWORD) callconv(.winapi) ?*anyopaque;
extern "user32" fn UnhookWindowsHookEx(hhk: *anyopaque) callconv(.winapi) BOOL;
extern "user32" fn CallNextHookEx(hhk: ?*anyopaque, nCode: i32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn GetClassNameW(hWnd: HWND, lpClassName: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
extern "gdi32" fn GetTextExtentPoint32W(hdc: HDC, lpString: [*]const u16, count: i32, psizl: *SIZE) callconv(.winapi) BOOL;
extern "gdi32" fn ExcludeClipRect(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32) callconv(.winapi) i32;
extern "user32" fn SystemParametersInfoForDpi(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT, dpi: UINT) callconv(.winapi) BOOL;
extern "dwmapi" fn DwmSetWindowAttribute(HWND, DWORD, *const anyopaque, DWORD) callconv(.winapi) i32;

test "a shortcut splits into one keycap per key" {
    var out: [6][]const u8 = undefined;
    const keys = out[0..splitShortcut("Ctrl+Shift+C", &out)];
    try std.testing.expectEqual(@as(usize, 3), keys.len);
    try std.testing.expectEqualStrings("Ctrl", keys[0]);
    try std.testing.expectEqualStrings("Shift", keys[1]);
    try std.testing.expectEqualStrings("C", keys[2]);

    const plus = out[0..splitShortcut("Ctrl++", &out)];
    try std.testing.expectEqual(@as(usize, 2), plus.len);
    try std.testing.expectEqualStrings("+", plus[1]);

    try std.testing.expectEqual(@as(usize, 1), splitShortcut("F11", &out));
    try std.testing.expectEqual(@as(usize, 0), splitShortcut("", &out));
}

test "the label never runs into the keycaps, at any scale" {
    for ([_]u32{ 96, 144, 192, 288 }) |dpi| {
        const with_caps = rowLayout(0, scale(220, dpi), true, scale(90, dpi), scale(16, dpi), dpi);
        try std.testing.expect(with_caps.label_left > with_caps.icon_left + scale(16, dpi));
        try std.testing.expect(with_caps.label_right <= with_caps.trailing_right - scale(90, dpi));
        // A row too narrow for both keeps the label start, never a negative width.
        const cramped = rowLayout(0, scale(60, dpi), true, scale(90, dpi), scale(16, dpi), dpi);
        try std.testing.expect(cramped.label_right >= cramped.label_left);
        const plain = rowLayout(0, scale(220, dpi), false, 0, scale(16, dpi), dpi);
        try std.testing.expect(plain.label_left < with_caps.label_left);
        try std.testing.expectEqual(plain.trailing_right, plain.label_right);
    }
}

test "a keycap prints its key the way the key is labelled" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("Ctrl", keycapLabel("ctrl", &buf));
    try std.testing.expectEqualStrings("P", keycapLabel("p", &buf));
    try std.testing.expectEqualStrings("Shift", keycapLabel("Shift", &buf));
    try std.testing.expectEqualStrings("", keycapLabel("", &buf));
    try std.testing.expectEqualStrings("\\", keycapLabel("backslash", &buf));
    try std.testing.expectEqualStrings("PgUp", keycapLabel("page_up", &buf));
}

test "menu sizes follow Windows text size and never drop below the floor" {
    // Default 9 pt menu font (12 px): the 14 px floor and 32 px rows hold.
    const default = metricsFor(12, 96);
    try std.testing.expectEqual(@as(i32, 14), default.text_px);
    try std.testing.expectEqual(@as(i32, 32), default.row);
    try std.testing.expectEqual(@as(i32, 16), default.icon_px);
    // Text size 225%: everything grows with the text, nothing clips it.
    const large = metricsFor(27, 96);
    try std.testing.expectEqual(@as(i32, 27), large.text_px);
    try std.testing.expect(large.row >= large.text_px + 18);
    try std.testing.expect(large.icon_px > default.icon_px);
    try std.testing.expect(large.cap > large.small_px);
    // 150% scale with default text: the floor scales with the dpi.
    const hidpi = metricsFor(18, 144);
    try std.testing.expectEqual(@as(i32, 21), hidpi.text_px);
    try std.testing.expectEqual(@as(i32, 48), hidpi.row);
}

test "a mnemonic is the letter after a single ampersand" {
    try std.testing.expectEqual(@as(?u8, 'R'), mnemonicOf("&Reset to default"));
    try std.testing.expectEqual(@as(?u8, 'b'), mnemonicOf("Fish && &bread"));
    try std.testing.expectEqual(@as(?u8, null), mnemonicOf("Copy"));
    try std.testing.expectEqual(@as(?u8, null), mnemonicOf("trailing&"));
}
