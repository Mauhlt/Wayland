//! Core Wayland protocol (wayland.xml): the objects a renderer needs.
//!
//! Interface tables are defined here instead of using libwayland's exported data symbols, so the
//! protocol description is checked at compile time and nothing extra is resolved at runtime.
//! Each object is an opaque proxy with request methods, an `Event` union and `setListener`:
//!
//!     registry.setListener(*App, onRegistry, app);
//!     fn onRegistry(r: *WL.Registry, ev: WL.Registry.Event, app: *App) void { ... }
const c = @import("wayland_client.zig");
const Argument = c.Argument;
const Fixed = c.Fixed;
const Array = c.Array;
const Interface = c.Interface;
const msg = c.msg;

/// The connection (also the wl_display object). See `CLIENT.Display`.
pub const Display = c.Display;
pub const EventQueue = c.EventQueue;

// ---------------------------------------------------------------------------
// Interface tables (requests and events in protocol order)
// ---------------------------------------------------------------------------
pub const wl_display_interface: Interface = .init("wl_display", 1, &.{
    msg("sync", "n", &.{&wl_callback_interface}),
    msg("get_registry", "n", &.{&wl_registry_interface}),
}, &.{
    msg("error", "ous", &.{ null, null, null }),
    msg("delete_id", "u", &.{null}),
});

pub const wl_registry_interface: Interface = .init("wl_registry", 1, &.{
    msg("bind", "usun", &.{ null, null, null, null }),
}, &.{
    msg("global", "usu", &.{ null, null, null }),
    msg("global_remove", "u", &.{null}),
});

pub const wl_callback_interface: Interface = .init("wl_callback", 1, &.{}, &.{
    msg("done", "u", &.{null}),
});

pub const wl_compositor_interface: Interface = .init("wl_compositor", 6, &.{
    msg("create_surface", "n", &.{&wl_surface_interface}),
    msg("create_region", "n", &.{&wl_region_interface}),
}, &.{});

pub const wl_buffer_interface: Interface = .init("wl_buffer", 1, &.{
    msg("destroy", "", &.{}),
}, &.{
    msg("release", "", &.{}),
});

pub const wl_surface_interface: Interface = .init("wl_surface", 6, &.{
    msg("destroy", "", &.{}),
    msg("attach", "?oii", &.{ &wl_buffer_interface, null, null }),
    msg("damage", "iiii", &.{ null, null, null, null }),
    msg("frame", "n", &.{&wl_callback_interface}),
    msg("set_opaque_region", "?o", &.{&wl_region_interface}),
    msg("set_input_region", "?o", &.{&wl_region_interface}),
    msg("commit", "", &.{}),
    msg("set_buffer_transform", "2i", &.{null}),
    msg("set_buffer_scale", "3i", &.{null}),
    msg("damage_buffer", "4iiii", &.{ null, null, null, null }),
    msg("offset", "5ii", &.{ null, null }),
}, &.{
    msg("enter", "o", &.{&wl_output_interface}),
    msg("leave", "o", &.{&wl_output_interface}),
    msg("preferred_buffer_scale", "6i", &.{null}),
    msg("preferred_buffer_transform", "6u", &.{null}),
});

pub const wl_region_interface: Interface = .init("wl_region", 1, &.{
    msg("destroy", "", &.{}),
    msg("add", "iiii", &.{ null, null, null, null }),
    msg("subtract", "iiii", &.{ null, null, null, null }),
}, &.{});

pub const wl_seat_interface: Interface = .init("wl_seat", 9, &.{
    msg("get_pointer", "n", &.{&wl_pointer_interface}),
    msg("get_keyboard", "n", &.{&wl_keyboard_interface}),
    msg("get_touch", "n", &.{&wl_touch_interface}),
    msg("release", "5", &.{}),
}, &.{
    msg("capabilities", "u", &.{null}),
    msg("name", "2s", &.{null}),
});

pub const wl_pointer_interface: Interface = .init("wl_pointer", 9, &.{
    msg("set_cursor", "u?oii", &.{ null, &wl_surface_interface, null, null }),
    msg("release", "3", &.{}),
}, &.{
    msg("enter", "uoff", &.{ null, &wl_surface_interface, null, null }),
    msg("leave", "uo", &.{ null, &wl_surface_interface }),
    msg("motion", "uff", &.{ null, null, null }),
    msg("button", "uuuu", &.{ null, null, null, null }),
    msg("axis", "uuf", &.{ null, null, null }),
    msg("frame", "5", &.{}),
    msg("axis_source", "5u", &.{null}),
    msg("axis_stop", "5uu", &.{ null, null }),
    msg("axis_discrete", "5ui", &.{ null, null }),
    msg("axis_value120", "8ui", &.{ null, null }),
    msg("axis_relative_direction", "9uu", &.{ null, null }),
});

pub const wl_keyboard_interface: Interface = .init("wl_keyboard", 9, &.{
    msg("release", "3", &.{}),
}, &.{
    msg("keymap", "uhu", &.{ null, null, null }),
    msg("enter", "uoa", &.{ null, &wl_surface_interface, null }),
    msg("leave", "uo", &.{ null, &wl_surface_interface }),
    msg("key", "uuuu", &.{ null, null, null, null }),
    msg("modifiers", "uuuuu", &.{ null, null, null, null, null }),
    msg("repeat_info", "4ii", &.{ null, null }),
});

pub const wl_touch_interface: Interface = .init("wl_touch", 9, &.{
    msg("release", "3", &.{}),
}, &.{
    msg("down", "uuoiff", &.{ null, null, &wl_surface_interface, null, null, null }),
    msg("up", "uui", &.{ null, null, null }),
    msg("motion", "uiff", &.{ null, null, null, null }),
    msg("frame", "", &.{}),
    msg("cancel", "", &.{}),
    msg("shape", "6iff", &.{ null, null, null }),
    msg("orientation", "6if", &.{ null, null }),
});

pub const wl_output_interface: Interface = .init("wl_output", 4, &.{
    msg("release", "3", &.{}),
}, &.{
    msg("geometry", "iiiiissi", &.{ null, null, null, null, null, null, null, null }),
    msg("mode", "uiii", &.{ null, null, null, null }),
    msg("done", "2", &.{}),
    msg("scale", "2i", &.{null}),
    msg("name", "4s", &.{null}),
    msg("description", "4s", &.{null}),
});

// ---------------------------------------------------------------------------
// Typed objects
// ---------------------------------------------------------------------------

/// wl_registry: announces globals; bind the ones you need.
pub const Registry = opaque {
    pub const interface = wl_registry_interface;

    pub const Event = union(enum) {
        global: struct { name: u32, interface: [*:0]const u8, version: u32 },
        global_remove: struct { name: u32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .global = .{ .name = a[0].u, .interface = a[1].s.?, .version = a[2].u } },
            1 => .{ .global_remove = .{ .name = a[0].u } },
            else => null,
        };
    }
    pub fn setListener(self: *Registry, comptime Data: type, comptime cb: fn (*Registry, Event, Data) void, data: Data) void {
        c.setListener(Registry, self, Data, cb, data);
    }

    /// Binds global `name` as `T`, at `min(version, T.interface.version)`.
    pub fn bind(self: *Registry, name: u32, comptime T: type, version: u32) error{OutOfMemory}!*T {
        const v = @min(version, @as(u32, @intCast(T.interface.version)));
        return c.requestNewVersioned(T, self, 0, &.{
            .uint(name), .string(T.interface.name), .uint(v), Argument.new_id,
        }, v);
    }
    pub fn destroy(self: *Registry) void {
        c.destroyProxy(self);
    }
};

/// wl_callback: one-shot `done` (frame callbacks, wl_display.sync).
pub const Callback = opaque {
    pub const interface = wl_callback_interface;

    pub const Event = union(enum) {
        /// For frame callbacks: the frame time in milliseconds.
        done: struct { data: u32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return if (opcode == 0) .{ .done = .{ .data = a[0].u } } else null;
    }
    pub fn setListener(self: *Callback, comptime Data: type, comptime cb: fn (*Callback, Event, Data) void, data: Data) void {
        c.setListener(Callback, self, Data, cb, data);
    }
    pub fn destroy(self: *Callback) void {
        c.destroyProxy(self);
    }
};

pub const Compositor = opaque {
    pub const interface = wl_compositor_interface;
    pub const Event = noreturn;

    pub fn createSurface(self: *Compositor) error{OutOfMemory}!*Surface {
        return c.requestNew(Surface, self, 0, &.{Argument.new_id});
    }
    pub fn createRegion(self: *Compositor) error{OutOfMemory}!*Region {
        return c.requestNew(Region, self, 1, &.{Argument.new_id});
    }
    pub fn destroy(self: *Compositor) void {
        c.destroyProxy(self);
    }
};

/// Opaque here: Vulkan presents through the surface, not wl_buffer.
pub const Buffer = opaque {
    pub const interface = wl_buffer_interface;

    pub const Event = union(enum) { release };
    pub fn decodeEvent(opcode: u32, _: [*]Argument) ?Event {
        return if (opcode == 0) .release else null;
    }
    pub fn setListener(self: *Buffer, comptime Data: type, comptime cb: fn (*Buffer, Event, Data) void, data: Data) void {
        c.setListener(Buffer, self, Data, cb, data);
    }
    pub fn destroy(self: *Buffer) void {
        c.requestDestroy(self, 0, &.{});
    }
};

/// wl_output.transform.
pub const Transform = enum(i32) {
    normal = 0,
    @"90" = 1,
    @"180" = 2,
    @"270" = 3,
    flipped = 4,
    flipped_90 = 5,
    flipped_180 = 6,
    flipped_270 = 7,
    _,
};

/// wl_surface: what Vulkan (VK_KHR_wayland_surface) renders into.
pub const Surface = opaque {
    pub const interface = wl_surface_interface;

    pub const Event = union(enum) {
        enter: struct { output: ?*Output },
        leave: struct { output: ?*Output },
        /// v6: scale the compositor would like buffers rendered at.
        preferred_buffer_scale: struct { factor: i32 },
        /// v6.
        preferred_buffer_transform: struct { transform: Transform },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .enter = .{ .output = c.argObject(Output, a[0]) } },
            1 => .{ .leave = .{ .output = c.argObject(Output, a[0]) } },
            2 => .{ .preferred_buffer_scale = .{ .factor = a[0].i } },
            3 => .{ .preferred_buffer_transform = .{ .transform = @enumFromInt(@as(i32, @bitCast(a[0].u))) } },
            else => null,
        };
    }
    pub fn setListener(self: *Surface, comptime Data: type, comptime cb: fn (*Surface, Event, Data) void, data: Data) void {
        c.setListener(Surface, self, Data, cb, data);
    }

    pub fn destroy(self: *Surface) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn attach(self: *Surface, buffer: ?*Buffer, x: i32, y: i32) void {
        c.request(self, 1, &.{ .object(buffer), .int(x), .int(y) });
    }
    /// Surface-local coordinates. Prefer `damageBuffer` (v4).
    pub fn damage(self: *Surface, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 2, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
    /// Request a frame callback; its `done` fires when it's a good time to draw the next frame.
    pub fn frame(self: *Surface) error{OutOfMemory}!*Callback {
        return c.requestNew(Callback, self, 3, &.{Argument.new_id});
    }
    pub fn setOpaqueRegion(self: *Surface, region: ?*Region) void {
        c.request(self, 4, &.{.object(region)});
    }
    pub fn setInputRegion(self: *Surface, region: ?*Region) void {
        c.request(self, 5, &.{.object(region)});
    }
    pub fn commit(self: *Surface) void {
        c.request(self, 6, &.{});
    }
    /// v2.
    pub fn setBufferTransform(self: *Surface, transform: Transform) void {
        c.request(self, 7, &.{.int(@backingInt(transform))});
    }
    /// v3. Integer HiDPI scale; render at size * scale.
    pub fn setBufferScale(self: *Surface, scale: i32) void {
        c.request(self, 8, &.{.int(scale)});
    }
    /// v4. Buffer coordinates.
    pub fn damageBuffer(self: *Surface, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 9, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
    /// v5.
    pub fn offset(self: *Surface, x: i32, y: i32) void {
        c.request(self, 10, &.{ .int(x), .int(y) });
    }
};

pub const Region = opaque {
    pub const interface = wl_region_interface;
    pub const Event = noreturn;

    pub fn destroy(self: *Region) void {
        c.requestDestroy(self, 0, &.{});
    }
    pub fn add(self: *Region, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 1, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
    pub fn subtract(self: *Region, x: i32, y: i32, w: i32, h: i32) void {
        c.request(self, 2, &.{ .int(x), .int(y), .int(w), .int(h) });
    }
};

/// wl_seat: a group of input devices.
pub const Seat = opaque {
    pub const interface = wl_seat_interface;

    pub const Capabilities = packed struct(u32) {
        pointer: bool = false,
        keyboard: bool = false,
        touch: bool = false,
        _r3: u29 = 0,
    };
    pub const Event = union(enum) {
        capabilities: Capabilities,
        /// v2.
        name: [*:0]const u8,
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .capabilities = @bitCast(a[0].u) },
            1 => .{ .name = a[0].s.? },
            else => null,
        };
    }
    pub fn setListener(self: *Seat, comptime Data: type, comptime cb: fn (*Seat, Event, Data) void, data: Data) void {
        c.setListener(Seat, self, Data, cb, data);
    }

    pub fn getPointer(self: *Seat) error{OutOfMemory}!*Pointer {
        return c.requestNew(Pointer, self, 0, &.{Argument.new_id});
    }
    pub fn getKeyboard(self: *Seat) error{OutOfMemory}!*Keyboard {
        return c.requestNew(Keyboard, self, 1, &.{Argument.new_id});
    }
    pub fn getTouch(self: *Seat) error{OutOfMemory}!*Touch {
        return c.requestNew(Touch, self, 2, &.{Argument.new_id});
    }
    /// Uses the v5 release request when available.
    pub fn release(self: *Seat) void {
        if (c.version(self) >= 5) c.requestDestroy(self, 3, &.{}) else c.destroyProxy(self);
    }
};

/// Linux input-event-codes for wl_pointer.button.
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;
pub const BTN_MIDDLE: u32 = 0x112;
pub const BTN_SIDE: u32 = 0x113;
pub const BTN_EXTRA: u32 = 0x114;

pub const Pointer = opaque {
    pub const interface = wl_pointer_interface;

    pub const ButtonState = enum(u32) { released = 0, pressed = 1, _ };
    pub const Axis = enum(u32) { vertical_scroll = 0, horizontal_scroll = 1, _ };
    pub const AxisSource = enum(u32) { wheel = 0, finger = 1, continuous = 2, wheel_tilt = 3, _ };
    pub const AxisRelativeDirection = enum(u32) { identical = 0, inverted = 1, _ };

    pub const Event = union(enum) {
        enter: struct { serial: u32, surface: ?*Surface, x: Fixed, y: Fixed },
        leave: struct { serial: u32, surface: ?*Surface },
        motion: struct { time: u32, x: Fixed, y: Fixed },
        /// `button` is a BTN_* code.
        button: struct { serial: u32, time: u32, button: u32, state: ButtonState },
        axis: struct { time: u32, axis: Axis, value: Fixed },
        /// v5: end of a group of events that belong together.
        frame,
        axis_source: AxisSource,
        axis_stop: struct { time: u32, axis: Axis },
        axis_discrete: struct { axis: Axis, discrete: i32 },
        /// v8: 120 = one wheel detent.
        axis_value120: struct { axis: Axis, value120: i32 },
        axis_relative_direction: struct { axis: Axis, direction: AxisRelativeDirection },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .enter = .{ .serial = a[0].u, .surface = c.argObject(Surface, a[1]), .x = a[2].f, .y = a[3].f } },
            1 => .{ .leave = .{ .serial = a[0].u, .surface = c.argObject(Surface, a[1]) } },
            2 => .{ .motion = .{ .time = a[0].u, .x = a[1].f, .y = a[2].f } },
            3 => .{ .button = .{ .serial = a[0].u, .time = a[1].u, .button = a[2].u, .state = @enumFromInt(a[3].u) } },
            4 => .{ .axis = .{ .time = a[0].u, .axis = @enumFromInt(a[1].u), .value = a[2].f } },
            5 => .frame,
            6 => .{ .axis_source = @enumFromInt(a[0].u) },
            7 => .{ .axis_stop = .{ .time = a[0].u, .axis = @enumFromInt(a[1].u) } },
            8 => .{ .axis_discrete = .{ .axis = @enumFromInt(a[0].u), .discrete = a[1].i } },
            9 => .{ .axis_value120 = .{ .axis = @enumFromInt(a[0].u), .value120 = a[1].i } },
            10 => .{ .axis_relative_direction = .{ .axis = @enumFromInt(a[0].u), .direction = @enumFromInt(a[1].u) } },
            else => null,
        };
    }
    pub fn setListener(self: *Pointer, comptime Data: type, comptime cb: fn (*Pointer, Event, Data) void, data: Data) void {
        c.setListener(Pointer, self, Data, cb, data);
    }

    /// `surface` null hides the cursor. `serial` is from the latest `enter`.
    pub fn setCursor(self: *Pointer, serial: u32, surface: ?*Surface, hotspot_x: i32, hotspot_y: i32) void {
        c.request(self, 0, &.{ .uint(serial), .object(surface), .int(hotspot_x), .int(hotspot_y) });
    }
    pub fn release(self: *Pointer) void {
        if (c.version(self) >= 3) c.requestDestroy(self, 1, &.{}) else c.destroyProxy(self);
    }
};

pub const Keyboard = opaque {
    pub const interface = wl_keyboard_interface;

    pub const KeymapFormat = enum(u32) { no_keymap = 0, xkb_v1 = 1, _ };
    pub const KeyState = enum(u32) { released = 0, pressed = 1, repeated = 2, _ };

    pub const Event = union(enum) {
        /// mmap `fd` (MAP_PRIVATE, `size` bytes), compile with XKB, then close `fd`.
        keymap: struct { format: KeymapFormat, fd: i32, size: u32 },
        enter: struct { serial: u32, surface: ?*Surface, keys: *Array },
        leave: struct { serial: u32, surface: ?*Surface },
        /// `key` is an evdev code; add 8 for an XKB keycode.
        key: struct { serial: u32, time: u32, key: u32, state: KeyState },
        modifiers: struct { serial: u32, depressed: u32, latched: u32, locked: u32, group: u32 },
        /// v4: `rate` keys/sec (0 = no repeat), `delay` ms.
        repeat_info: struct { rate: i32, delay: i32 },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .keymap = .{ .format = @enumFromInt(a[0].u), .fd = a[1].h, .size = a[2].u } },
            1 => .{ .enter = .{ .serial = a[0].u, .surface = c.argObject(Surface, a[1]), .keys = a[2].a.? } },
            2 => .{ .leave = .{ .serial = a[0].u, .surface = c.argObject(Surface, a[1]) } },
            3 => .{ .key = .{ .serial = a[0].u, .time = a[1].u, .key = a[2].u, .state = @enumFromInt(a[3].u) } },
            4 => .{ .modifiers = .{ .serial = a[0].u, .depressed = a[1].u, .latched = a[2].u, .locked = a[3].u, .group = a[4].u } },
            5 => .{ .repeat_info = .{ .rate = a[0].i, .delay = a[1].i } },
            else => null,
        };
    }
    pub fn setListener(self: *Keyboard, comptime Data: type, comptime cb: fn (*Keyboard, Event, Data) void, data: Data) void {
        c.setListener(Keyboard, self, Data, cb, data);
    }
    pub fn release(self: *Keyboard) void {
        if (c.version(self) >= 3) c.requestDestroy(self, 0, &.{}) else c.destroyProxy(self);
    }
};

pub const Touch = opaque {
    pub const interface = wl_touch_interface;

    pub const Event = union(enum) {
        down: struct { serial: u32, time: u32, surface: ?*Surface, id: i32, x: Fixed, y: Fixed },
        up: struct { serial: u32, time: u32, id: i32 },
        motion: struct { time: u32, id: i32, x: Fixed, y: Fixed },
        frame,
        cancel,
        shape: struct { id: i32, major: Fixed, minor: Fixed },
        orientation: struct { id: i32, orientation: Fixed },
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .down = .{ .serial = a[0].u, .time = a[1].u, .surface = c.argObject(Surface, a[2]), .id = a[3].i, .x = a[4].f, .y = a[5].f } },
            1 => .{ .up = .{ .serial = a[0].u, .time = a[1].u, .id = a[2].i } },
            2 => .{ .motion = .{ .time = a[0].u, .id = a[1].i, .x = a[2].f, .y = a[3].f } },
            3 => .frame,
            4 => .cancel,
            5 => .{ .shape = .{ .id = a[0].i, .major = a[1].f, .minor = a[2].f } },
            6 => .{ .orientation = .{ .id = a[0].i, .orientation = a[1].f } },
            else => null,
        };
    }
    pub fn setListener(self: *Touch, comptime Data: type, comptime cb: fn (*Touch, Event, Data) void, data: Data) void {
        c.setListener(Touch, self, Data, cb, data);
    }
    pub fn release(self: *Touch) void {
        if (c.version(self) >= 3) c.requestDestroy(self, 0, &.{}) else c.destroyProxy(self);
    }
};

/// wl_output: a monitor. Events arrive as a batch terminated by `done` (v2).
pub const Output = opaque {
    pub const interface = wl_output_interface;

    pub const Mode = packed struct(u32) {
        current: bool = false,
        preferred: bool = false,
        _r2: u30 = 0,
    };
    pub const Event = union(enum) {
        geometry: struct {
            x: i32,
            y: i32,
            physical_width_mm: i32,
            physical_height_mm: i32,
            subpixel: i32,
            make: [*:0]const u8,
            model: [*:0]const u8,
            transform: Transform,
        },
        /// `refresh_mhz`: refresh rate in millihertz.
        mode: struct { flags: Mode, width: i32, height: i32, refresh_mhz: i32 },
        done,
        scale: struct { factor: i32 },
        name: [*:0]const u8,
        description: [*:0]const u8,
    };
    pub fn decodeEvent(opcode: u32, a: [*]Argument) ?Event {
        return switch (opcode) {
            0 => .{ .geometry = .{
                .x = a[0].i,
                .y = a[1].i,
                .physical_width_mm = a[2].i,
                .physical_height_mm = a[3].i,
                .subpixel = a[4].i,
                .make = a[5].s.?,
                .model = a[6].s.?,
                .transform = @enumFromInt(a[7].i),
            } },
            1 => .{ .mode = .{ .flags = @bitCast(a[0].u), .width = a[1].i, .height = a[2].i, .refresh_mhz = a[3].i } },
            2 => .done,
            3 => .{ .scale = .{ .factor = a[0].i } },
            4 => .{ .name = a[0].s.? },
            5 => .{ .description = a[0].s.? },
            else => null,
        };
    }
    pub fn setListener(self: *Output, comptime Data: type, comptime cb: fn (*Output, Event, Data) void, data: Data) void {
        c.setListener(Output, self, Data, cb, data);
    }
    pub fn release(self: *Output) void {
        if (c.version(self) >= 3) c.requestDestroy(self, 0, &.{}) else c.destroyProxy(self);
    }
};
