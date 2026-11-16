//! cursor-shape-v1 (staging): ask the compositor to draw a named cursor
//! (no cursor theme or buffers in the client).
//!
//! Not every compositor offers it (Weston, so WSLg, does not); without
//! `wp_cursor_shape_manager_v1` a client sets cursor images itself, e.g.
//! from a cursor theme through `CURSOR` (libwayland-cursor).
const c = @import("wayland_client.zig");
const wl = @import("wayland_protocol.zig");
const Argument = c.Argument;
const Interface = c.Interface;
const msg = c.msg;

pub const wp_cursor_shape_manager_v1_interface: Interface = .init("wp_cursor_shape_manager_v1", 1, &.{
    msg("destroy", "", &.{}),
    msg("get_pointer", "no", &.{ &wp_cursor_shape_device_v1_interface, &wl.wl_pointer_interface }),
    // The tablet tool's interface (tablet-v2) is not bound here.
    msg("get_tablet_tool_v2", "no", &.{ &wp_cursor_shape_device_v1_interface, null }),
}, &.{});

pub const wp_cursor_shape_device_v1_interface: Interface = .init("wp_cursor_shape_device_v1", 1, &.{
    msg("destroy", "", &.{}),
    msg("set_shape", "uu", &.{ null, null }),
}, &.{});

pub const Manager = opaque {
    pub const interface = wp_cursor_shape_manager_v1_interface;
    pub const Event = noreturn;

    pub fn destroy(self: *Manager) void {
        c.requestDestroy(self, 0, &.{});
    }
    /// The shape device of `pointer` (one per wl_pointer).
    pub fn getPointer(self: *Manager, pointer: *wl.Pointer) error{OutOfMemory}!*Device {
        return c.requestNew(Device, self, 1, &.{ Argument.new_id, .object(pointer) });
    }
};

pub const Device = opaque {
    pub const interface = wp_cursor_shape_device_v1_interface;
    pub const Event = noreturn;

    /// wp_cursor_shape_device_v1.shape (CSS cursor names), version 1.
    pub const Shape = enum(u32) {
        default = 1,
        context_menu = 2,
        help = 3,
        pointer = 4,
        progress = 5,
        wait = 6,
        cell = 7,
        crosshair = 8,
        text = 9,
        vertical_text = 10,
        alias = 11,
        copy = 12,
        move = 13,
        no_drop = 14,
        not_allowed = 15,
        grab = 16,
        grabbing = 17,
        e_resize = 18,
        n_resize = 19,
        ne_resize = 20,
        nw_resize = 21,
        s_resize = 22,
        se_resize = 23,
        sw_resize = 24,
        w_resize = 25,
        ew_resize = 26,
        ns_resize = 27,
        nesw_resize = 28,
        nwse_resize = 29,
        col_resize = 30,
        row_resize = 31,
        all_scroll = 32,
        zoom_in = 33,
        zoom_out = 34,
        _,
    };

    pub fn destroy(self: *Device) void {
        c.requestDestroy(self, 0, &.{});
    }
    /// `serial`: of the latest wl_pointer.enter.
    pub fn setShape(self: *Device, serial: u32, shape: Shape) void {
        c.request(self, 1, &.{ .uint(serial), .uint(@backingInt(shape)) });
    }
};
