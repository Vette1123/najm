//! Najm: what Settings shows in the open terminals while a draft is unsaved.
//!
//! The chrome's preview (`App.settings_preview`) is a clone of the running
//! config with typed fields set on it. A terminal's look cannot be previewed
//! that way: a theme sets colours a later theme must take away, `text-color`
//! and the bold/italic font families are filled in by `finalize`, and a
//! `config-file` include or a command-line option can override what Settings
//! saves. So the panes' preview is the config Save would produce: the user's
//! files loaded again, the edited keys written as lines right after the main
//! config file (where Save patches them), then the command line and the
//! includes over them, then `finalize`. `App.previewSettingsPanes` pushes it
//! into every open pane; the running config and new terminals never see it.

const std = @import("std");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const Key = @import("../../config/key.zig").Key;
const formatter = @import("../../config/formatter.zig");

/// The keys whose draft every open terminal shows before Save: how the text
/// looks and where it sits. Everything else either has its own preview (the
/// chrome's, `PreviewEffect`) or only applies to terminals started later.
pub const keys = [_]Key{
    .@"font-size",
    .@"font-family",
    .theme,
    .@"text-color",
    .@"cursor-style",
    .@"window-padding-x",
    .@"window-padding-y",
    .@"window-padding-balance",
};

/// Whether open terminals preview `key`.
pub fn previews(key: Key) bool {
    return for (keys) |k| {
        if (k == key) break true;
    } else false;
}

/// One setting as config text, every line ending in a newline. A repeatable
/// list that is not empty starts with `<key> = `, which resets what lower
/// layers set; an empty list's formatter already emits that reset. Save
/// writes its lines with this too (`patchOrAppendEdits`).
pub fn writeEntry(
    comptime field: std.builtin.Type.StructField,
    value: field.type,
    writer: *std.Io.Writer,
) !void {
    if (field.type == Config.RepeatableString and value.list.items.len != 0)
        try writer.print("{s} = \n", .{field.name});
    try formatter.formatEntry(field.type, field.name, value, writer);
}

/// Writes the lines of every previewed key `pending` changed from
/// `original`, and returns how many keys that was. Zero: nothing to preview.
pub fn writeLines(
    original: *const Config,
    pending: *const Config,
    writer: *std.Io.Writer,
) !usize {
    var count: usize = 0;
    inline for (keys) |key| {
        if (original.changed(pending, key)) {
            try writeEntry(fieldOf(key), @field(pending, @tagName(key)), writer);
            count += 1;
        }
    }
    return count;
}

fn fieldOf(comptime key: Key) std.builtin.Type.StructField {
    for (std.meta.fields(Config)) |field| {
        if (std.mem.eql(u8, field.name, @tagName(key))) return field;
    }
    @compileError("no Config field for " ++ @tagName(key));
}

/// Loads `lines` (from `writeLines`) into `config` as a config file would.
pub fn loadLines(config: *Config, alloc: std.mem.Allocator, lines: []const u8) !void {
    var reader: std.Io.Reader = .fixed(lines);
    try config.loadReader(alloc, &reader, "Settings preview");
}

/// The config Save would give with `lines` saved: loaded as `Config.load`
/// loads, with `lines` after the main config file. In `conditional` (the
/// running config's light/dark state), its launch layout dropped as the
/// palette's theme preview drops it. The caller runs it at the startup cwd
/// (`App.enterStartupCwd`) and owns the result.
pub fn load(
    alloc: std.mem.Allocator,
    lines: []const u8,
    conditional: @FieldType(Config, "_conditional_state"),
) !Config {
    var result = try Config.default(alloc);
    errdefer result.deinit();
    try result.loadDefaultFiles(alloc);
    try loadLines(&result, alloc, lines);
    try result.loadCliArgs(alloc);
    try result.loadRecursiveFiles(alloc);
    try finish(&result, conditional);
    return result;
}

/// `finalize` in `conditional`, without a launch layout.
pub fn finish(config: *Config, conditional: @FieldType(Config, "_conditional_state")) !void {
    config._conditional_state = conditional;
    try config.finalize();
    config.@"launch-layout" = null;
    _ = config.dropLaunchLayoutReplaySteps(0);
}

test "settings pane preview writes only the previewed keys a draft changed" {
    const alloc = std.testing.allocator;
    var original = try Config.default(alloc);
    defer original.deinit();
    var pending = try original.clone(alloc);
    defer pending.deinit();

    var none: std.Io.Writer.Allocating = .init(alloc);
    defer none.deinit();
    try std.testing.expectEqual(@as(usize, 0), try writeLines(&original, &pending, &none.writer));
    try std.testing.expectEqualStrings("", none.written());

    pending.@"font-size" = 17;
    pending.@"scrollback-limit" = 1234; // not previewed in panes
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try std.testing.expectEqual(@as(usize, 1), try writeLines(&original, &pending, &out.writer));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "font-size = 17") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "scrollback-limit") == null);
}

test "settings pane preview lines give the finalized config Save would" {
    const alloc = std.testing.allocator;
    var original = try Config.default(alloc);
    defer original.deinit();
    var pending = try original.clone(alloc);
    defer pending.deinit();
    pending.@"font-size" = 19;
    pending.@"cursor-style" = .underline;
    try loadLines(&pending, alloc, "font-family = Cascadia Mono\n");

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try std.testing.expectEqual(@as(usize, 3), try writeLines(&original, &pending, &out.writer));

    var preview = try Config.default(alloc);
    defer preview.deinit();
    try loadLines(&preview, alloc, out.written());
    try finish(&preview, original._conditional_state);
    try std.testing.expectEqual(@as(f32, 19), preview.@"font-size");
    try std.testing.expectEqual(pending.@"cursor-style", preview.@"cursor-style");
    try std.testing.expectEqual(@as(usize, 1), preview.@"font-family".count());
    // `finalize` gives the other styles the family, as a saved one does.
    try std.testing.expectEqual(@as(usize, 1), preview.@"font-family-bold".count());
    try std.testing.expect(!original.changed(&preview, .@"scrollback-limit"));
}

test "settings pane preview previews how terminal text looks, not what starts" {
    try std.testing.expect(previews(.@"font-size"));
    try std.testing.expect(previews(.theme));
    try std.testing.expect(previews(.@"font-family"));
    try std.testing.expect(!previews(.command));
    try std.testing.expect(!previews(.@"scrollback-limit"));
    try std.testing.expect(!previews(.@"background-opacity"));
}
