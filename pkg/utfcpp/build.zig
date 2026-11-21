const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "utfcpp",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    linkCxx(b, lib);

    if (target.result.os.tag.isDarwin()) {
        const apple_sdk = @import("apple_sdk");
        try apple_sdk.addPaths(b, lib);
    }

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{});

    lib.addCSourceFiles(.{
        .flags = flags.items,
        .files = &.{"empty.cc"},
    });

    if (b.lazyDependency("utfcpp", .{})) |upstream| {
        lib.addIncludePath(upstream.path(""));
        lib.installHeadersDirectory(
            upstream.path("source"),
            "",
            .{ .include_extensions = &.{".h"} },
        );
    }

    b.installArtifact(lib);

    // {
    //     const test_exe = b.addTest(.{
    //         .name = "test",
    //         .root_source_file = .{ .path = "main.zig" },
    //         .target = target,
    //         .optimize = optimize,
    //     });
    //     test_exe.linkLibrary(lib);
    //
    //     var it = module.import_table.iterator();
    //     while (it.next()) |entry| test_exe.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    //     const tests_run = b.addRunArtifact(test_exe);
    //     const test_step = b.step("test", "Run tests");
    //     test_step.dependOn(&tests_run.step);
    // }
}

/// Zig's bundled libc++ has no illumos port (no thread API, no locale
/// layer), so on illumos C++ is compiled against the system libstdc++.
/// The header directories come from ILLUMOS_CXX_INCLUDE (colon-separated),
/// defaulting to pkgsrc gcc13. They must be -I rather than -isystem so
/// libstdc++'s #include_next finds libc's headers after them.
fn linkCxx(b: *std.Build, step: *std.Build.Step.Compile) void {
    if (step.rootModuleTarget().os.tag != .illumos) {
        step.linkLibCpp();
        return;
    }
    const dirs = b.graph.env_map.get("ILLUMOS_CXX_INCLUDE") orelse
        "/opt/local/gcc13/include/c++/13.4.0:" ++
            "/opt/local/gcc13/include/c++/13.4.0/x86_64-sun-solaris2.11:" ++
            "/opt/local/gcc13/include/c++/13.4.0/backward";
    var it = std.mem.tokenizeScalar(u8, dirs, ':');
    while (it.next()) |d| step.addIncludePath(.{ .cwd_relative = d });
}
