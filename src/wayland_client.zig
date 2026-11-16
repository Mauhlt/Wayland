//! libwayland-client: loading, wire types, marshalling and event dispatch.
//!
//! The library is opened with dlopen on first `load()` (also done by `Display.connect`), so a
//! machine without Wayland gets `error.LibraryNotFound` instead of a failed launch. Requests are
//! sent with `wl_proxy_marshal_array_flags` (libwayland >= 1.20) and fall back to the older
//! `wl_proxy_marshal_array_constructor_versioned` API (>= 1.10) when it is missing.
const std = @import("std");
const dl = @import("dl.zig");

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

/// Any protocol object (wl_proxy). Typed objects (`WL.Surface`, ...) cast to and from this.
pub const Proxy = opaque {};

/// 24.8 signed fixed-point (wl_fixed_t).
pub const Fixed = enum(i32) {
    _,

    pub fn fromInt(v: i32) Fixed {
        return @enumFromInt(v * 256);
    }
    pub fn fromFloat(v: f64) Fixed {
        return @enumFromInt(@as(i32, @intFromFloat(@round(v * 256.0))));
    }
    pub fn toFloat(self: Fixed) f64 {
        return @as(f64, @floatFromInt(@backingInt(self))) / 256.0;
    }
    pub fn toInt(self: Fixed) i32 {
        return @divTrunc(@backingInt(self), 256);
    }
};

/// wl_array.
pub const Array = extern struct {
    size: usize,
    alloc: usize,
    data: ?*anyopaque,

    /// Views the contents as a slice of `T`.
    pub fn slice(self: *const Array, comptime T: type) []const T {
        const p: [*]const T = @ptrCast(@alignCast(self.data orelse return &.{}));
        return p[0 .. self.size / @sizeOf(T)];
    }
};

/// One marshalled argument (union wl_argument).
pub const Argument = extern union {
    i: i32,
    u: u32,
    f: Fixed,
    s: ?[*:0]const u8,
    o: ?*Proxy,
    n: u32,
    a: ?*Array,
    h: i32,

    pub fn int(v: i32) Argument {
        return .{ .i = v };
    }
    pub fn uint(v: u32) Argument {
        return .{ .u = v };
    }
    pub fn fixed(v: Fixed) Argument {
        return .{ .f = v };
    }
    pub fn string(v: ?[*:0]const u8) Argument {
        return .{ .s = v };
    }
    /// Any typed object pointer, or null for an optional ("?o") argument.
    pub fn object(v: anytype) Argument {
        return .{ .o = if (@typeInfo(@TypeOf(v)) == .null) null else @ptrCast(v) };
    }
    pub fn array(v: ?*Array) Argument {
        return .{ .a = v };
    }
    pub fn fd(v: i32) Argument {
        return .{ .h = v };
    }
    /// Placeholder for a new_id; libwayland fills in the id.
    pub const new_id: Argument = .{ .n = 0 };
};

/// struct wl_message: one request or event.
pub const Message = extern struct {
    name: [*:0]const u8,
    /// Leading digits = since-version; then one char per argument (i u f s o n a h, '?' = nullable).
    signature: [*:0]const u8,
    /// One entry per argument: the interface of 'o' / 'n' arguments, else null.
    types: ?[*]const ?*const Interface,
};

/// struct wl_interface: the protocol description libwayland marshals with.
pub const Interface = extern struct {
    name: [*:0]const u8,
    version: c_int,
    method_count: c_int,
    methods: ?[*]const Message,
    event_count: c_int,
    events: ?[*]const Message,

    /// Builds an interface from slices (used by the protocol files).
    pub fn init(name: [*:0]const u8, ver: c_int, methods: []const Message, events: []const Message) Interface {
        return .{
            .name = name,
            .version = ver,
            .method_count = @intCast(methods.len),
            .methods = if (methods.len == 0) null else methods.ptr,
            .event_count = @intCast(events.len),
            .events = if (events.len == 0) null else events.ptr,
        };
    }
};

/// Convenience for protocol tables.
pub fn msg(name: [*:0]const u8, signature: [*:0]const u8, types: []const ?*const Interface) Message {
    return .{ .name = name, .signature = signature, .types = if (types.len == 0) null else types.ptr };
}

/// Number of arguments in a message signature (skips since-digits and '?').
pub fn signatureArgCount(signature: [*:0]const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (signature[i] != 0) : (i += 1) {
        switch (signature[i]) {
            'i', 'u', 'f', 's', 'o', 'n', 'a', 'h' => n += 1,
            else => {},
        }
    }
    return n;
}

// ---------------------------------------------------------------------------
// Library loading
// ---------------------------------------------------------------------------

pub const Display = opaque {
    /// Connects to `name` (null = $WAYLAND_DISPLAY, or "wayland-0"). Loads libwayland if needed.
    pub fn connect(name: ?[*:0]const u8) error{ LibraryNotFound, MissingSymbol, ConnectFailed }!*Display {
        try load();
        return api().wl_display_connect.?(name) orelse error.ConnectFailed;
    }
    /// Uses an already-connected socket (e.g. from $WAYLAND_SOCKET).
    pub fn connectToFd(fd: i32) error{ LibraryNotFound, MissingSymbol, ConnectFailed }!*Display {
        try load();
        return api().wl_display_connect_to_fd.?(fd) orelse error.ConnectFailed;
    }
    pub fn disconnect(self: *Display) void {
        api().wl_display_disconnect.?(self);
    }
    /// Socket fd, for poll()-based loops.
    pub fn getFd(self: *Display) i32 {
        return api().wl_display_get_fd.?(self);
    }
    /// Blocks until events arrive, then dispatches them. Returns the number dispatched.
    pub fn dispatch(self: *Display) error{DispatchFailed}!u32 {
        return check(api().wl_display_dispatch.?(self));
    }
    /// Dispatches already-queued events without reading the socket.
    pub fn dispatchPending(self: *Display) error{DispatchFailed}!u32 {
        return check(api().wl_display_dispatch_pending.?(self));
    }
    /// Sends all requests and waits until the server has processed them (and their events).
    pub fn roundtrip(self: *Display) error{DispatchFailed}!u32 {
        return check(api().wl_display_roundtrip.?(self));
    }
    /// Returns false if the socket would block (retry after POLLOUT).
    pub fn flush(self: *Display) error{DispatchFailed}!bool {
        const r = api().wl_display_flush.?(self);
        if (r >= 0) return true;
        if (std.c._errno().* == @intFromEnum(std.posix.E.AGAIN)) return false;
        return error.DispatchFailed;
    }
    /// Non-blocking poll loop: `while (!prepareRead()) dispatchPending(); flush; poll; readEvents or cancelRead`.
    pub fn prepareRead(self: *Display) bool {
        return api().wl_display_prepare_read.?(self) == 0;
    }
    pub fn readEvents(self: *Display) error{DispatchFailed}!void {
        if (api().wl_display_read_events.?(self) != 0) return error.DispatchFailed;
    }
    pub fn cancelRead(self: *Display) void {
        api().wl_display_cancel_read.?(self);
    }
    /// Last fatal error (an errno value), 0 if none.
    pub fn getError(self: *Display) i32 {
        return api().wl_display_get_error.?(self);
    }
    pub fn createQueue(self: *Display) ?*EventQueue {
        return api().wl_display_create_queue.?(self);
    }
    pub fn dispatchQueue(self: *Display, queue: *EventQueue) error{DispatchFailed}!u32 {
        return check(api().wl_display_dispatch_queue.?(self, queue));
    }
    pub fn dispatchQueuePending(self: *Display, queue: *EventQueue) error{DispatchFailed}!u32 {
        return check(api().wl_display_dispatch_queue_pending.?(self, queue));
    }
    pub fn roundtripQueue(self: *Display, queue: *EventQueue) error{DispatchFailed}!u32 {
        return check(api().wl_display_roundtrip_queue.?(self, queue));
    }

    /// Requests the global registry (wl_display.get_registry).
    pub fn getRegistry(self: *Display) error{OutOfMemory}!*@import("wayland_protocol.zig").Registry {
        const P = @import("wayland_protocol.zig");
        return requestNew(P.Registry, self, 1, &.{Argument.new_id});
    }
    /// Callback whose `done` fires once all earlier requests are processed (wl_display.sync).
    pub fn sync(self: *Display) error{OutOfMemory}!*@import("wayland_protocol.zig").Callback {
        const P = @import("wayland_protocol.zig");
        return requestNew(P.Callback, self, 0, &.{Argument.new_id});
    }
};

pub const EventQueue = opaque {
    pub fn destroy(self: *EventQueue) void {
        api().wl_event_queue_destroy.?(self);
    }
};

fn check(r: c_int) error{DispatchFailed}!u32 {
    return if (r < 0) error.DispatchFailed else @intCast(r);
}

const DispatcherFn = *const fn (
    implementation: ?*const anyopaque,
    target: ?*anyopaque,
    opcode: u32,
    message: *const Message,
    args: [*]Argument,
) callconv(.c) c_int;

/// libwayland-client symbols. Field names are the C symbol names.
pub const Symbols = struct {
    wl_display_connect: ?*const fn (?[*:0]const u8) callconv(.c) ?*Display,
    wl_display_connect_to_fd: ?*const fn (i32) callconv(.c) ?*Display,
    wl_display_disconnect: ?*const fn (*Display) callconv(.c) void,
    wl_display_get_fd: ?*const fn (*Display) callconv(.c) i32,
    wl_display_dispatch: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_dispatch_pending: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_roundtrip: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_flush: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_prepare_read: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_read_events: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_cancel_read: ?*const fn (*Display) callconv(.c) void,
    wl_display_get_error: ?*const fn (*Display) callconv(.c) c_int,
    wl_display_create_queue: ?*const fn (*Display) callconv(.c) ?*EventQueue,
    wl_display_dispatch_queue: ?*const fn (*Display, *EventQueue) callconv(.c) c_int,
    wl_display_dispatch_queue_pending: ?*const fn (*Display, *EventQueue) callconv(.c) c_int,
    wl_display_roundtrip_queue: ?*const fn (*Display, *EventQueue) callconv(.c) c_int,
    wl_event_queue_destroy: ?*const fn (*EventQueue) callconv(.c) void,

    wl_proxy_marshal_array_flags: ?*const fn (*Proxy, u32, ?*const Interface, u32, u32, [*]Argument) callconv(.c) ?*Proxy,
    wl_proxy_marshal_array_constructor_versioned: ?*const fn (*Proxy, u32, [*]Argument, *const Interface, u32) callconv(.c) ?*Proxy,
    wl_proxy_marshal_array: ?*const fn (*Proxy, u32, [*]Argument) callconv(.c) void,
    wl_proxy_destroy: ?*const fn (*Proxy) callconv(.c) void,
    wl_proxy_add_dispatcher: ?*const fn (*Proxy, DispatcherFn, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    wl_proxy_get_user_data: ?*const fn (*Proxy) callconv(.c) ?*anyopaque,
    wl_proxy_set_user_data: ?*const fn (*Proxy, ?*anyopaque) callconv(.c) void,
    wl_proxy_get_version: ?*const fn (*Proxy) callconv(.c) u32,
    wl_proxy_get_id: ?*const fn (*Proxy) callconv(.c) u32,
    wl_proxy_set_queue: ?*const fn (*Proxy, ?*EventQueue) callconv(.c) void,
};

/// Present only in newer libwayland; everything else is required.
const optional_symbols = [_][]const u8{"wl_proxy_marshal_array_flags"};

var symbols: ?Symbols = null;

/// Opens libwayland-client.so.0 and resolves its symbols. Safe to call more than once.
pub fn load() error{ LibraryNotFound, MissingSymbol }!void {
    if (symbols != null) return;
    const lib = try dl.Library.open(&.{ "libwayland-client.so.0", "libwayland-client.so" });
    const syms = lib.loadAll(Symbols);
    if (dl.firstMissing(syms, &optional_symbols)) |name| {
        std.log.scoped(.wayland).err("libwayland-client is missing {s}", .{name});
        lib.close();
        return error.MissingSymbol;
    }
    symbols = syms;
}

pub fn isLoaded() bool {
    return symbols != null;
}

/// Loaded symbols. Asserts `load()` (or `Display.connect`) succeeded.
pub fn api() *const Symbols {
    return &(symbols orelse @panic("Wayland: call CLIENT.load() or Display.connect() first"));
}

// ---------------------------------------------------------------------------
// Proxy helpers used by the typed protocol objects
// ---------------------------------------------------------------------------

const marshal_flag_destroy: u32 = 1;

var force_legacy_marshal = false;

/// Uses the pre-1.20 marshalling path even when `wl_proxy_marshal_array_flags` exists
/// (for testing the fallback that runs on older distros).
pub fn forceLegacyMarshal(enable: bool) void {
    force_legacy_marshal = enable;
}

fn asProxy(obj: anytype) *Proxy {
    return @ptrCast(obj);
}

/// libwayland's WL_CLOSURE_MAX_ARGS: no message has more arguments.
pub const max_args = 20;

fn marshal(proxy: *Proxy, opcode: u32, iface: ?*const Interface, ver: u32, flags: u32, args: []const Argument) ?*Proxy {
    const a = api();
    // libwayland writes through `args`: a request that creates an object
    // gets the new proxy stored into its new_id argument
    // (create_outgoing_proxy sets args[i].o). Callers pass constant
    // argument lists (often in read-only memory), so marshal from a
    // writable copy.
    std.debug.assert(args.len <= max_args);
    var buf: [max_args]Argument = undefined;
    if (args.len == 0) buf[0] = .new_id else @memcpy(buf[0..args.len], args);
    const argv: [*]Argument = &buf;
    if (!force_legacy_marshal) if (a.wl_proxy_marshal_array_flags) |f| return f(proxy, opcode, iface, ver, flags, argv);
    const result = if (iface) |i|
        a.wl_proxy_marshal_array_constructor_versioned.?(proxy, opcode, argv, i, ver)
    else blk: {
        a.wl_proxy_marshal_array.?(proxy, opcode, argv);
        break :blk null;
    };
    if (flags & marshal_flag_destroy != 0) a.wl_proxy_destroy.?(proxy);
    return result;
}

/// Sends a request that creates no object.
pub fn request(obj: anytype, opcode: u32, args: []const Argument) void {
    _ = marshal(asProxy(obj), opcode, null, version(obj), 0, args);
}

/// Sends a destructor request and frees the proxy.
pub fn requestDestroy(obj: anytype, opcode: u32, args: []const Argument) void {
    _ = marshal(asProxy(obj), opcode, null, version(obj), marshal_flag_destroy, args);
}

/// Sends a request whose new_id creates a `T` (same version as the parent).
pub fn requestNew(comptime T: type, obj: anytype, opcode: u32, args: []const Argument) error{OutOfMemory}!*T {
    const p = marshal(asProxy(obj), opcode, &T.interface, version(obj), 0, args) orelse return error.OutOfMemory;
    return @ptrCast(p);
}

/// Like `requestNew` with an explicit version (wl_registry.bind).
pub fn requestNewVersioned(comptime T: type, obj: anytype, opcode: u32, args: []const Argument, ver: u32) error{OutOfMemory}!*T {
    const p = marshal(asProxy(obj), opcode, &T.interface, ver, 0, args) orelse return error.OutOfMemory;
    return @ptrCast(p);
}

/// Frees a proxy that has no destructor request (wl_callback, wl_registry, ...).
pub fn destroyProxy(obj: anytype) void {
    api().wl_proxy_destroy.?(asProxy(obj));
}

/// Version the object was bound / created with.
pub fn version(obj: anytype) u32 {
    return api().wl_proxy_get_version.?(asProxy(obj));
}

/// Protocol object id.
pub fn id(obj: anytype) u32 {
    return api().wl_proxy_get_id.?(asProxy(obj));
}

/// Moves `obj`'s events to `queue` (null = default queue).
pub fn setQueue(obj: anytype, queue: ?*EventQueue) void {
    api().wl_proxy_set_queue.?(asProxy(obj), queue);
}

/// Installs `callback` as the event handler for `obj` (once per object).
///
/// `T` is the typed object (e.g. `WL.Surface`) with `pub const Event` and
/// `pub fn decodeEvent(opcode, args) ?Event`. `Data` must be a pointer type or `void`.
pub fn setListener(
    comptime T: type,
    obj: *T,
    comptime Data: type,
    comptime callback: fn (obj: *T, event: T.Event, data: Data) void,
    data: Data,
) void {
    const Impl = struct {
        fn dispatch(_: ?*const anyopaque, target: ?*anyopaque, opcode: u32, _: *const Message, args: [*]Argument) callconv(.c) c_int {
            const self: *T = @ptrCast(target.?);
            const event = T.decodeEvent(opcode, args) orelse return 0;
            const raw = api().wl_proxy_get_user_data.?(@ptrCast(self));
            const user: Data = if (Data == void) {} else @ptrCast(@alignCast(raw));
            callback(self, event, user);
            return 0;
        }
        const marker: u8 = 0;
    };
    const raw: ?*anyopaque = if (Data == void) null else @ptrCast(@constCast(data));
    // The implementation pointer only has to be non-null; dispatch is per-type above.
    _ = api().wl_proxy_add_dispatcher.?(asProxy(obj), Impl.dispatch, &Impl.marker, raw);
}

/// Casts an 'o' event argument to a typed object.
pub fn argObject(comptime T: type, a: Argument) ?*T {
    return @ptrCast(a.o);
}
