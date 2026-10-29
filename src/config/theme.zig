const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const build_config = @import("../build_config.zig");
const global_state = &@import("../global.zig").state;
const internal_os = @import("../os/main.zig");
const cli_diags = @import("../cli/diagnostics.zig");

/// Location of possible themes. The order of this enum matters because it
/// defines the priority of theme search (from top to bottom).
pub const Location = enum {
    user, // XDG config dir
    legacy_user, // Legacy Ghostty XDG config dir
    resources, // Ghostty resources dir

    /// Returns the directory for the given theme based on this location type.
    ///
    /// This will return null with no error if the directory type doesn't exist
    /// or is invalid for any reason. For example, it is perfectly valid to
    /// install and run Ghostty without the resources directory.
    ///
    /// Due to the way allocations are handled, an Arena allocator (or another
    /// similar allocator implementation) should be used. It may not be safe to
    /// free the returned allocations.
    pub fn dir(
        self: Location,
        arena_alloc: Allocator,
    ) error{OutOfMemory}!?[]const u8 {
        return switch (self) {
            .user, .legacy_user => user: {
                const subdir = std.fs.path.join(arena_alloc, &.{
                    if (self == .user) build_config.data_dir_name else "ghostty",
                    "themes",
                }) catch return error.OutOfMemory;

                break :user internal_os.xdg.config(
                    arena_alloc,
                    .{ .subdir = subdir },
                ) catch |err| {
                    // We need to do some comptime tricks to get the right
                    // error set since some platforms don't support some
                    // error types.
                    const Error = @TypeOf(err) || switch (builtin.os.tag) {
                        .ios => error{BufferTooSmall},
                        else => error{},
                    };

                    switch (@as(Error, err)) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.BufferTooSmall => return error.OutOfMemory,

                        // Any other error we treat as the XDG directory not
                        // existing. Windows in particularly can return a LOT
                        // of errors here.
                        else => return null,
                    }
                };
            },

            .resources => try std.fs.path.join(arena_alloc, &.{
                global_state.resources_dir.app() orelse return null,
                "themes",
            }),
        };
    }
};

/// An iterator that returns all possible directories for finding themes in
/// order of priority.
pub const LocationIterator = struct {
    /// Due to the way allocations are handled, an Arena allocator (or another
    /// similar allocator implementation) should be used. It may not be safe to
    /// free the returned allocations.
    arena_alloc: Allocator,
    i: usize = 0,

    pub fn next(self: *LocationIterator) !?struct {
        location: Location,
        dir: []const u8,
    } {
        const max = @typeInfo(Location).@"enum".fields.len;
        while (self.i < max) {
            const location: Location = @enumFromInt(self.i);
            self.i += 1;
            if (try location.dir(self.arena_alloc)) |dir|
                return .{
                    .location = location,
                    .dir = dir,
                };
        }
        return null;
    }

    pub fn reset(self: *LocationIterator) void {
        self.i = 0;
    }
};

pub const Entry = struct {
    location: Location,
    path: []const u8,
    name: []const u8,

    pub fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
        return std.ascii.orderIgnoreCase(lhs.name, rhs.name) == .lt;
    }
};

pub const Directory = struct {
    location: Location,
    dir: []const u8,
};

pub fn list(alloc: Allocator, arena_alloc: Allocator) ![]Entry {
    var dirs: std.ArrayList(Directory) = .empty;
    defer dirs.deinit(alloc);
    try appendDirectories(alloc, arena_alloc, &dirs);
    return try listFromDirectories(alloc, dirs.items);
}

fn appendDirectories(alloc: Allocator, arena_alloc: Allocator, dirs: *std.ArrayList(Directory)) !void {
    var it: LocationIterator = .{ .arena_alloc = arena_alloc };
    while (try it.next()) |loc| {
        try dirs.append(alloc, .{
            .location = loc.location,
            .dir = loc.dir,
        });
    }
}

/// `list`, without walking the theme directories again while none of them
/// changed: the command palette and the Settings theme dropdown list every
/// installed theme each time they open. The caller owns the result, as
/// with `list` (`freeList`); the cache keeps its own copy. UI thread and
/// other callers are serialised by `list_cache_mutex`.
pub fn listCached(alloc: Allocator, arena_alloc: Allocator) ![]Entry {
    var dirs: std.ArrayList(Directory) = .empty;
    defer dirs.deinit(alloc);
    try appendDirectories(alloc, arena_alloc, &dirs);
    list_cache_mutex.lock();
    defer list_cache_mutex.unlock();
    return try list_cache.get(alloc, dirs.items);
}

var list_cache_mutex: std.Thread.Mutex = .{};
var list_cache: ListCache = .{};

/// The last listing and, for each directory it came from, its modification
/// time when the listing started. Adding, removing or renaming a file in a
/// directory changes that directory's time (NTFS and POSIX alike), which is
/// all a listing of names and paths depends on.
const ListCache = struct {
    arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator),
    entries: []const Entry = &.{},
    stamps: []const Stamp = &.{},
    valid: bool = false,
    /// Directory walks done; tests read it.
    rebuilds: u32 = 0,

    const Stamp = struct { dir: []const u8, mtime: i128 };

    fn deinit(self: *ListCache) void {
        self.arena.deinit();
        self.* = undefined;
    }

    fn get(self: *ListCache, alloc: Allocator, dirs: []const Directory) ![]Entry {
        if (!self.valid or !self.matches(dirs)) {
            self.valid = false;
            _ = self.arena.reset(.retain_capacity);
            const keep = self.arena.allocator();
            // Stamped before the walk: a file added during it moves a time
            // past the stamp, so the next call walks again.
            const stamps = try keep.alloc(Stamp, dirs.len);
            for (dirs, stamps) |dir, *stamp| stamp.* = .{ .dir = try keep.dupe(u8, dir.dir), .mtime = dirMtime(dir.dir) };
            const fresh = try listFromDirectories(alloc, dirs);
            defer freeList(alloc, fresh);
            self.entries = try copyEntries(keep, fresh);
            self.stamps = stamps;
            self.valid = true;
            self.rebuilds +%= 1;
        }
        return try copyEntries(alloc, self.entries);
    }

    fn matches(self: *const ListCache, dirs: []const Directory) bool {
        if (self.stamps.len != dirs.len) return false;
        for (self.stamps, dirs) |stamp, dir| {
            if (!std.mem.eql(u8, stamp.dir, dir.dir)) return false;
            if (stamp.mtime != dirMtime(dir.dir)) return false;
        }
        return true;
    }

    /// A directory's modification time, or -1 when it cannot be read (a
    /// missing user theme directory: creating it changes the stamp).
    fn dirMtime(path: []const u8) i128 {
        var dir = std.fs.cwd().openDir(path, .{}) catch return -1;
        defer dir.close();
        const stat = dir.stat() catch return -1;
        return stat.mtime;
    }
};

fn copyEntries(alloc: Allocator, entries: []const Entry) ![]Entry {
    const out = try alloc.alloc(Entry, entries.len);
    var done: usize = 0;
    errdefer {
        for (out[0..done]) |entry| {
            alloc.free(entry.path);
            alloc.free(entry.name);
        }
        alloc.free(out);
    }
    for (entries, out) |entry, *copy| {
        const path = try alloc.dupe(u8, entry.path);
        errdefer alloc.free(path);
        copy.* = .{ .location = entry.location, .path = path, .name = try alloc.dupe(u8, entry.name) };
        done += 1;
    }
    return out;
}

/// Enumerate installed theme files with the same directory priority as
/// `open`: current user themes first, legacy user themes second, and bundled
/// resources last. Duplicate names keep the first location deterministically.
pub fn listFromDirectories(alloc: Allocator, dirs: []const Directory) ![]Entry {
    var themes: std.ArrayList(Entry) = .empty;
    errdefer {
        for (themes.items) |entry| {
            alloc.free(entry.path);
            alloc.free(entry.name);
        }
        themes.deinit(alloc);
    }

    for (dirs) |loc| {
        var dir = std.fs.cwd().openDir(loc.dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {
                std.log.warn("failed to open theme directory dir={s} err={}", .{ loc.dir, err });
                continue;
            },
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            switch (entry.kind) {
                .file, .sym_link => {},
                else => continue,
            }
            if (std.mem.eql(u8, entry.name, ".DS_Store")) continue;
            if (containsThemeName(themes.items, entry.name)) continue;

            try themes.append(alloc, .{
                .location = loc.location,
                .path = try std.fs.path.join(alloc, &.{ loc.dir, entry.name }),
                .name = try alloc.dupe(u8, entry.name),
            });
        }
    }

    std.mem.sortUnstable(Entry, themes.items, {}, Entry.lessThan);
    return try themes.toOwnedSlice(alloc);
}

pub fn freeList(alloc: Allocator, themes: []Entry) void {
    for (themes) |entry| {
        alloc.free(entry.path);
        alloc.free(entry.name);
    }
    alloc.free(themes);
}

fn containsThemeName(themes: []const Entry, name: []const u8) bool {
    for (themes) |theme| {
        if (std.mem.eql(u8, theme.name, name)) return true;
    }
    return false;
}

/// Open the given named theme. If there are any errors then messages
/// will be appended to the given error list and null is returned. If
/// a non-null return value is returned, there are never any errors added.
///
/// One error that is not recoverable and may be returned is OOM. This is
/// always a critical error for configuration loading so it is returned.
///
/// Due to the way allocations are handled, an Arena allocator (or another
/// similar allocator implementation) should be used. It may not be safe to
/// free the returned allocations.
///
/// This will never return anything other than a handle to a regular file. If
/// the theme resolves to something other than a regular file a diagnostic entry
/// will be added to the list and null will be returned.
pub fn open(
    arena_alloc: Allocator,
    theme: []const u8,
    diags: *cli_diags.DiagnosticList,
) error{OutOfMemory}!?struct {
    path: []const u8,
    file: std.fs.File,
} {
    // Absolute themes are loaded a different path.
    if (std.fs.path.isAbsolute(theme)) {
        const file: std.fs.File = try openAbsolute(
            arena_alloc,
            theme,
            diags,
        ) orelse return null;
        const stat = file.stat() catch |err| {
            try diags.append(arena_alloc, .{
                .message = try std.fmt.allocPrintSentinel(
                    arena_alloc,
                    "not reading theme from \"{s}\": {}",
                    .{ theme, err },
                    0,
                ),
            });
            return null;
        };
        switch (stat.kind) {
            .file => {},
            else => {
                try diags.append(arena_alloc, .{
                    .message = try std.fmt.allocPrintSentinel(
                        arena_alloc,
                        "not reading theme from \"{s}\": it is a {s}",
                        .{ theme, @tagName(stat.kind) },
                        0,
                    ),
                });
                return null;
            },
        }
        return .{ .path = theme, .file = file };
    }

    const basename = std.fs.path.basename(theme);
    if (!std.mem.eql(u8, theme, basename)) {
        try diags.append(arena_alloc, .{
            .message = try std.fmt.allocPrintSentinel(
                arena_alloc,
                "theme \"{s}\" cannot include path separators unless it is an absolute path",
                .{theme},
                0,
            ),
        });
        return null;
    }

    // Iterate over the possible locations to try to find the
    // one that exists.
    var it: LocationIterator = .{ .arena_alloc = arena_alloc };
    const cwd = std.fs.cwd();
    while (try it.next()) |loc| {
        const path = try std.fs.path.join(arena_alloc, &.{ loc.dir, theme });
        if (cwd.openFile(path, .{})) |file| {
            const stat = file.stat() catch |err| {
                try diags.append(arena_alloc, .{
                    .message = try std.fmt.allocPrintSentinel(
                        arena_alloc,
                        "not reading theme from \"{s}\": {}",
                        .{ theme, err },
                        0,
                    ),
                });
                return null;
            };
            switch (stat.kind) {
                .file => {},
                else => {
                    try diags.append(arena_alloc, .{
                        .message = try std.fmt.allocPrintSentinel(
                            arena_alloc,
                            "not reading theme from \"{s}\": it is a {s}",
                            .{ theme, @tagName(stat.kind) },
                            0,
                        ),
                    });
                    return null;
                },
            }
            return .{
                .path = path,
                .file = file,
            };
        } else |err| switch (err) {
            // Not an error, just continue to the next location.
            error.FileNotFound => {},

            // Anything else is an error we log and give up on.
            else => {
                try diags.append(arena_alloc, .{
                    .message = try std.fmt.allocPrintSentinel(
                        arena_alloc,
                        "failed to load theme \"{s}\" from the file \"{s}\": {}",
                        .{ theme, path, err },
                        0,
                    ),
                });

                return null;
            },
        }
    }

    // Unlikely scenario: the theme doesn't exist. In this case, we reset
    // our iterator, reiterate over in order to build a better error message.
    // This does double allocate some memory but for errors I think that's
    // fine.
    it.reset();
    try appendNotFound(arena_alloc, theme, &it, diags);

    return null;
}

/// One diagnostic for a theme no directory has, naming every path tried. A
/// diagnostic per directory made a single misspelled name count as several
/// config problems.
fn appendNotFound(
    arena_alloc: Allocator,
    theme: []const u8,
    it: *LocationIterator,
    diags: *cli_diags.DiagnosticList,
) error{OutOfMemory}!void {
    var message: std.Io.Writer.Allocating = .init(arena_alloc);
    message.writer.print("theme \"{s}\" not found", .{theme}) catch return error.OutOfMemory;
    var tried: usize = 0;
    while (try it.next()) |loc| : (tried += 1) {
        const path = try std.fs.path.join(arena_alloc, &.{ loc.dir, theme });
        message.writer.print("{s} \"{s}\"", .{ if (tried == 0) ", tried path" else ",", path }) catch return error.OutOfMemory;
    }
    if (tried == 0) message.writer.writeAll(": there is no theme directory") catch return error.OutOfMemory;
    try diags.append(arena_alloc, .{
        .message = try message.toOwnedSliceSentinel(0),
    });
}

/// Open the given theme from an absolute path. If there are any errors
/// then messages will be appended to the given error list and null is
/// returned. If a non-null return value is returned, there are never any
/// errors added.
///
/// Due to the way allocations are handled, an Arena allocator (or another
/// similar allocator implementation) should be used. It may not be safe to
/// free the returned allocations.
pub fn openAbsolute(
    arena_alloc: Allocator,
    theme: []const u8,
    diags: *cli_diags.DiagnosticList,
) error{OutOfMemory}!?std.fs.File {
    return std.fs.openFileAbsolute(theme, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => try diags.append(arena_alloc, .{
                .message = try std.fmt.allocPrintSentinel(
                    arena_alloc,
                    "failed to load theme from the path \"{s}\"",
                    .{theme},
                    0,
                ),
            }),
            else => try diags.append(arena_alloc, .{
                .message = try std.fmt.allocPrintSentinel(
                    arena_alloc,
                    "failed to load theme from the path \"{s}\": {}",
                    .{ theme, err },
                    0,
                ),
            }),
        }

        return null;
    };
}

test "theme list keeps first duplicate by directory priority" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("user");
    try tmp.dir.makePath("legacy-user");
    try tmp.dir.makePath("resources");
    {
        var file = try tmp.dir.createFile("user/Dupe", .{});
        file.close();
    }
    {
        var file = try tmp.dir.createFile("legacy-user/Dupe", .{});
        file.close();
    }
    {
        var file = try tmp.dir.createFile("legacy-user/LegacyWins", .{});
        file.close();
    }
    {
        var file = try tmp.dir.createFile("resources/Dupe", .{});
        file.close();
    }
    {
        var file = try tmp.dir.createFile("resources/LegacyWins", .{});
        file.close();
    }

    var user_buf: [std.fs.max_path_bytes]u8 = undefined;
    var legacy_user_buf: [std.fs.max_path_bytes]u8 = undefined;
    var resources_buf: [std.fs.max_path_bytes]u8 = undefined;
    const user_dir = try tmp.dir.realpath("user", &user_buf);
    const legacy_user_dir = try tmp.dir.realpath("legacy-user", &legacy_user_buf);
    const resources_dir = try tmp.dir.realpath("resources", &resources_buf);
    const entries = try listFromDirectories(std.testing.allocator, &.{
        .{ .location = .user, .dir = user_dir },
        .{ .location = .legacy_user, .dir = legacy_user_dir },
        .{ .location = .resources, .dir = resources_dir },
    });
    defer freeList(std.testing.allocator, entries);

    try std.testing.expectEqual(@as(usize, 2), entries.len);
    var found_user = false;
    var found_legacy_user = false;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, "Dupe")) {
            try std.testing.expectEqual(Location.user, entry.location);
            found_user = true;
        } else if (std.mem.eql(u8, entry.name, "LegacyWins")) {
            try std.testing.expectEqual(Location.legacy_user, entry.location);
            found_legacy_user = true;
        }
    }
    try std.testing.expect(found_user);
    try std.testing.expect(found_legacy_user);
}

test "the theme list cache walks again only when a directory changed" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("user");
    (try tmp.dir.createFile("user/First", .{})).close();
    const user_dir = try tmp.dir.realpathAlloc(alloc, "user");
    defer alloc.free(user_dir);
    const root = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(root);
    const missing_dir = try std.fs.path.join(alloc, &.{ root, "resources" });
    defer alloc.free(missing_dir);
    const dirs = [_]Directory{
        .{ .location = .user, .dir = user_dir },
        .{ .location = .resources, .dir = missing_dir },
    };

    var cache: ListCache = .{};
    defer cache.deinit();

    const first = try cache.get(alloc, &dirs);
    defer freeList(alloc, first);
    const again = try cache.get(alloc, &dirs);
    defer freeList(alloc, again);
    try std.testing.expectEqual(@as(u32, 1), cache.rebuilds);
    try std.testing.expectEqual(@as(usize, 1), again.len);
    // An owned copy, not the cache's own memory.
    try std.testing.expect(first[0].name.ptr != again[0].name.ptr);

    // A new theme file changes its directory's time.
    (try tmp.dir.createFile("user/Second", .{})).close();
    const added = try cache.get(alloc, &dirs);
    defer freeList(alloc, added);
    try std.testing.expectEqual(@as(u32, 2), cache.rebuilds);
    try std.testing.expectEqual(@as(usize, 2), added.len);

    // A directory that appears counts as a change too.
    try tmp.dir.makePath("resources");
    (try tmp.dir.createFile("resources/Bundled", .{})).close();
    const appeared = try cache.get(alloc, &dirs);
    defer freeList(alloc, appeared);
    try std.testing.expectEqual(@as(u32, 3), cache.rebuilds);
    try std.testing.expectEqual(@as(usize, 3), appeared.len);
}

test "issue149 user theme locations prefer noctty before legacy ghostty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var it: LocationIterator = .{ .arena_alloc = arena.allocator() };
    const user = (try it.next()).?;
    try std.testing.expectEqual(Location.user, user.location);
    try std.testing.expectEqualStrings("themes", std.fs.path.basename(user.dir));
    try std.testing.expectEqualStrings(
        build_config.data_dir_name,
        std.fs.path.basename(std.fs.path.dirname(user.dir).?),
    );

    const legacy_user = (try it.next()).?;
    try std.testing.expectEqual(Location.legacy_user, legacy_user.location);
    try std.testing.expectEqualStrings("themes", std.fs.path.basename(legacy_user.dir));
    try std.testing.expectEqualStrings(
        "ghostty",
        std.fs.path.basename(std.fs.path.dirname(legacy_user.dir).?),
    );
}

test "a theme no directory has is one diagnostic that names every path tried" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diags: cli_diags.DiagnosticList = .{};
    const found = try open(arena.allocator(), "no-such-theme-pkg22", &diags);
    try std.testing.expect(found == null);

    // One misspelled name used to count as one problem per directory searched.
    try std.testing.expectEqual(@as(usize, 1), diags.items().len);
    const message = diags.items()[0].message;
    try std.testing.expect(std.mem.indexOf(u8, message, "theme \"no-such-theme-pkg22\" not found") != null);

    var it: LocationIterator = .{ .arena_alloc = arena.allocator() };
    while (try it.next()) |loc| {
        try std.testing.expect(std.mem.indexOf(u8, message, loc.dir) != null);
    }
}
