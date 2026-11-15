# Third-party material

All code in this repository is under the MIT licence in [LICENSE](LICENSE). No
third-party source files are vendored. The bindings are written by hand, but their
interface tables (interface names, versions, request and event names, argument
signatures and enum values) follow the protocol and header definitions below, which
keep their own terms.

## Wayland core protocol (wayland.xml)

- Used in: src/wayland_protocol.zig.
- Upstream: <https://gitlab.freedesktop.org/wayland/wayland>, `protocol/wayland.xml`.
- Copyright: as listed in the file's `<copyright>` element (Kristian Høgsberg,
  Intel Corporation, Collabora, Ltd.).
- Licence: MIT (Expat), as stated in that element.

## wayland-protocols: xdg-shell and xdg-decoration

- Used in: src/xdg_shell.zig (`stable/xdg-shell/xdg-shell.xml`) and
  src/xdg_decoration.zig (`unstable/xdg-decoration/xdg-decoration-unstable-v1.xml`).
- Upstream: <https://gitlab.freedesktop.org/wayland/wayland-protocols>.
- Copyright: as listed in each file's `<copyright>` element.
- Licence: MIT (Expat), as stated in those elements.

## libxkbcommon keysym values

- Used in: src/xkbcommon.zig (a few keysym constants, e.g. `XKB_KEY_BackSpace` =
  0xff08, and the function signatures it looks up at run time).
- Upstream: <https://github.com/xkbcommon/libxkbcommon>, `include/xkbcommon/xkbcommon.h`
  and `xkbcommon-keysyms.h`.
- Licence: MIT/X11-style, as stated in libxkbcommon's LICENSE.

## Run-time libraries (not distributed)

`libwayland-client` and `libxkbcommon` are opened with dlopen at run time. They are
not linked or shipped with this package.
