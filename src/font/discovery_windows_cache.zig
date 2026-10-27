//! A persistent index of what the Windows font scan found in each file, so
//! a launch that names a font does not open every installed font with
//! FreeType again. Measured on a 568-face machine: naming a `font-family`
//! added 94 ms (median of 9) to cold start, and `font-codepoint-map` 62 ms,
//! all of it the scan the first grid waits for.
//!
//! An entry is reused only while its file's size and modification time are
//! unchanged; anything else is scanned as before and the index rewritten.
//! The index is also dropped whole when the build version or this format
//! changes, so a scan fix in a newer build is never hidden by old entries.
//! Coverage is not stored; it is still read lazily per face.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Bump when `Face` or how the scan fills it changes.
pub const format_version: u32 = 1;

/// One face as the scan recorded it (Record minus the lazy coverage).
pub const Face = struct {
    face_index: i32,
    family_name: []const u8,
    style_name: []const u8,
    full_name: []const u8,
    typographic_family: ?[]const u8 = null,
    typographic_style: ?[]const u8 = null,
    weight: u16,
    weight_min: ?f64 = null,
    weight_max: ?f64 = null,
    monospace: bool,
    bold: bool,
    italic: bool,
    color: bool,
    variable: bool,
};

/// Every face found in one file, and the file stamp they are valid for.
pub const File = struct {
    path: []const u8,
    size: u64,
    mtime: i128,
    faces: []const Face,
};

const Document = struct {
    format: u32,
    build: []const u8,
    files: []const File,
};

/// A loaded index. Owns its memory through `arena`.
pub const Index = struct {
    arena: std.heap.ArenaAllocator,
    by_path: std.StringHashMapUnmanaged(File) = .{},

    pub fn deinit(self: *Index) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// The faces recorded for `path`, if its stamp still matches.
    pub fn lookup(self: *const Index, path: []const u8, size: u64, mtime: i128) ?[]const Face {
        const file = self.by_path.get(path) orelse return null;
        if (file.size != size or file.mtime != mtime) return null;
        return file.faces;
    }
};

/// Read the index at `path`. Null when it is missing, unreadable, from
/// another build or format, or malformed: the caller then scans everything.
pub fn load(gpa: Allocator, path: []const u8, build: []const u8) ?Index {
    var index: Index = .{ .arena = std.heap.ArenaAllocator.init(gpa) };
    errdefer index.deinit();
    const alloc = index.arena.allocator();

    const bytes = std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024 * 1024) catch return deinitNull(&index);
    const doc = std.json.parseFromSliceLeaky(Document, alloc, bytes, .{ .ignore_unknown_fields = true }) catch
        return deinitNull(&index);
    if (doc.format != format_version or !std.mem.eql(u8, doc.build, build)) return deinitNull(&index);

    for (doc.files) |file| index.by_path.put(alloc, file.path, file) catch return deinitNull(&index);
    return index;
}

fn deinitNull(index: *Index) ?Index {
    index.deinit();
    return null;
}

/// Write `files` to `path`, through a temporary file and a rename so a
/// crash mid-write leaves the old index or none, never half of one.
pub fn save(gpa: Allocator, path: []const u8, build: []const u8, files: []const File) !void {
    if (std.fs.path.dirname(path)) |dir| try std.fs.cwd().makePath(dir);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(Document{
        .format = format_version,
        .build = build,
        .files = files,
    }, .{ .emit_null_optional_fields = false }, &out.writer);

    const tmp_path = try std.fmt.allocPrint(gpa, "{s}.tmp", .{path});
    defer gpa.free(tmp_path);
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = out.written() });
    try std.fs.cwd().rename(tmp_path, path);
}

test "font index round-trips and reuses only unchanged files" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);
    const path = try std.fs.path.join(testing.allocator, &.{ dir, "sub", "font-index.json" });
    defer testing.allocator.free(path);

    const faces = [_]Face{
        .{ .face_index = 0, .family_name = "Cascadia Code", .style_name = "Regular", .full_name = "Cascadia Code Regular", .weight = 400, .weight_min = 200, .weight_max = 700, .monospace = true, .bold = false, .italic = false, .color = false, .variable = true },
        .{ .face_index = 1, .family_name = "Segoe UI", .style_name = "Bold", .full_name = "Segoe UI Bold", .typographic_family = "Segoe UI Variable", .weight = 700, .monospace = false, .bold = true, .italic = false, .color = false, .variable = false },
    };
    const files = [_]File{.{ .path = "C:\\Windows\\Fonts\\a.ttf", .size = 1234, .mtime = 5678, .faces = &faces }};
    try save(testing.allocator, path, "1.0.0", &files);

    var index = load(testing.allocator, path, "1.0.0") orelse return error.TestExpectedIndex;
    defer index.deinit();

    const hit = index.lookup("C:\\Windows\\Fonts\\a.ttf", 1234, 5678) orelse return error.TestExpectedHit;
    try testing.expectEqual(@as(usize, 2), hit.len);
    try testing.expectEqualStrings("Cascadia Code", hit[0].family_name);
    try testing.expectEqual(@as(?f64, 700), hit[0].weight_max);
    try testing.expectEqualStrings("Segoe UI Variable", hit[1].typographic_family.?);
    try testing.expectEqual(@as(?[]const u8, null), hit[0].typographic_style);

    // A changed file, an unknown file: scanned again.
    try testing.expectEqual(@as(?[]const Face, null), index.lookup("C:\\Windows\\Fonts\\a.ttf", 1235, 5678));
    try testing.expectEqual(@as(?[]const Face, null), index.lookup("C:\\Windows\\Fonts\\a.ttf", 1234, 5679));
    try testing.expectEqual(@as(?[]const Face, null), index.lookup("C:\\Windows\\Fonts\\b.ttf", 1234, 5678));
}

test "font index from another build, another format or garbage is ignored" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);
    const path = try std.fs.path.join(testing.allocator, &.{ dir, "font-index.json" });
    defer testing.allocator.free(path);

    try save(testing.allocator, path, "1.0.0", &.{});
    try testing.expect(load(testing.allocator, path, "1.0.1") == null);

    try tmp.dir.writeFile(.{ .sub_path = "font-index.json", .data = "{\"format\":999,\"build\":\"1.0.0\",\"files\":[]}" });
    try testing.expect(load(testing.allocator, path, "1.0.0") == null);

    try tmp.dir.writeFile(.{ .sub_path = "font-index.json", .data = "not json" });
    try testing.expect(load(testing.allocator, path, "1.0.0") == null);

    const missing = try std.fs.path.join(testing.allocator, &.{ dir, "absent.json" });
    defer testing.allocator.free(missing);
    try testing.expect(load(testing.allocator, missing, "1.0.0") == null);
}
