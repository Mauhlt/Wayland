//! Runtime library loading (dlopen / dlsym).
//!
//! Symbols are looked up into a struct of optional function pointers whose field names are the
//! C symbol names, so a missing symbol is a null field instead of a failed program start.
const std = @import("std");

pub const Library = struct {
    handle: *anyopaque,

    /// Tries each name in order (e.g. "libfoo.so.0", then "libfoo.so").
    pub fn open(names: []const [*:0]const u8) error{LibraryNotFound}!Library {
        for (names) |name| {
            if (std.c.dlopen(name, .{ .NOW = true })) |h| return .{ .handle = h };
        }
        return error.LibraryNotFound;
    }

    pub fn close(self: Library) void {
        _ = std.c.dlclose(self.handle);
    }

    /// Looks up one symbol as `T` (a pointer type). Null if missing.
    pub fn lookup(self: Library, comptime T: type, name: [*:0]const u8) ?T {
        const p = std.c.dlsym(self.handle, name) orelse return null;
        return @ptrCast(@alignCast(p));
    }

    /// Fills every `?*const fn` field of `Syms` from the field's name.
    pub fn loadAll(self: Library, comptime Syms: type) Syms {
        var out: Syms = undefined;
        const info = @typeInfo(Syms).@"struct";
        inline for (info.field_names, info.field_types) |name, T| {
            @field(out, name) = self.lookup(@typeInfo(T).optional.child, name);
        }
        return out;
    }
};

/// Returns the name of the first null field of `syms` that is not listed in `optional`.
pub fn firstMissing(syms: anytype, comptime optional: []const []const u8) ?[]const u8 {
    inline for (@typeInfo(@TypeOf(syms)).@"struct".field_names) |name| {
        const is_optional = comptime blk: {
            for (optional) |o| if (std.mem.eql(u8, o, name)) break :blk true;
            break :blk false;
        };
        if (!is_optional and @field(syms, name) == null) return name;
    }
    return null;
}
