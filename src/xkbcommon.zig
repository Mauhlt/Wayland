//! libxkbcommon: turning wl_keyboard key codes into keysyms and text.
//!
//!     try XKB.load();
//!     const ctx = XKB.Context.new() orelse return error.Xkb;
//!     // on wl_keyboard.keymap:
//!     const keymap = try XKB.Keymap.fromFd(ctx, fd, size);  // closes nothing; close(fd) yourself
//!     const state = XKB.State.new(keymap) orelse return error.Xkb;
//!     // on wl_keyboard.modifiers: state.updateMask(depressed, latched, locked, 0, 0, group);
//!     // on wl_keyboard.key:       const sym = state.keyGetOneSym(key + 8);
const std = @import("std");
const dl = @import("dl.zig");

/// XKB keycode = evdev / wl_keyboard key code + 8.
pub const evdev_offset: u32 = 8;

pub const Keysym = enum(u32) {
    no_symbol = 0,
    space = 0x0020,
    a = 0x0061,
    z = 0x007a,
    backspace = 0xff08,
    tab = 0xff09,
    @"return" = 0xff0d,
    escape = 0xff1b,
    delete = 0xffff,
    home = 0xff50,
    left = 0xff51,
    up = 0xff52,
    right = 0xff53,
    down = 0xff54,
    page_up = 0xff55,
    page_down = 0xff56,
    end = 0xff57,
    insert = 0xff63,
    f1 = 0xffbe,
    f2 = 0xffbf,
    f3 = 0xffc0,
    f4 = 0xffc1,
    f5 = 0xffc2,
    f6 = 0xffc3,
    f7 = 0xffc4,
    f8 = 0xffc5,
    f9 = 0xffc6,
    f10 = 0xffc7,
    f11 = 0xffc8,
    f12 = 0xffc9,
    shift_l = 0xffe1,
    shift_r = 0xffe2,
    control_l = 0xffe3,
    control_r = 0xffe4,
    caps_lock = 0xffe5,
    alt_l = 0xffe9,
    alt_r = 0xffea,
    super_l = 0xffeb,
    super_r = 0xffec,
    _,

    /// Unicode code point the keysym produces, or 0.
    pub fn toUtf32(self: Keysym) u32 {
        return api().xkb_keysym_to_utf32.?(@backingInt(self));
    }
    /// Writes the keysym name (e.g. "Escape") into `buf`; returns the slice.
    pub fn getName(self: Keysym, buf: []u8) ?[]const u8 {
        const n = api().xkb_keysym_get_name.?(@backingInt(self), buf.ptr, buf.len);
        if (n < 0) return null;
        return buf[0..@min(@as(usize, @intCast(n)), buf.len -| 1)];
    }
    /// Case-sensitive lookup by name (e.g. "Escape", "a").
    pub fn fromName(name: [*:0]const u8) Keysym {
        return @enumFromInt(api().xkb_keysym_from_name.?(name, 0));
    }
};

/// Standard modifier names for `State.modNameIsActive`.
pub const MOD_NAME_SHIFT = "Shift";
pub const MOD_NAME_CAPS = "Lock";
pub const MOD_NAME_CTRL = "Control";
pub const MOD_NAME_ALT = "Mod1";
pub const MOD_NAME_NUM = "Mod2";
pub const MOD_NAME_LOGO = "Mod4";

/// enum xkb_state_component.
pub const StateComponent = bitpack struct(u32) {
    mods_depressed: bool = false,
    mods_latched: bool = false,
    mods_locked: bool = false,
    mods_effective: bool = false,
    layout_depressed: bool = false,
    layout_latched: bool = false,
    layout_locked: bool = false,
    layout_effective: bool = false,
    leds: bool = false,
    _r9: u23 = 0,
};

/// struct xkb_rule_names; null fields use the system default.
pub const RuleNames = extern struct {
    rules: ?[*:0]const u8 = null,
    model: ?[*:0]const u8 = null,
    layout: ?[*:0]const u8 = null,
    variant: ?[*:0]const u8 = null,
    options: ?[*:0]const u8 = null,
};

const keymap_format_text_v1: c_int = 1;

pub const Context = opaque {
    pub fn new() ?*Context {
        return api().xkb_context_new.?(0);
    }
    pub fn unref(self: *Context) void {
        api().xkb_context_unref.?(self);
    }
};

pub const Keymap = opaque {
    /// Compiles the keymap text sent by wl_keyboard.keymap. Does not close `fd`.
    pub fn fromFd(ctx: *Context, fd: i32, size: u32) error{ MapFailed, CompileFailed }!*Keymap {
        const mem = std.posix.mmap(null, size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, fd, 0) catch return error.MapFailed;
        defer std.posix.munmap(mem);
        // The text is NUL-terminated within `size`.
        const len = std.mem.indexOfScalar(u8, mem, 0) orelse mem.len;
        return fromBuffer(ctx, mem[0..len]) orelse error.CompileFailed;
    }
    pub fn fromBuffer(ctx: *Context, text: []const u8) ?*Keymap {
        return api().xkb_keymap_new_from_buffer.?(ctx, text.ptr, text.len, keymap_format_text_v1, 0);
    }
    pub fn fromString(ctx: *Context, text: [*:0]const u8) ?*Keymap {
        return api().xkb_keymap_new_from_string.?(ctx, text, keymap_format_text_v1, 0);
    }
    /// Keymap from RMLVO names (e.g. `.{ .layout = "us" }`), without a compositor.
    pub fn fromNames(ctx: *Context, names: ?*const RuleNames) ?*Keymap {
        return api().xkb_keymap_new_from_names.?(ctx, names, 0);
    }
    pub fn unref(self: *Keymap) void {
        api().xkb_keymap_unref.?(self);
    }
    pub fn keyRepeats(self: *Keymap, keycode: u32) bool {
        return api().xkb_keymap_key_repeats.?(self, keycode) != 0;
    }
};

pub const State = opaque {
    pub fn new(keymap: *Keymap) ?*State {
        return api().xkb_state_new.?(keymap);
    }
    pub fn unref(self: *State) void {
        api().xkb_state_unref.?(self);
    }
    /// Feed wl_keyboard.modifiers here (layouts: 0, 0, group).
    pub fn updateMask(
        self: *State,
        depressed_mods: u32,
        latched_mods: u32,
        locked_mods: u32,
        depressed_layout: u32,
        latched_layout: u32,
        locked_layout: u32,
    ) StateComponent {
        const r = api().xkb_state_update_mask.?(self, depressed_mods, latched_mods, locked_mods, depressed_layout, latched_layout, locked_layout);
        return @bitCast(@as(u32, @bitCast(r)));
    }
    pub fn keyGetOneSym(self: *State, keycode: u32) Keysym {
        return @enumFromInt(api().xkb_state_key_get_one_sym.?(self, keycode));
    }
    /// UTF-8 text for the key, written to `buf`. Empty when the key produces no text.
    pub fn keyGetUtf8(self: *State, keycode: u32, buf: []u8) []const u8 {
        const n = api().xkb_state_key_get_utf8.?(self, keycode, buf.ptr, buf.len);
        if (n <= 0) return buf[0..0];
        return buf[0..@min(@as(usize, @intCast(n)), buf.len -| 1)];
    }
    pub fn keyGetUtf32(self: *State, keycode: u32) u32 {
        return api().xkb_state_key_get_utf32.?(self, keycode);
    }
    /// e.g. `state.modNameIsActive(XKB.MOD_NAME_CTRL, .{ .mods_effective = true })`.
    pub fn modNameIsActive(self: *State, name: [*:0]const u8, kind: StateComponent) bool {
        return api().xkb_state_mod_name_is_active.?(self, name, @bitCast(kind)) > 0;
    }
};

/// libxkbcommon symbols. Field names are the C symbol names.
pub const Symbols = struct {
    xkb_context_new: ?*const fn (c_int) callconv(.c) ?*Context,
    xkb_context_unref: ?*const fn (*Context) callconv(.c) void,
    xkb_keymap_new_from_string: ?*const fn (*Context, [*:0]const u8, c_int, c_int) callconv(.c) ?*Keymap,
    xkb_keymap_new_from_buffer: ?*const fn (*Context, [*]const u8, usize, c_int, c_int) callconv(.c) ?*Keymap,
    xkb_keymap_new_from_names: ?*const fn (*Context, ?*const RuleNames, c_int) callconv(.c) ?*Keymap,
    xkb_keymap_unref: ?*const fn (*Keymap) callconv(.c) void,
    xkb_keymap_key_repeats: ?*const fn (*Keymap, u32) callconv(.c) c_int,
    xkb_state_new: ?*const fn (*Keymap) callconv(.c) ?*State,
    xkb_state_unref: ?*const fn (*State) callconv(.c) void,
    xkb_state_update_mask: ?*const fn (*State, u32, u32, u32, u32, u32, u32) callconv(.c) c_int,
    xkb_state_key_get_one_sym: ?*const fn (*State, u32) callconv(.c) u32,
    xkb_state_key_get_utf8: ?*const fn (*State, u32, [*]u8, usize) callconv(.c) c_int,
    xkb_state_key_get_utf32: ?*const fn (*State, u32) callconv(.c) u32,
    xkb_state_mod_name_is_active: ?*const fn (*State, [*:0]const u8, c_int) callconv(.c) c_int,
    xkb_keysym_get_name: ?*const fn (u32, [*]u8, usize) callconv(.c) c_int,
    xkb_keysym_from_name: ?*const fn ([*:0]const u8, c_int) callconv(.c) u32,
    xkb_keysym_to_utf32: ?*const fn (u32) callconv(.c) u32,
};

var symbols: ?Symbols = null;

/// Opens libxkbcommon.so.0 and resolves its symbols. Safe to call more than once.
pub fn load() error{ LibraryNotFound, MissingSymbol }!void {
    if (symbols != null) return;
    const lib = try dl.Library.open(&.{ "libxkbcommon.so.0", "libxkbcommon.so" });
    const syms = lib.loadAll(Symbols);
    if (dl.firstMissing(syms, &.{})) |name| {
        std.log.scoped(.xkbcommon).err("libxkbcommon is missing {s}", .{name});
        lib.close();
        return error.MissingSymbol;
    }
    symbols = syms;
}

pub fn isLoaded() bool {
    return symbols != null;
}

pub fn api() *const Symbols {
    return &(symbols orelse @panic("XKB: call XKB.load() first"));
}
