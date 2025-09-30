const c = @import("c");
const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.frontend);
const builtin = @import("builtin");

const gpa = std.heap.c_allocator;
extern var mirror: [*:0]const u8;

comptime {
    if (builtin.target.isMuslLibC()) {
        @export(&canonicalizeFileName, .{ .name = "canonicalize_file_name" });
    }
}

fn canonicalizeFileName(target: ?[*:0]u8) callconv(.c) ?[*:0]u8 {
    if (target == null) {
        @branchHint(.unlikely);
        return null;
    }
    const real_path = std.fs.cwd().realpathAlloc(gpa, mem.span(target.?)) catch {
        @branchHint(.unlikely);
        return null;
    };
    defer gpa.free(real_path);
    const real_path_sentinel = gpa.dupeZ(u8, real_path) catch {
        @branchHint(.unlikely);
        return null;
    };
    return real_path_sentinel.ptr;
}

export fn frontend_download(source_cstr: [*c]const u8, target_cstr: [*c]const u8) c_int {
    const source = mem.span(source_cstr);
    const target = mem.span(target_cstr);
    frontendDownload(source, target) catch |err| {
        log.err("failed to download '{s}' from '{s}/{s}': {t}", .{
            target,
            mirror,
            source,
            err,
        });
        return -1;
    };
    return 0;
}

fn frontendDownload(source: []const u8, target: []const u8) !void {
    var buf: [8 * 1024]u8 = undefined;

    var target_file = try std.fs.cwd().createFile(target, .{});
    defer target_file.close();

    var target_file_writer = target_file.writer(&buf);

    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    const url = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ mirror, source });
    defer gpa.free(url);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &target_file_writer.interface,
    });
    try target_file_writer.interface.flush();

    if (result.status != .ok) return error.HttpStatusNotOk;
}
