//! Najm: an opt-in recorder for what one terminal receives from its pty and
//! when it resizes, written as a replay script for
//! `src/terminal/resize_replay.zig` (`size`, `pty conpty`, `send`,
//! `resize`). A screen that goes wrong in use can then be replayed through
//! the same terminal code, byte for byte.
//!
//! Set `NAJM_PTY_RECORD_DIR` to a directory to turn it on; each terminal
//! writes `najm-<pid>-<n>.vt` there. A file past `rotate_bytes` is renamed
//! to `.prev.vt` and a new one starts at the current size, so the disk use
//! stays near twice that per terminal. Off when the variable is unset.

const std = @import("std");
const internal_os = @import("../os/main.zig");

pub const rotate_bytes: u64 = 32 * 1024 * 1024;

var next_id = std.atomic.Value(u32).init(0);

pub const Recorder = struct {
    mutex: std.Thread.Mutex = .{},
    file: ?std.fs.File = null,
    path: ?[]u8 = null,
    alloc: ?std.mem.Allocator = null,
    written: u64 = 0,
    cols: u16 = 0,
    rows: u16 = 0,

    pub fn init(alloc: std.mem.Allocator, cols: u16, rows: u16) Recorder {
        const dir = (internal_os.getEnvVarOwnedTrimmedNotEmpty(alloc, "NAJM_PTY_RECORD_DIR") catch return .{}) orelse return .{};
        defer alloc.free(dir);
        pruneOld(dir, std.time.timestamp());
        const pid = if (@import("builtin").os.tag == .windows) std.os.windows.GetCurrentProcessId() else 0;
        const name = std.fmt.allocPrint(alloc, "najm-{d}-{d}.vt", .{ pid, next_id.fetchAdd(1, .monotonic) }) catch return .{};
        defer alloc.free(name);
        const path = std.fs.path.join(alloc, &.{ dir, name }) catch return .{};
        var self: Recorder = .{ .path = path, .alloc = alloc, .cols = cols, .rows = rows };
        self.open() catch {
            alloc.free(path);
            return .{};
        };
        return self;
    }

    pub fn deinit(self: *Recorder) void {
        if (self.file) |f| f.close();
        if (self.path) |p| self.alloc.?.free(p);
        self.* = .{};
    }

    /// Bytes the terminal is about to process.
    pub fn output(self: *Recorder, bytes: []const u8) void {
        if (self.file == null) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        var i: usize = 0;
        while (i < bytes.len) {
            const end = @min(bytes.len, i + 4096);
            self.writeLine("send ", bytes[i..end]);
            i = end;
        }
        self.maybeRotate();
    }

    pub fn resize(self: *Recorder, cols: u16, rows: u16) void {
        if (self.file == null) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        self.cols = cols;
        self.rows = rows;
        var buf: [48]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "resize {d} {d}\n", .{ cols, rows }) catch return;
        self.writeRaw(line);
    }

    fn open(self: *Recorder) !void {
        const file = try std.fs.cwd().createFile(self.path.?, .{ .truncate = true });
        self.file = file;
        self.written = 0;
        var buf: [96]u8 = undefined;
        self.writeRaw(try std.fmt.bufPrint(&buf, "# recorded by Najm\nsize {d} {d}\npty conpty\n", .{ self.cols, self.rows }));
    }

    fn maybeRotate(self: *Recorder) void {
        if (self.written < rotate_bytes) return;
        const alloc = self.alloc.?;
        const path = self.path.?;
        self.file.?.close();
        self.file = null;
        const prev = std.fmt.allocPrint(alloc, "{s}.prev.vt", .{path[0 .. path.len - ".vt".len]}) catch return;
        defer alloc.free(prev);
        std.fs.cwd().rename(path, prev) catch {};
        self.open() catch {};
    }

    fn writeLine(self: *Recorder, prefix: []const u8, bytes: []const u8) void {
        var buf: [4096 * 4 + 16]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        w.writeAll(prefix) catch return;
        writeEscaped(&w, bytes) catch return;
        w.writeByte('\n') catch return;
        self.writeRaw(w.buffered());
    }

    fn writeRaw(self: *Recorder, bytes: []const u8) void {
        const file = self.file orelse return;
        file.writeAll(bytes) catch {
            // A full disk or a removed directory ends the recording, never
            // the terminal.
            file.close();
            self.file = null;
            return;
        };
        self.written += bytes.len;
    }
};

/// Recordings are kept this long; every new terminal deletes older ones,
/// so a recording left on does not fill the disk.
pub const keep_seconds: i64 = 2 * 24 * 60 * 60;

/// Deletes this recorder's own files (`najm-*.vt`) in `dir` last written
/// before `now - keep_seconds`. Anything else in the directory is left.
pub fn pruneOld(dir_path: []const u8, now: i64) void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch return) |entry| {
        if (entry.kind != .file or !isRecording(entry.name)) continue;
        const stat = dir.statFile(entry.name) catch continue;
        const written: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
        if (now - written > keep_seconds) dir.deleteFile(entry.name) catch {};
    }
}

pub fn isRecording(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "najm-") and std.mem.endsWith(u8, name, ".vt");
}

/// Writes `bytes` with the escapes `resize_replay`'s `send` decodes: every
/// control byte, every byte past ASCII, the backslash, and spaces (the
/// replay trims a line's edges, and a run of spaces is cheaper to keep
/// exact than to reason about).
pub fn writeEscaped(w: *std.Io.Writer, bytes: []const u8) !void {
    for (bytes) |b| switch (b) {
        0x1b => try w.writeAll("\\e"),
        '\r' => try w.writeAll("\\r"),
        '\n' => try w.writeAll("\\n"),
        '\t' => try w.writeAll("\\t"),
        '\\' => try w.writeAll("\\\\"),
        0x21...0x5b, 0x5d...0x7e => try w.writeByte(b),
        else => try w.print("\\x{x:0>2}", .{b}),
    };
}

test "pruning deletes only old recordings" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    for ([_][]const u8{ "najm-1-0.vt", "najm-1-0.prev.vt", "notes.txt" }) |name| {
        const f = try tmp.dir.createFile(name, .{});
        f.close();
    }
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);

    // Just written: nothing is old enough.
    pruneOld(path, std.time.timestamp());
    try tmp.dir.access("najm-1-0.vt", .{});

    // Three days on: both recordings go, the other file stays.
    pruneOld(path, std.time.timestamp() + 3 * 24 * 60 * 60);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("najm-1-0.vt", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("najm-1-0.prev.vt", .{}));
    try tmp.dir.access("notes.txt", .{});
}

test "a recorded chunk escapes into what the replay decodes" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeEscaped(&w, "\x1b[2K ok\\\r\n\t\xe2\x97\x8f");
    try std.testing.expectEqualStrings("\\e[2K\\x20ok\\\\\\r\\n\\t\\xe2\\x97\\x8f", w.buffered());
}
