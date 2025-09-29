const std = @import("std");

const debian_arch = enum {
    amd64,
    arm64,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const debian_installer_dep = b.dependency("debian_installer", .{
        .target = target,
        .optimize = optimize,
    });

    const debian_installer = debian_installer_dep.artifact("debian-installer");

    const debconfclient_dep = b.dependency("debconfclient", .{
        .target = target,
        .optimize = optimize,
    });

    const config_h = b.addConfigHeader(.{
        .style = .{
            .autoconf_undef = b.path("include/config.h.in"),
        },
        .include_path = "config.h",
    }, .{
        .DPKG_ARCH = @tagName(debian_arch.amd64),
        .HAVE_LIBCURL = true,
        .PACKAGE_BUGREPORT = "https://bugs.debian.org/cdebootstrap",
        .PACKAGE_NAME = "cdebootstrap",
        .PACKAGE_STRING = "cdebootstrap",
        .PACKAGE_TARNAME = "cdebootstrap",
        .PACKAGE_URL = "http://deb.debian.org/debian/pool/main/c/cdebootstrap",
        .PACKAGE_VERSION = "0.7.9",
        .CONFIGDIR = "config",
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/cimport.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addConfigHeader(config_h);
    translate_c.addIncludePath(b.path("include"));
    translate_c.addIncludePath(debian_installer.getEmittedIncludeTree());

    const c_mod = translate_c.createModule();

    const frontend = b.addLibrary(.{
        .name = "frontend",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    frontend.linkSystemLibrary("curl");
    frontend.addConfigHeader(config_h);
    frontend.addIncludePath(b.path("include"));
    frontend.addCSourceFiles(.{
        .root = b.path("src/frontend/standalone"),
        .files = &frontend_standalone,
    });
    frontend.linkLibrary(debconfclient_dep.artifact("debconfclient"));
    frontend.linkLibrary(debian_installer_dep.artifact("debian-installer"));

    const helper = b.addExecutable(.{
        .name = "helper",
        .root_module = b.createModule(.{
            .root_source_file = b.path("helper/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
            },
        }),
    });
    helper.linkSystemLibrary("archive");

    const run = b.addRunArtifact(helper);
    run.addDirectoryArg(b.path("helper"));
    const helper_dir = run.addOutputDirectoryArg("helper");
    b.installDirectory(.{
        .source_dir = helper_dir,
        .install_dir = .{ .custom = "helper" },
        .install_subdir = "",
    });
    b.installDirectory(.{
        .source_dir = b.path("config"),
        .install_dir = .{ .custom = "helper" },
        .install_subdir = "",
    });

    const exe = b.addExecutable(.{
        .name = "cdebootstrap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
            },
        }),
    });
    exe.linkSystemLibrary("z");
    exe.linkSystemLibrary("lzma");
    exe.linkSystemLibrary("bzip2");
    exe.addConfigHeader(config_h);
    exe.addIncludePath(b.path("include"));
    exe.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &cdebootstrap_sources,
    });
    exe.addIncludePath(debian_installer.getEmittedIncludeTree());
    exe.linkLibrary(frontend);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

const frontend_standalone = [_][]const u8{
    "main.c",
    "message.c",
};

const cdebootstrap_sources = [_][]const u8{
    "check.c",
    "decompress_bz.c",
    "decompress_gz.c",
    "decompress_xz.c",
    "decompress_null.c",
    "download.c",
    "execute.c",
    "gpg.c",
    "install.c",
    "log.c",
    "package.c",
    "suite.c",
    "suite_action.c",
    "suite_config.c",
    "suite_packages.c",
    "target.c",
};
