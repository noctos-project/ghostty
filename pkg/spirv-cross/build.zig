const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("spirv_cross", .{});

    const module = b.addModule("spirv_cross", .{ .root_source_file = b.path("main.zig") });
    module.addIncludePath(upstream.path(""));

    const lib = try buildSpirvCross(b, upstream, target, optimize);
    b.installArtifact(lib);

    if (target.query.isNative()) {
        const test_exe = b.addTest(.{
            .name = "test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_exe.linkLibrary(lib);
        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);

        // Uncomment this if we're debugging tests
        // b.installArtifact(test_exe);
    }
}

fn buildSpirvCross(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = "spirv_cross",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.linkLibC();
    linkCxx(b, lib);
    if (target.result.os.tag.isDarwin()) {
        const apple_sdk = @import("apple_sdk");
        try apple_sdk.addPaths(b, lib);
    }

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{
        "-DSPIRV_CROSS_C_API_GLSL=1",
        "-DSPIRV_CROSS_C_API_MSL=1",

        "-fno-sanitize=undefined",
        "-fno-sanitize-trap=undefined",
    });

    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .flags = flags.items,
        .files = &.{
            // Core
            "spirv_cross.cpp",
            "spirv_parser.cpp",
            "spirv_cross_parsed_ir.cpp",
            "spirv_cfg.cpp",

            // C
            "spirv_cross_c.cpp",

            // GLSL
            "spirv_glsl.cpp",

            // MSL
            "spirv_msl.cpp",
        },
    });

    lib.installHeadersDirectory(
        upstream.path(""),
        "",
        .{ .include_extensions = &.{".h"} },
    );

    return lib;
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
