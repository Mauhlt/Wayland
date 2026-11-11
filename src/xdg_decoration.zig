//! xdg-decoration (unstable v1): ask the compositor to draw the title bar and borders.
//!
//! Not every compositor offers it (GNOME/Mutter does not); when `zxdg_decoration_manager_v1`
//! is missing from the registry, the window has no decorations unless the client draws them.
const c = @import("wayland_client.zig");
const xdg = @import("xdg_shell.zig");
const Argument = c.Argument;
const Interface = c.Interface;
const msg = c.msg;

pub const zxdg_decoration_manager_v1_interface: Interface = .init("zxdg_decoration_manager_v1", 1, &.{
    msg("destroy", "", &.{}),
    msg("get_toplevel_decoration", "no", &.{ &zxdg_toplevel_decoration_v1_interface, &xdg.xdg_toplevel_interface }),
}, &.{});

pub const zxdg_toplevel_decoration_v1_interface: Interface = .init("zxdg_toplevel_decoration_v1", 1, &.{
    msg("destroy", "", &.{}),
    msg("set_mode", "u", &.{null}),
    msg("unset_mode", "", &.{}),
}, &.{
    msg("configure", "u", &.{null}),
});

pub const Manager = opaque {
    pub const interface = zxdg_decoration_manager_v1_interface;
    pub const Event = noreturn;

    pub fn destroy(self: *Manager) void {
        c.requestDestroy(self, 0, &.{});
    }
    /// Call before the toplevel's first commit.
    pub fn getToplevelDecoration(self: *Manager, toplevel: *xdg.Toplevel) error{OutOfMemory}!*ToplevelDecoration {
        return c.requestNew(ToplevelDecoration, self, 1, &.{ Argument.new_id, .object(toplevel) });
    }
};

pub const ToplevelDecoration = opaque {
    pub const interface = zxdg_toplevel_decoration_v1_interface;

    pub const Mode = enum(u32) {
        client_side = 1,
        server_side = 2,
        _,
    };
    pub const Event = union(enum) {
        /// The mode the compositor chose; draw your own decorations for `.client_side`.
        configure: struct { mode: Mode },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return if (opcode == 0) .{ .configure = .{ .mode = @enumFromInt(a[0].u) } } else null;
    }
    pub fn setListener(self: *ToplevelDecoration, comptime Data: type, comptime cb: fn (*ToplevelDecoration, Event, Data) void, data: Data) void {
        c.setListener(ToplevelDecoration, self, Data, cb, data);
    }

    pub fn destroy(self: *ToplevelDecoration) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn setMode(self: *ToplevelDecoration, mode: Mode) void {
        c.request(self, 1, &.{.uint(@backingInt(mode))});
    }
    pub fn unsetMode(self: *ToplevelDecoration) void {
        c.request(self, 2, &.{});
    }
};
