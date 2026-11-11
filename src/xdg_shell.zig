//! xdg-shell (stable): turning a wl_surface into a desktop window.
//!
//!     wm_base = registry.bind(name, XDG.WmBase, 6)   // answer `ping` with `pong`!
//!     xdg_surface = wm_base.getXdgSurface(surface)
//!     toplevel = xdg_surface.getToplevel()
//!     surface.commit()  -> wait for xdg_surface `configure`, `ackConfigure(serial)`, then render.
const c = @import("wayland_client.zig");
const wl = @import("wayland_protocol.zig");
const Argument = c.Argument;
const Interface = c.Interface;
const msg = c.msg;

// ---------------------------------------------------------------------------
// Interface tables
// ---------------------------------------------------------------------------
pub const xdg_wm_base_interface: Interface = .init("xdg_wm_base", 6, &.{
    msg("destroy", "", &.{}),
    msg("create_positioner", "n", &.{&xdg_positioner_interface}),
    msg("get_xdg_surface", "no", &.{ &xdg_surface_interface, &wl.wl_surface_interface }),
    msg("pong", "u", &.{null}),
}, &.{
    msg("ping", "u", &.{null}),
});

pub const xdg_positioner_interface: Interface = .init("xdg_positioner", 6, &.{
    msg("destroy", "", &.{}),
    msg("set_size", "ii", &.{ null, null }),
    msg("set_anchor_rect", "iiii", &.{ null, null, null, null }),
    msg("set_anchor", "u", &.{null}),
    msg("set_gravity", "u", &.{null}),
    msg("set_constraint_adjustment", "u", &.{null}),
    msg("set_offset", "ii", &.{ null, null }),
    msg("set_reactive", "3", &.{}),
    msg("set_parent_size", "3ii", &.{ null, null }),
    msg("set_parent_configure", "3u", &.{null}),
}, &.{});

pub const xdg_surface_interface: Interface = .init("xdg_surface", 6, &.{
    msg("destroy", "", &.{}),
    msg("get_toplevel", "n", &.{&xdg_toplevel_interface}),
    msg("get_popup", "n?oo", &.{ &xdg_popup_interface, &xdg_surface_interface, &xdg_positioner_interface }),
    msg("set_window_geometry", "iiii", &.{ null, null, null, null }),
    msg("ack_configure", "u", &.{null}),
}, &.{
    msg("configure", "u", &.{null}),
});

pub const xdg_toplevel_interface: Interface = .init("xdg_toplevel", 6, &.{
    msg("destroy", "", &.{}),
    msg("set_parent", "?o", &.{&xdg_toplevel_interface}),
    msg("set_title", "s", &.{null}),
    msg("set_app_id", "s", &.{null}),
    msg("show_window_menu", "ouii", &.{ &wl.wl_seat_interface, null, null, null }),
    msg("move", "ou", &.{ &wl.wl_seat_interface, null }),
    msg("resize", "ouu", &.{ &wl.wl_seat_interface, null, null }),
    msg("set_max_size", "ii", &.{ null, null }),
    msg("set_min_size", "ii", &.{ null, null }),
    msg("set_maximized", "", &.{}),
    msg("unset_maximized", "", &.{}),
    msg("set_fullscreen", "?o", &.{&wl.wl_output_interface}),
    msg("unset_fullscreen", "", &.{}),
    msg("set_minimized", "", &.{}),
}, &.{
    msg("configure", "iia", &.{ null, null, null }),
    msg("close", "", &.{}),
    msg("configure_bounds", "4ii", &.{ null, null }),
    msg("wm_capabilities", "5a", &.{null}),
});

pub const xdg_popup_interface: Interface = .init("xdg_popup", 6, &.{
    msg("destroy", "", &.{}),
    msg("grab", "ou", &.{ &wl.wl_seat_interface, null }),
    msg("reposition", "3ou", &.{ &xdg_positioner_interface, null }),
}, &.{
    msg("configure", "iiii", &.{ null, null, null, null }),
    msg("popup_done", "", &.{}),
    msg("repositioned", "3u", &.{null}),
});

// ---------------------------------------------------------------------------
// Typed objects
// ---------------------------------------------------------------------------

pub const WmBase = opaque {
    pub const interface = xdg_wm_base_interface;

    pub const Event = union(enum) {
        /// Reply with `pong(serial)` or the compositor may consider the client hung.
        ping: struct { serial: u32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return if (opcode == 0) .{ .ping = .{ .serial = a[0].u } } else null;
    }
    pub fn setListener(self: *WmBase, comptime Data: type, comptime cb: fn (*WmBase, Event, Data) void, data: Data) void {
        c.setListener(WmBase, self, Data, cb, data);
    }

    pub fn destroy(self: *WmBase) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn createPositioner(self: *WmBase) error{OutOfMemory}!*Positioner {
        return c.requestNew(Positioner, self, 1, &.{Argument.new_id});
    }
    pub fn getXdgSurface(self: *WmBase, surface: *wl.Surface) error{OutOfMemory}!*Surface {
        return c.requestNew(Surface, self, 2, &.{ Argument.new_id, .object(surface) });
    }
    pub fn pong(self: *WmBase, serial: u32) void {
        c.request(self, 3, &.{.uint(serial)});
    }
};

/// Placement rules for popups (menus, tooltips).
pub const Positioner = opaque {
    pub const interface = xdg_positioner_interface;
    pub const Event = noreturn;

    pub fn destroy(self: *Positioner) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn setSize(self: *Positioner, w: i32, h: i32) void {
        c.request(self, 1, &.{ .int(w), .int(h) });
    }
    pub fn setAnchorRect(self: *Positioner, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 2, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
    /// xdg_positioner.anchor: none 0, top 1, bottom 2, left 3, right 4, top_left 5, bottom_left 6, top_right 7, bottom_right 8.
    pub fn setAnchor(self: *Positioner, anchor: u32) void {
        c.request(self, 3, &.{.uint(anchor)});
    }
    /// Same values as `setAnchor`.
    pub fn setGravity(self: *Positioner, gravity: u32) void {
        c.request(self, 4, &.{.uint(gravity)});
    }
    /// Bits: slide_x 1, slide_y 2, flip_x 4, flip_y 8, resize_x 16, resize_y 32.
    pub fn setConstraintAdjustment(self: *Positioner, adjustment: u32) void {
        c.request(self, 5, &.{.uint(adjustment)});
    }
    pub fn setOffset(self: *Positioner, x: i32, y: i32) void {
        c.request(self, 6, &.{ .int(x), .int(y) });
    }
};

/// xdg_surface: the role-independent part of a desktop surface.
pub const Surface = opaque {
    pub const interface = xdg_surface_interface;

    pub const Event = union(enum) {
        /// End of a configure sequence: apply pending state, `ackConfigure(serial)`, commit.
        configure: struct { serial: u32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return if (opcode == 0) .{ .configure = .{ .serial = a[0].u } } else null;
    }
    pub fn setListener(self: *Surface, comptime Data: type, comptime cb: fn (*Surface, Event, Data) void, data: Data) void {
        c.setListener(Surface, self, Data, cb, data);
    }

    pub fn destroy(self: *Surface) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn getToplevel(self: *Surface) error{OutOfMemory}!*Toplevel {
        return c.requestNew(Toplevel, self, 1, &.{Argument.new_id});
    }
    pub fn getPopup(self: *Surface, parent: ?*Surface, positioner: *Positioner) error{OutOfMemory}!*Popup {
        return c.requestNew(Popup, self, 2, &.{ Argument.new_id, .object(parent), .object(positioner) });
    }
    /// The visible window area, excluding client-side shadows.
    pub fn setWindowGeometry(self: *Surface, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 3, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
    pub fn ackConfigure(self: *Surface, serial: u32) void {
        c.request(self, 4, &.{.uint(serial)});
    }
};

/// xdg_toplevel: a regular window.
pub const Toplevel = opaque {
    pub const interface = xdg_toplevel_interface;

    pub const State = enum(u32) {
        maximized = 1,
        fullscreen = 2,
        resizing = 3,
        activated = 4,
        tiled_left = 5,
        tiled_right = 6,
        tiled_top = 7,
        tiled_bottom = 8,
        suspended = 9,
        _,
    };
    pub const States = struct {
        maximized: bool = false,
        fullscreen: bool = false,
        resizing: bool = false,
        activated: bool = false,
        tiled: bool = false,
        /// v6: the window is not visible; stop rendering.
        suspended: bool = false,

        pub fn fromArray(array: *const c.Array) States {
            var s: States = .{};
            for (array.slice(u32)) |raw| switch (@as(State, @enumFromInt(raw))) {
                .maximized => s.maximized = true,
                .fullscreen => s.fullscreen = true,
                .resizing => s.resizing = true,
                .activated => s.activated = true,
                .tiled_left, .tiled_right, .tiled_top, .tiled_bottom => s.tiled = true,
                .suspended => s.suspended = true,
                _ => {},
            };
            return s;
        }
    };
    pub const ResizeEdge = enum(u32) {
        none = 0,
        top = 1,
        bottom = 2,
        left = 4,
        top_left = 5,
        bottom_left = 6,
        right = 8,
        top_right = 9,
        bottom_right = 10,
    };

    pub const Event = union(enum) {
        /// 0 x 0 = pick your own size. Followed by xdg_surface `configure`.
        configure: struct { width: i32, height: i32, states: States },
        /// The user asked to close the window.
        close,
        /// v4: suggested maximum size (e.g. the work area).
        configure_bounds: struct { width: i32, height: i32 },
        /// v5: window-menu / maximize / fullscreen / minimize support, as an array of u32.
        wm_capabilities: *c.Array,
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .configure = .{ .width = a[0].i, .height = a[1].i, .states = .fromArray(a[2].a.?) } },
            1 => .close,
            2 => .{ .configure_bounds = .{ .width = a[0].i, .height = a[1].i } },
            3 => .{ .wm_capabilities = a[0].a.? },
            else => null,
        };
    }
    pub fn setListener(self: *Toplevel, comptime Data: type, comptime cb: fn (*Toplevel, Event, Data) void, data: Data) void {
        c.setListener(Toplevel, self, Data, cb, data);
    }

    pub fn destroy(self: *Toplevel) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn setParent(self: *Toplevel, parent: ?*Toplevel) void {
        c.request(self, 1, &.{.object(parent)});
    }
    pub fn setTitle(self: *Toplevel, title: [*:0]const u8) void {
        c.request(self, 2, &.{.string(title)});
    }
    /// Desktop-file id, e.g. "com.example.renderer".
    pub fn setAppId(self: *Toplevel, app_id: [*:0]const u8) void {
        c.request(self, 3, &.{.string(app_id)});
    }
    pub fn showWindowMenu(self: *Toplevel, seat: *wl.Seat, serial: u32, x: i32, y: i32) void {
        c.request(self, 4, &.{ .object(seat), .uint(serial), .int(x), .int(y) });
    }
    /// Start an interactive move (call from a pointer button press; `serial` from that event).
    pub fn move(self: *Toplevel, seat: *wl.Seat, serial: u32) void {
        c.request(self, 5, &.{ .object(seat), .uint(serial) });
    }
    pub fn resize(self: *Toplevel, seat: *wl.Seat, serial: u32, edges: ResizeEdge) void {
        c.request(self, 6, &.{ .object(seat), .uint(serial), .uint(@backingInt(edges)) });
    }
    /// 0 = no limit.
    pub fn setMaxSize(self: *Toplevel, w: i32, h: i32) void {
        c.request(self, 7, &.{ .int(w), .int(h) });
    }
    pub fn setMinSize(self: *Toplevel, w: i32, h: i32) void {
        c.request(self, 8, &.{ .int(w), .int(h) });
    }
    pub fn setMaximized(self: *Toplevel) void {
        c.request(self, 9, &.{});
    }
    pub fn unsetMaximized(self: *Toplevel) void {
        c.request(self, 10, &.{});
    }
    /// `output` null = the compositor picks.
    pub fn setFullscreen(self: *Toplevel, output: ?*wl.Output) void {
        c.request(self, 11, &.{.object(output)});
    }
    pub fn unsetFullscreen(self: *Toplevel) void {
        c.request(self, 12, &.{});
    }
    pub fn setMinimized(self: *Toplevel) void {
        c.request(self, 13, &.{});
    }
};

pub const Popup = opaque {
    pub const interface = xdg_popup_interface;

    pub const Event = union(enum) {
        configure: struct { x: i32, y: i32, width: i32, height: i32 },
        popup_done,
        repositioned: struct { token: u32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .configure = .{ .x = a[0].i, .y = a[1].i, .width = a[2].i, .height = a[3].i } },
            1 => .popup_done,
            2 => .{ .repositioned = .{ .token = a[0].u } },
            else => null,
        };
    }
    pub fn setListener(self: *Popup, comptime Data: type, comptime cb: fn (*Popup, Event, Data) void, data: Data) void {
        c.setListener(Popup, self, Data, cb, data);
    }
    pub fn destroy(self: *Popup) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn grab(self: *Popup, seat: *wl.Seat, serial: u32) void {
        c.request(self, 1, &.{ .object(seat), .uint(serial) });
    }
};
