const c = @import("c");
const std = @import("std");
const fs = std.fs;
const log = std.log;
const mem = std.mem;
const posix = std.posix;
const time = std.time;
const assert = std.debug.assert;
const Entry = @import("Entry.zig");

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
                var pkg_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer pkg_dir.close();
                var pkg_meta_dir = try pkg_dir.openDir("DEBIAN", .{ .iterate = true });
                defer pkg_meta_dir.close();

                var control_ctx: Context = .{ .gpa = gpa };
                defer control_ctx.deinit();
                try control_ctx.createTarBall(gpa, pkg_meta_dir);

                var data_ctx: Context = .{ .gpa = gpa };
                defer data_ctx.deinit();
                try data_ctx.createTarBall(gpa, pkg_dir);

                const path = try std.fs.path.join(gpa, &.{ outdir, entry.name });
                defer gpa.free(path);

                try createDebianPkg(gpa, path, control_ctx.buffer.items, data_ctx.buffer.items);
            },
            else => {},
        }
    }
}

fn createDebianPkg(gpa: mem.Allocator, path: []const u8, control: []const u8, data: []const u8) !void {
    const filepath = try std.fmt.allocPrintSentinel(gpa, "{s}.deb", .{path}, 0);
    defer gpa.free(filepath);
    // Create the final .deb (ar archive)
    const a = c.archive_write_new();
    defer {
        assert(c.archive_write_close(a) == c.ARCHIVE_OK);
        assert(c.archive_write_free(a) == c.ARCHIVE_OK);
    }
    assert(c.archive_write_set_format_ar_bsd(a) == c.ARCHIVE_OK);
    assert(c.archive_write_open_filename(a, filepath) == c.ARCHIVE_OK);

    {
        // Add debian-binary
        const debian_binary = "2.0\n";
        const entry = c.archive_entry_new();
        defer c.archive_entry_free(entry);

        c.archive_entry_set_pathname(entry, "debian-binary");
        c.archive_entry_set_size(entry, debian_binary.len);
        c.archive_entry_set_filetype(entry, posix.S.IFREG);
        c.archive_entry_set_perm(entry, 0o644);
        c.archive_entry_set_uid(entry, 0);
        c.archive_entry_set_gid(entry, 0);
        assert(c.archive_write_header(a, entry) == c.ARCHIVE_OK);
        assert(c.archive_write_data(a, debian_binary.ptr, debian_binary.len) == debian_binary.len);
    }

    {
        // Add control.tar.gz
        const entry = c.archive_entry_new();
        defer c.archive_entry_free(entry);

        c.archive_entry_set_pathname(entry, "control.tar.gz");
        c.archive_entry_set_size(entry, @intCast(control.len));
        c.archive_entry_set_filetype(entry, posix.S.IFREG);
        c.archive_entry_set_perm(entry, 0o644);
        c.archive_entry_set_uid(entry, 0);
        c.archive_entry_set_gid(entry, 0);
        assert(c.archive_write_header(a, entry) == c.ARCHIVE_OK);
        assert(c.archive_write_data(a, control.ptr, control.len) == control.len);
    }

    {
        // Add data.tar.gz
        const entry = c.archive_entry_new();
        defer c.archive_entry_free(entry);

        c.archive_entry_set_pathname(entry, "data.tar.gz");
        c.archive_entry_set_size(entry, @intCast(data.len));
        c.archive_entry_set_filetype(entry, posix.S.IFREG);
        c.archive_entry_set_perm(entry, 0o644);
        c.archive_entry_set_uid(entry, 0);
        c.archive_entry_set_gid(entry, 0);
        assert(c.archive_write_header(a, entry) == c.ARCHIVE_OK);
        assert(c.archive_write_data(a, data.ptr, data.len) == data.len);
    }
}

const Context = struct {
    gpa: mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,

    fn writeCallback(
        archive: ?*c.struct_archive,
        client_data: ?*anyopaque,
        buffer_ptr: ?*const anyopaque,
        length: usize,
    ) callconv(.c) c.la_ssize_t {
        _ = archive;
        const ctx: *Context = @ptrCast(@alignCast(client_data));
        const data_to_write: [*]const u8 = @ptrCast(@alignCast(buffer_ptr));

        ctx.buffer.appendSlice(ctx.gpa, data_to_write[0..length]) catch return -1;
        return @intCast(length);
    }

    pub fn createTarBall(context: *Context, gpa: mem.Allocator, pkg_meta_dir: fs.Dir) !void {
        const a = c.archive_write_new();
        assert(a != null);
        defer {
            assert(c.archive_write_close(a) == c.ARCHIVE_OK);
            assert(c.archive_write_free(a) == c.ARCHIVE_OK);
        }
        assert(c.archive_write_add_filter_gzip(a) == c.ARCHIVE_OK);
        assert(c.archive_write_set_format_pax_restricted(a) == c.ARCHIVE_OK);

        if (c.archive_write_open2(a, context, null, Context.writeCallback, null, null) != c.ARCHIVE_OK) {
            log.err("Error opening memory for tar.gz creation: {s}", .{c.archive_error_string(a)});
            return error.OpenMemory;
        }

        var walker = try pkg_meta_dir.walk(gpa);
        defer walker.deinit();

        var read_buf: [1024]u8 = undefined;
        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    if (mem.startsWith(u8, entry.path, "DEBIAN")) continue;
                    var allocating: std.Io.Writer.Allocating = .init(gpa);
                    defer allocating.deinit();

                    var file = try entry.dir.openFile(entry.basename, .{});
                    defer file.close();

                    var file_reader = file.reader(&read_buf);
                    const reader = &file_reader.interface;

                    _ = try reader.streamRemaining(&allocating.writer);
                    try allocating.writer.flush();

                    const content = allocating.written();

                    const stat = try posix.fstat(file.handle);

                    var archive_entry: Entry = try .init();
                    defer archive_entry.deinit();
                    archive_entry.setUid(0);
                    archive_entry.setGid(0);
                    archive_entry.setPathName(entry.path);
                    archive_entry.copyStat(&stat);
                    assert(c.archive_write_header(a, archive_entry.inner) == c.ARCHIVE_OK);
                    assert(c.archive_write_data(a, content.ptr, content.len) == content.len);
                },
                else => {},
            }
        }
    }

    pub fn deinit(context: *Context) void {
        context.buffer.deinit(context.gpa);
    }
};
