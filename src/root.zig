//! Zig bindings for Wayland clients: a window to render into with Vulkan, plus input.
//!
//!     const W = @import("Wayland");
//!     const display = try W.WL.Display.connect(null);   // dlopens libwayland-client
//!     const registry = try display.getRegistry();
//!     registry.setListener(*App, App.onGlobal, &app);
//!     _ = try display.roundtrip();
//!
//! Everything is loaded at runtime with dlopen, so one binary runs on any distro (and fails
//! with an error, not a loader crash, where Wayland is unavailable).

pub const CLIENT = @import("wayland_client.zig");
pub const WL = @import("wayland_protocol.zig");
pub const XDG = @import("xdg_shell.zig");
pub const DECOR = @import("xdg_decoration.zig");
pub const XKB = @import("xkbcommon.zig");
pub const DL = @import("dl.zig");


// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// Forces semantic analysis of every declaration (and nested type methods).
fn refAllDeclsRecursive(comptime T: type, comptime depth: u32) void {
    if (depth == 0) return;
    inline for (comptime std.meta.declarations(T)) |name| {
        const field = @field(T, name);
        if (@TypeOf(field) == type) {
            switch (@typeInfo(field)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(field, depth - 1),
                else => {},
            }
        }
        _ = &field;
    }
}

test "analyze all declarations (Linux targets)" {
    // Only meaningful when building for Linux (e.g. `zig build test -Dtarget=x86_64-linux-gnu`).
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    refAllDeclsRecursive(@This(), 4);
}

const all_interfaces = [_]*const CLIENT.Interface{
    &WL.wl_display_interface,  &WL.wl_registry_interface, &WL.wl_callback_interface,
    &WL.wl_compositor_interface, &WL.wl_buffer_interface, &WL.wl_surface_interface,
    &WL.wl_region_interface,   &WL.wl_seat_interface,     &WL.wl_pointer_interface,
    &WL.wl_keyboard_interface, &WL.wl_touch_interface,    &WL.wl_output_interface,
    &XDG.xdg_wm_base_interface, &XDG.xdg_positioner_interface, &XDG.xdg_surface_interface,
    &XDG.xdg_toplevel_interface, &XDG.xdg_popup_interface,
    &DECOR.zxdg_decoration_manager_v1_interface, &DECOR.zxdg_toplevel_decoration_v1_interface,
};

test "protocol tables: names, versions and message counts" {
    const expect = struct {
        fn f(iface: *const CLIENT.Interface, name: []const u8, version: c_int, requests: c_int, events: c_int) !void {
            try testing.expectEqualStrings(name, std.mem.span(iface.name));
            try testing.expectEqual(version, iface.version);
            try testing.expectEqual(requests, iface.method_count);
            try testing.expectEqual(events, iface.event_count);
        }
    }.f;
    try expect(&WL.wl_display_interface, "wl_display", 1, 2, 2);
    try expect(&WL.wl_registry_interface, "wl_registry", 1, 1, 2);
    try expect(&WL.wl_compositor_interface, "wl_compositor", 6, 2, 0);
    try expect(&WL.wl_surface_interface, "wl_surface", 6, 11, 4);
    try expect(&WL.wl_seat_interface, "wl_seat", 9, 4, 2);
    try expect(&WL.wl_pointer_interface, "wl_pointer", 9, 2, 11);
    try expect(&WL.wl_keyboard_interface, "wl_keyboard", 9, 1, 6);
    try expect(&WL.wl_touch_interface, "wl_touch", 9, 1, 7);
    try expect(&WL.wl_output_interface, "wl_output", 4, 1, 6);
    try expect(&XDG.xdg_wm_base_interface, "xdg_wm_base", 6, 4, 1);
    try expect(&XDG.xdg_positioner_interface, "xdg_positioner", 6, 10, 0);
    try expect(&XDG.xdg_surface_interface, "xdg_surface", 6, 5, 1);
    try expect(&XDG.xdg_toplevel_interface, "xdg_toplevel", 6, 14, 4);
    try expect(&XDG.xdg_popup_interface, "xdg_popup", 6, 3, 3);
    try expect(&DECOR.zxdg_decoration_manager_v1_interface, "zxdg_decoration_manager_v1", 1, 2, 0);
    try expect(&DECOR.zxdg_toplevel_decoration_v1_interface, "zxdg_toplevel_decoration_v1", 1, 3, 1);
}

test "protocol tables: every message is well formed" {
    for (all_interfaces) |iface| {
        const lists = [_]struct { ?[*]const CLIENT.Message, c_int }{
            .{ iface.methods, iface.method_count },
            .{ iface.events, iface.event_count },
        };
        for (lists) |list| {
            const msgs, const count = list;
            if (count == 0) {
                try testing.expect(msgs == null);
                continue;
            }
            for (msgs.?[0..@intCast(count)]) |m| {
                const sig = std.mem.span(m.signature);
                const nargs = CLIENT.signatureArgCount(m.signature);
                // Since-version prefix must not exceed the interface version.
                var i: usize = 0;
                while (i < sig.len and std.ascii.isDigit(sig[i])) : (i += 1) {}
                if (i > 0) try testing.expect(try std.fmt.parseInt(c_int, sig[0..i], 10) <= iface.version);
                for (sig[i..]) |ch| try testing.expect(std.mem.indexOfScalar(u8, "iufsonah?", ch) != null);
                // A new_id with a known interface must name it.
                if (nargs == 0) try testing.expect(m.types == null) else try testing.expect(m.types != null);
                var arg: usize = 0;
                for (sig[i..]) |ch| {
                    if (ch == '?') continue;
                    const t = m.types.?[arg];
                    if (ch != 'o' and ch != 'n') try testing.expect(t == null);
                    arg += 1;
                }
            }
        }
    }
}

test "wire types match libwayland's ABI" {
    try testing.expectEqual(8, @sizeOf(CLIENT.Argument));
    try testing.expectEqual(3 * @sizeOf(usize), @sizeOf(CLIENT.Array));
    try testing.expectEqual(3 * @sizeOf(usize), @sizeOf(CLIENT.Message));
    try testing.expectEqual(if (@sizeOf(usize) == 8) 40 else 24, @sizeOf(CLIENT.Interface));
    try testing.expectEqual(256, @backingInt(CLIENT.Fixed.fromInt(1)));
    try testing.expectEqual(-1.5, CLIENT.Fixed.fromFloat(-1.5).toFloat());
    try testing.expectEqual(10, CLIENT.Fixed.fromFloat(10.75).toInt());
    try testing.expectEqual(4, CLIENT.signatureArgCount("5u?oii"));
    try testing.expectEqual(0, CLIENT.signatureArgCount("3"));
    try testing.expectEqual(0x06, @as(u32, @bitCast(XKB.StateComponent{ .mods_latched = true, .mods_locked = true })));
}

test "events decode from wire arguments" {
    const A = CLIENT.Argument;
    var states = [_]u32{ 4, 1, 9 }; // activated, maximized, suspended
    var array: CLIENT.Array = .{ .size = @sizeOf(@TypeOf(states)), .alloc = 0, .data = &states };
    var args = [_]A{ .int(800), .int(600), .array(&array) };
    const ev = XDG.Toplevel.decodeEvent(0, &args).?;
    try testing.expectEqual(800, ev.configure.width);
    try testing.expect(ev.configure.states.activated and ev.configure.states.maximized and ev.configure.states.suspended);
    try testing.expect(!ev.configure.states.fullscreen);

    var ptr_args = [_]A{ .uint(7), .uint(1000), .uint(WL.BTN_LEFT), .uint(1) };
    const b = WL.Pointer.decodeEvent(3, &ptr_args).?.button;
    try testing.expectEqual(WL.BTN_LEFT, b.button);
    try testing.expectEqual(WL.Pointer.ButtonState.pressed, b.state);

    var seat_args = [_]A{.uint(0b011)};
    const caps = WL.Seat.decodeEvent(0, &seat_args).?.capabilities;
    try testing.expect(caps.pointer and caps.keyboard and !caps.touch);

    var reg_args = [_]A{ .uint(3), .string("wl_compositor"), .uint(6) };
    const g = WL.Registry.decodeEvent(0, &reg_args).?.global;
    try testing.expectEqualStrings("wl_compositor", std.mem.span(g.interface));
    try testing.expectEqual(null, WL.Registry.decodeEvent(9, &reg_args));
}

// --- Live tests: need a Linux machine (or WSLg) --------------------------------

test "live: xkbcommon keymap from names" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    XKB.load() catch return error.SkipZigTest;
    const ctx = XKB.Context.new() orelse return error.TestUnexpectedResult;
    defer ctx.unref();
    const keymap = XKB.Keymap.fromNames(ctx, &.{ .rules = "evdev", .model = "pc105", .layout = "us" }) orelse
        return error.SkipZigTest; // xkeyboard-config data not installed
    defer keymap.unref();
    const state = XKB.State.new(keymap) orelse return error.TestUnexpectedResult;
    defer state.unref();

    const key_a: u32 = 30 + XKB.evdev_offset; // KEY_A
    try testing.expectEqual(XKB.Keysym.a, state.keyGetOneSym(key_a));
    var buf: [8]u8 = undefined;
    try testing.expectEqualStrings("a", state.keyGetUtf8(key_a, &buf));
    try testing.expect(keymap.keyRepeats(key_a));
    try testing.expectEqual(XKB.Keysym.escape, XKB.Keysym.fromName("Escape"));
    var name: [32]u8 = undefined;
    try testing.expectEqualStrings("Escape", XKB.Keysym.escape.getName(&name).?);
    try testing.expectEqual('a', XKB.Keysym.a.toUtf32());
}

test "live: connect, bind globals, map an xdg toplevel" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    try mapToplevel();
}

test "live: same, through the pre-1.20 libwayland marshalling fallback" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    CLIENT.forceLegacyMarshal(true);
    defer CLIENT.forceLegacyMarshal(false);
    try mapToplevel();
}

fn mapToplevel() !void {
    const display = WL.Display.connect(null) catch return error.SkipZigTest; // no compositor
    defer display.disconnect();

    const App = struct {
        compositor: ?*WL.Compositor = null,
        wm_base: ?*XDG.WmBase = null,
        seat: ?*WL.Seat = null,
        decorations: ?*DECOR.Manager = null,
        outputs: u32 = 0,
        configured: bool = false,
        width: i32 = 0,

        fn onGlobal(registry: *WL.Registry, ev: WL.Registry.Event, app: *@This()) void {
            switch (ev) {
                .global => |g| {
                    const name = std.mem.span(g.interface);
                    if (std.mem.eql(u8, name, "wl_compositor"))
                        app.compositor = registry.bind(g.name, WL.Compositor, g.version) catch null
                    else if (std.mem.eql(u8, name, "xdg_wm_base"))
                        app.wm_base = registry.bind(g.name, XDG.WmBase, g.version) catch null
                    else if (std.mem.eql(u8, name, "wl_seat"))
                        app.seat = registry.bind(g.name, WL.Seat, g.version) catch null
                    else if (std.mem.eql(u8, name, "zxdg_decoration_manager_v1"))
                        app.decorations = registry.bind(g.name, DECOR.Manager, g.version) catch null
                    else if (std.mem.eql(u8, name, "wl_output"))
                        app.outputs += 1;
                },
                .global_remove => {},
            }
        }
        fn onPing(wm: *XDG.WmBase, ev: XDG.WmBase.Event, _: void) void {
            wm.pong(ev.ping.serial);
        }
        fn onSurface(xs: *XDG.Surface, ev: XDG.Surface.Event, app: *@This()) void {
            xs.ackConfigure(ev.configure.serial);
            app.configured = true;
        }
        fn onToplevel(_: *XDG.Toplevel, ev: XDG.Toplevel.Event, app: *@This()) void {
            switch (ev) {
                .configure => |cfg| app.width = cfg.width,
                else => {},
            }
        }
    };
    var app: App = .{};

    const registry = try display.getRegistry();
    defer registry.destroy();
    registry.setListener(*App, App.onGlobal, &app);
    _ = try display.roundtrip();

    const compositor = app.compositor orelse return error.TestUnexpectedResult;
    defer compositor.destroy();
    const wm_base = app.wm_base orelse return error.TestUnexpectedResult;
    defer wm_base.destroy();
    defer if (app.seat) |seat| seat.release();
    defer if (app.decorations) |d| d.destroy();
    wm_base.setListener(void, App.onPing, {});
    try testing.expect(CLIENT.version(compositor) >= 1);

    const surface = try compositor.createSurface();
    defer surface.destroy();
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    const toplevel = try xdg_surface.getToplevel();
    defer toplevel.destroy();
    xdg_surface.setListener(*App, App.onSurface, &app);
    toplevel.setListener(*App, App.onToplevel, &app);
    toplevel.setTitle("Zig Wayland bindings test");
    toplevel.setAppId("zig.wayland.test");
    const deco: ?*DECOR.ToplevelDecoration = if (app.decorations) |d| try d.getToplevelDecoration(toplevel) else null;
    defer if (deco) |dd| dd.destroy();
    if (deco) |dd| dd.setMode(.server_side);
    surface.commit();

    var tries: u32 = 0;
    while (!app.configured and tries < 20) : (tries += 1) _ = try display.roundtrip();
    try testing.expect(app.configured);

    // A frame callback round trip proves request + event plumbing for new objects.
    const cb = try display.sync();
    var done = false;
    cb.setListener(*bool, struct {
        fn f(c: *WL.Callback, _: WL.Callback.Event, flag: *bool) void {
            flag.* = true;
            c.destroy();
        }
    }.f, &done);
    _ = try display.roundtrip();
    try testing.expect(done);
    try testing.expectEqual(0, display.getError());
}

test "live: compositor keymap through wl_keyboard and xkbcommon" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    XKB.load() catch return error.SkipZigTest;
    const display = WL.Display.connect(null) catch return error.SkipZigTest;
    defer display.disconnect();

    const App = struct {
        compositor: ?*WL.Compositor = null,
        wm_base: ?*XDG.WmBase = null,
        configured: bool = false,
        seat: ?*WL.Seat = null,
        caps: WL.Seat.Capabilities = .{},
        keymap: ?*XKB.Keymap = null,
        ctx: *XKB.Context,
        failed: bool = false,

        fn onGlobal(registry: *WL.Registry, ev: WL.Registry.Event, app: *@This()) void {
            if (ev != .global) return;
            const g = ev.global;
            const name = std.mem.span(g.interface);
            if (std.mem.eql(u8, name, "wl_seat") and app.seat == null)
                app.seat = registry.bind(g.name, WL.Seat, g.version) catch null
            else if (std.mem.eql(u8, name, "wl_compositor"))
                app.compositor = registry.bind(g.name, WL.Compositor, g.version) catch null
            else if (std.mem.eql(u8, name, "xdg_wm_base"))
                app.wm_base = registry.bind(g.name, XDG.WmBase, g.version) catch null;
        }
        fn onPing(wm: *XDG.WmBase, ev: XDG.WmBase.Event, _: void) void {
            wm.pong(ev.ping.serial);
        }
        fn onConfigure(xs: *XDG.Surface, ev: XDG.Surface.Event, app: *@This()) void {
            xs.ackConfigure(ev.configure.serial);
            app.configured = true;
        }
        fn onSeat(_: *WL.Seat, ev: WL.Seat.Event, app: *@This()) void {
            if (ev == .capabilities) app.caps = ev.capabilities;
        }
        fn onKeyboard(_: *WL.Keyboard, ev: WL.Keyboard.Event, app: *@This()) void {
            switch (ev) {
                .keymap => |k| {
                    defer _ = std.c.close(k.fd);
                    if (k.format != .xkb_v1) return;
                    app.keymap = XKB.Keymap.fromFd(app.ctx, k.fd, k.size) catch blk: {
                        app.failed = true;
                        break :blk null;
                    };
                },
                else => {},
            }
        }
    };
    const ctx = XKB.Context.new() orelse return error.TestUnexpectedResult;
    defer ctx.unref();
    var app: App = .{ .ctx = ctx };

    const registry = try display.getRegistry();
    defer registry.destroy();
    registry.setListener(*App, App.onGlobal, &app);
    _ = try display.roundtrip();

    // Keyboard input goes to windows, and some compositors (WSLg) only attach their input
    // seat once a window is mapped, so map one first.
    const compositor = app.compositor orelse return error.SkipZigTest;
    defer compositor.destroy();
    const wm_base = app.wm_base orelse return error.SkipZigTest;
    defer wm_base.destroy();
    wm_base.setListener(void, App.onPing, {});
    const surface = try compositor.createSurface();
    defer surface.destroy();
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    const toplevel = try xdg_surface.getToplevel();
    defer toplevel.destroy();
    xdg_surface.setListener(*App, App.onConfigure, &app);
    toplevel.setTitle("Zig Wayland keyboard test");
    surface.commit();

    var tries: u32 = 0;
    while (app.seat == null and tries < 20) : (tries += 1) {
        _ = try display.roundtrip();
        if (app.seat == null) {
            // Wait up to 50 ms for the compositor to send something.
            var fds = [_]std.posix.pollfd{.{ .fd = display.getFd(), .events = std.posix.POLL.IN, .revents = 0 }};
            _ = std.posix.poll(&fds, 50) catch {};
        }
    }
    const seat = app.seat orelse {
        std.debug.print("skip: compositor has no wl_seat\n", .{});
        return error.SkipZigTest;
    };
    defer seat.release();
    seat.setListener(*App, App.onSeat, &app);
    // Capabilities and the keymap can arrive a few roundtrips late (e.g. while a compositor
    // is still setting up its input devices), so wait for each with a bound.
    tries = 0;
    while (!app.caps.keyboard and tries < 10) : (tries += 1) _ = try display.roundtrip();
    if (!app.caps.keyboard) {
        std.debug.print("skip: wl_seat has no keyboard (capabilities {any})\n", .{app.caps});
        return error.SkipZigTest;
    }

    const keyboard = try seat.getKeyboard();
    defer keyboard.release();
    keyboard.setListener(*App, App.onKeyboard, &app);
    tries = 0;
    while (app.keymap == null and !app.failed and tries < 10) : (tries += 1) _ = try display.roundtrip();
    try testing.expect(!app.failed);
    const keymap = app.keymap orelse {
        std.debug.print("skip: compositor sent no xkb keymap\n", .{});
        return error.SkipZigTest;
    };
    defer keymap.unref();

    const state = XKB.State.new(keymap) orelse return error.TestUnexpectedResult;
    defer state.unref();
    // KEY_ESC is layout independent.
    try testing.expectEqual(XKB.Keysym.escape, state.keyGetOneSym(1 + XKB.evdev_offset));
}
