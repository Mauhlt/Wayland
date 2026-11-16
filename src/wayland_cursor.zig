//! libwayland-cursor: cursor images from the user's Xcursor theme (or the
//! library's small built-in set), as wl_shm buffers to show with
//! `wl_pointer.set_cursor`. For compositors without cursor-shape-v1.
//!
//! Opened with dlopen on `load()`; a machine without the library gets
//! `error.LibraryNotFound` and the client keeps the compositor's cursor.
//!
//!     try CURSOR.load();
//!     const theme = CURSOR.Theme.load(null, 24 * scale, shm) orelse return;
//!     const cur = theme.getCursor("left_ptr") orelse return;
//!     const img = cur.images[0];
//!     surface.attach(img.buffer(), 0, 0); ...
const std = @import("std");
const dl = @import("dl.zig");
const wl = @import("wayland_protocol.zig");

/// struct wl_cursor_image.
pub const Image = extern struct {
    width: u32,
    height: u32,
    hotspot_x: u32,
    hotspot_y: u32,
    /// Animation delay to the next image, milliseconds.
    delay: u32,

    /// The image's buffer (owned by the theme: never destroy it).
    pub fn buffer(self: *Image) ?*wl.Buffer {
        return api().wl_cursor_image_get_buffer.?(self);
    }
};

/// struct wl_cursor.
pub const Cursor = extern struct {
    image_count: c_uint,
    images: [*]*Image,
    name: [*:0]const u8,
};

/// struct wl_cursor_theme (opaque).
pub const Theme = opaque {
    /// `name` null: the default theme. `size`: pixels (e.g. 24 times the
    /// buffer scale). The cursors' buffers are made from `shm`.
    pub fn load(name: ?[*:0]const u8, size: i32, shm: *wl.Shm) ?*Theme {
        return api().wl_cursor_theme_load.?(name, size, shm);
    }
    pub fn destroy(self: *Theme) void {
        api().wl_cursor_theme_destroy.?(self);
    }
    /// An Xcursor name ("left_ptr", "top_side", ...); null if the theme
    /// has none.
    pub fn getCursor(self: *Theme, name: [*:0]const u8) ?*Cursor {
        return api().wl_cursor_theme_get_cursor.?(self, name);
    }
};

pub const Symbols = struct {
    wl_cursor_theme_load: ?*const fn (?[*:0]const u8, c_int, *wl.Shm) callconv(.c) ?*Theme,
    wl_cursor_theme_destroy: ?*const fn (*Theme) callconv(.c) void,
    wl_cursor_theme_get_cursor: ?*const fn (*Theme, [*:0]const u8) callconv(.c) ?*Cursor,
    wl_cursor_image_get_buffer: ?*const fn (*Image) callconv(.c) ?*wl.Buffer,
};

var symbols: ?Symbols = null;

/// Opens libwayland-cursor.so.0. Safe to call more than once.
pub fn load() error{ LibraryNotFound, MissingSymbol }!void {
    if (symbols != null) return;
    const lib = try dl.Library.open(&.{ "libwayland-cursor.so.0", "libwayland-cursor.so" });
    const syms = lib.loadAll(Symbols);
    if (dl.firstMissing(syms, &.{})) |name| {
        std.log.scoped(.wayland).err("libwayland-cursor is missing {s}", .{name});
        lib.close();
        return error.MissingSymbol;
    }
    symbols = syms;
}

pub fn isLoaded() bool {
    return symbols != null;
}

/// Loaded symbols. Asserts `load()` succeeded.
pub fn api() *const Symbols {
    return &(symbols orelse @panic("Wayland: call CURSOR.load() first"));
}
