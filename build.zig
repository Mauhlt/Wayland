const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // libc is only needed for dlopen; libwayland / libxkbcommon are loaded at runtime.
    const mod = b.addModule("Wayland", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const mod_tests = b.addTest(.{ .root_module = mod, .name = "wayland-test" });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    // `zig build test -Dtarget=x86_64-linux-gnu` from another OS still compiles and links the tests.
    run_mod_tests.skip_foreign_checks = true;
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Installs zig-out/bin/wayland-test, e.g. to run inside WSL or on another Linux machine.
    const install_tests = b.addInstallArtifact(mod_tests, .{});
    const test_exe_step = b.step("test-exe", "Install the test binary");
    test_exe_step.dependOn(&install_tests.step);
}
