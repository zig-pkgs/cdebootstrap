const std = @import("std");
const mem = std.mem;
const ar = @import("ar.zig");
const tar = @import("tar.zig");

pub fn main() !void {
    const helperdir = mem.span(std.os.argv[1]);
    const outdir = mem.span(std.os.argv[2]);

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa_state.deinit() != .ok) @panic("mem leak");

    const gpa = gpa_state.allocator();

    var dir = try std.fs.cwd().openDir(helperdir, .{ .iterate = true });
    defer dir.close();

    var dir_it = dir.iterate();
    while (try dir_it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                if (mem.eql(u8, entry.name, "src")) continue;
                var pkg_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer pkg_dir.close();
                var pkg_meta_dir = try pkg_dir.openDir("DEBIAN", .{ .iterate = true });
                defer pkg_meta_dir.close();

                const control = try createTarBall(gpa, pkg_meta_dir);
                defer gpa.free(control);
                const data = try createTarBall(gpa, pkg_dir);
                defer gpa.free(data);

                const path = try std.fs.path.join(gpa, &.{ outdir, entry.name });
                defer gpa.free(path);

                try createDebianPkg(gpa, path, control, data);
            },
            else => {},
        }
    }
}

fn createDebianPkg(gpa: mem.Allocator, path: []const u8, control: []const u8, data: []const u8) !void {
    var write_buf: [4 * 1024]u8 = undefined;
    const filepath = try std.fmt.allocPrintSentinel(gpa, "{s}.deb", .{path}, 0);
    defer gpa.free(filepath);
    var file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();

    var file_writer = file.writer(&write_buf);

    var ar_writer: ar.Writer = try .init(&file_writer.interface);
    try ar_writer.addFileFromBytes("debian-binary", "2.0\n", .{
        .mtime = std.time.timestamp(),
        .mode = 0o644,
    });
    try ar_writer.addFileFromBytes("control.tar.gz", control, .{
        .mtime = std.time.timestamp(),
        .mode = 0o644,
    });
    try ar_writer.addFileFromBytes("data.tar.gz", data, .{
        .mtime = std.time.timestamp(),
        .mode = 0o644,
    });

    try file_writer.interface.flush();
}

fn createTarBall(gpa: mem.Allocator, pkg_meta_dir: std.fs.Dir) ![]u8 {
    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();

    var walker = try pkg_meta_dir.walk(gpa);
    defer walker.deinit();

    var read_buf: [1024]u8 = undefined;
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (mem.startsWith(u8, entry.path, "DEBIAN")) continue;

                var file = try entry.dir.openFile(entry.basename, .{});
                defer file.close();

                const stat = try std.posix.fstat(file.handle);

                var file_reader = file.reader(&read_buf);
                const reader = &file_reader.interface;

                var tar_writer: tar.Writer = .{ .underlying_writer = &allocating.writer };
                try tar_writer.writeFileStream(entry.path, @intCast(stat.size), reader, .{
                    .uid = 0,
                    .gid = 0,
                    .mode = stat.mode,
                });
            },
            else => {},
        }
    }

    return try allocating.toOwnedSlice();
}
