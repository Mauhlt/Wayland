# Wayland

Zig bindings for Wayland clients: a window to render into with Vulkan
(`VK_KHR_wayland_surface`), plus keyboard, pointer, touch and output info.

| Namespace | Contents |
|-----------|----------|
| `CLIENT`  | libwayland-client: loading, `Display`, wire types (`Fixed`, `Array`, `Argument`), proxy helpers (`version`, `id`, `setQueue`) |
| `WL`      | Core protocol: `Display`, `Registry`, `Callback`, `Compositor`, `Surface`, `Region`, `Seat`, `Pointer`, `Keyboard`, `Touch`, `Output` |
| `XDG`     | xdg-shell: `WmBase`, `Surface`, `Toplevel`, `Popup`, `Positioner` |
| `DECOR`   | xdg-decoration: server-side title bars (`Manager`, `ToplevelDecoration`) |
| `XKB`     | libxkbcommon: keymaps, key state, keysyms, UTF-8 text |
| `DL`      | dlopen / dlsym helpers |

## Install

```sh
zig fetch --save git+https://github.com/Mauhlt/Wayland.git
```

```zig
const wayland = b.dependency("Wayland", .{});
exe.root_module.addImport("Wayland", wayland.module("Wayland"));
```

Build with a `-gnu` target (e.g. `-Dtarget=x86_64-linux-gnu`). A static musl binary
can't dlopen the system's glibc libraries.

## Running on different Linux machines

Nothing is linked at build time. `libwayland-client.so.0` and `libxkbcommon.so.0` are
opened with `dlopen`, so:

- it cross-compiles from Windows or macOS without a Linux sysroot,
- one binary runs on any distro, and
- a machine without Wayland gets `error.LibraryNotFound` from `Display.connect`
  instead of failing to start, so you can fall back to something else.

Requests use `wl_proxy_marshal_array_flags` (libwayland 1.20+) and fall back to the
older `wl_proxy_marshal_array_constructor_versioned` API (1.10+, 2016) automatically.
Protocol descriptions are compiled into the package, and `Registry.bind` clamps each
global to the version both sides support.

## Example: window

```zig
const W = @import("Wayland");
const WL = W.WL;
const XDG = W.XDG;

const App = struct {
    compositor: ?*WL.Compositor = null,
    wm_base: ?*XDG.WmBase = null,
    width: i32 = 800,
    height: i32 = 600,
    configured: bool = false,
    closed: bool = false,

    fn onGlobal(reg: *WL.Registry, ev: WL.Registry.Event, app: *App) void {
        if (ev != .global) return;
        const name = std.mem.span(ev.global.interface);
        if (std.mem.eql(u8, name, "wl_compositor"))
            app.compositor = reg.bind(ev.global.name, WL.Compositor, ev.global.version) catch null
        else if (std.mem.eql(u8, name, "xdg_wm_base"))
            app.wm_base = reg.bind(ev.global.name, XDG.WmBase, ev.global.version) catch null;
    }
    fn onPing(wm: *XDG.WmBase, ev: XDG.WmBase.Event, _: void) void {
        wm.pong(ev.ping.serial);
    }
    fn onSurface(xs: *XDG.Surface, ev: XDG.Surface.Event, app: *App) void {
        xs.ackConfigure(ev.configure.serial);
        app.configured = true;
    }
    fn onToplevel(_: *XDG.Toplevel, ev: XDG.Toplevel.Event, app: *App) void {
        switch (ev) {
            .configure => |c| if (c.width > 0 and c.height > 0) {
                app.width = c.width;
                app.height = c.height;
            },
            .close => app.closed = true,
            else => {},
        }
    }
};

var app: App = .{};
const display = try WL.Display.connect(null);
defer display.disconnect();
const registry = try display.getRegistry();
registry.setListener(*App, App.onGlobal, &app);
_ = try display.roundtrip();

app.wm_base.?.setListener(void, App.onPing, {});
const surface = try app.compositor.?.createSurface();
const xdg_surface = try app.wm_base.?.getXdgSurface(surface);
const toplevel = try xdg_surface.getToplevel();
xdg_surface.setListener(*App, App.onSurface, &app);
toplevel.setListener(*App, App.onToplevel, &app);
toplevel.setTitle("Renderer");
surface.commit();
while (!app.configured) _ = try display.dispatch();

// Vulkan: VkWaylandSurfaceCreateInfoKHR{ .display = display, .surface = surface }
while (!app.closed) {
    _ = try display.dispatchPending();
    _ = try display.flush();
    // render a frame at app.width x app.height
}
```

Keyboard input: bind `wl_seat`, call `seat.getKeyboard()`, compile the `keymap` event's
fd with `XKB.Keymap.fromFd`, and translate `key` events with `XKB.State` (key code + 8).

Window decorations: bind `zxdg_decoration_manager_v1` and ask for `.server_side`.
GNOME doesn't offer it, so there the window has no title bar unless you draw one.

## Tests

`zig build test` checks the protocol tables (names, versions, message counts,
signatures), wire-type ABI and event decoding on any OS. On Linux it also:

- talks to the running compositor: binds globals and maps an xdg toplevel, through both
  the modern and the pre-1.20 libwayland code paths, and
- gets the compositor's keymap through `wl_keyboard` and compiles it with xkbcommon.

From Windows: `zig build test-exe -Dtarget=x86_64-linux-gnu` builds `zig-out/bin/wayland-test`
to run in WSL. On WSLg, give the compositor a few seconds after WSL starts so its input
seat is attached. If `/run/user/1000/wayland-0` is missing, set
`WAYLAND_DISPLAY=/mnt/wslg/runtime-dir/wayland-0`.
