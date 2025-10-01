const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.package);
const native_endian = @import("builtin").cpu.arch.endian();
const ar = @import("ar");
const c = @import("c");

const gpa = std.heap.c_allocator;

extern const execute_io_log_handler: fn (file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void;

fn packageExtractSelfBz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        decomp: *c.struct_decompress_bz,
        err: ?anyerror = null,
        file_out: std.fs.File = .{ .handle = -1 },

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            const context: *@This() = @ptrCast(@alignCast(user_data));
            context.file_out = .{ .handle = c.fileno(file) };
            const r = c.decompress_bz(context.decomp, c.fileno(file));
            if (r <= 0) context.err = error.DecompressXz;
        }

        pub fn deinit(self: *@This()) void {
            c.decompress_bz_free(self.decomp);
        }
    };

    const file_reader: *std.fs.File.Reader = @alignCast(@fieldParentPtr("interface", reader));

    var context: Context = .{
        .decomp = c.decompress_bz_new(file_reader.file.handle, len) orelse return error.NotBzStream,
    };
    defer context.deinit();

    const io_info: []const c.execute_io_info = &.{
        .{
            .fd = 0,
            .events = c.POLLOUT,
            .handler = Context.handler,
            .user_data = &context,
        },
        .{
            .fd = 1,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.DI_LOG_LEVEL_OUTPUT),
        },
        .{
            .fd = 2,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.LOG_LEVEL_OUTPUT_STDERR),
        },
    };

    const ret = c.execute_full(command.ptr, io_info.ptr, @intCast(io_info.len));
    if (ret != 0) {
        return error.ExecutionFailure;
    }

    if (context.err) |err| switch (err) {
        error.EndOfStream => {},
        else => |e| {
            context.file_out.close();
            return e;
        },
    };
}

fn packageExtractSelfGz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,
        file_out: std.fs.File = .{ .handle = -1 },

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            var write_buf: [4 * 1024]u8 = undefined;
            var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
            const context: *@This() = @ptrCast(@alignCast(user_data));
            context.file_out = .{ .handle = c.fileno(file) };
            var file_out_writer = context.file_out.writer(&write_buf);
            var decompress: std.compress.flate.Decompress = .init(context.reader, .gzip, &flate_buffer);
            _ = decompress.reader.streamRemaining(&file_out_writer.interface) catch |err| {
                context.err = err;
                return;
            };
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var context: Context = .{ .reader = reader, .limit = .limited(len) };
    defer context.deinit();

    const io_info: []const c.execute_io_info = &.{
        .{
            .fd = 0,
            .events = c.POLLOUT,
            .handler = Context.handler,
            .user_data = &context,
        },
        .{
            .fd = 1,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.DI_LOG_LEVEL_OUTPUT),
        },
        .{
            .fd = 2,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.LOG_LEVEL_OUTPUT_STDERR),
        },
    };

    const ret = c.execute_full(command.ptr, io_info.ptr, @intCast(io_info.len));
    if (ret != 0) {
        return error.ExecutionFailure;
    }

    if (context.err) |err| switch (err) {
        error.EndOfStream => {},
        else => |e| {
            context.file_out.close();
            return e;
        },
    };
}

fn packageExtractSelfXz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,
        file_out: std.fs.File = .{ .handle = -1 },

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            var write_buf: [4 * 1024]u8 = undefined;
            const context: *@This() = @ptrCast(@alignCast(user_data));
            context.file_out = .{ .handle = c.fileno(file) };
            var file_out_writer = context.file_out.writer(&write_buf);
            var decompress = std.compress.xz.Decompress.init(context.reader, gpa, &.{}) catch |err| {
                context.err = err;
                return;
            };
            _ = decompress.reader.streamRemaining(&file_out_writer.interface) catch |err| {
                context.err = err;
                return;
            };
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var context: Context = .{ .reader = reader, .limit = .limited(len) };
    defer context.deinit();

    const io_info: []const c.execute_io_info = &.{
        .{
            .fd = 0,
            .events = c.POLLOUT,
            .handler = Context.handler,
            .user_data = &context,
        },
        .{
            .fd = 1,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.DI_LOG_LEVEL_OUTPUT),
        },
        .{
            .fd = 2,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.LOG_LEVEL_OUTPUT_STDERR),
        },
    };

    const ret = c.execute_full(command.ptr, io_info.ptr, @intCast(io_info.len));
    if (ret != 0) {
        return error.ExecutionFailure;
    }

    if (context.err) |err| switch (err) {
        error.EndOfStream => {},
        else => |e| {
            context.file_out.close();
            return e;
        },
    };
}

fn packageExtractSelfNull(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,
        file_out: std.fs.File = .{ .handle = -1 },

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            var write_buf: [4 * 1024]u8 = undefined;
            const context: *@This() = @ptrCast(@alignCast(user_data));
            context.file_out = .{ .handle = c.fileno(file) };
            var file_out_writer = context.file_out.writer(&write_buf);
            const size = context.limit.toInt().?;
            _ = context.reader.streamExact(&file_out_writer.interface, size) catch |err| {
                context.err = err;
                return;
            };
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var context: Context = .{ .reader = reader, .limit = .limited(len) };
    defer context.deinit();

    const io_info: []const c.execute_io_info = &.{
        .{
            .fd = 0,
            .events = c.POLLOUT,
            .handler = Context.handler,
            .user_data = &context,
        },
        .{
            .fd = 1,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.DI_LOG_LEVEL_OUTPUT),
        },
        .{
            .fd = 2,
            .events = c.POLLIN,
            .handler = execute_io_log_handler,
            .user_data = @ptrFromInt(c.LOG_LEVEL_OUTPUT_STDERR),
        },
    };

    const ret = c.execute_full(command.ptr, io_info.ptr, @intCast(io_info.len));
    if (ret != 0) {
        return error.ExecutionFailure;
    }

    if (context.err) |err| switch (err) {
        error.EndOfStream => {},
        else => |e| {
            context.file_out.close();
            return e;
        },
    };
}

const DEBIAN_BINARY_CONTENT = "2.0\n";

/// Errors that can occur during archive processing.
const PackageExtractError = error{
    /// The file is not a valid 'ar' archive.
    InvalidArchiveFormat,
    /// A member header has an invalid magic number.
    InvalidMemberFormat,
    /// The member size field could not be parsed as a number.
    InvalidMemberSize,
    /// The 'debian-binary' member has an unexpected size or content.
    InvalidDebianBinary,
    /// Missing debian-binary or data file
    InvalidDebianPackage,
};

/// Parses the member size from the ar_hdr.size field.
/// The input is a slice of bytes representing a space-padded ASCII number.
fn parseMemberSize(slice: []const u8) PackageExtractError!usize {
    // Trim any padding spaces from the right.
    const trimmed_slice = std.mem.trimRight(u8, slice, " ");

    // Parse the remaining slice as a base-10 integer.
    // If parsing fails, we map the error to our specific error set.
    return std.fmt.parseUnsigned(usize, trimmed_slice, 10) catch {
        return error.InvalidMemberSize;
    };
}

/// Extracts a data.tar.* member from a Debian package (.deb) file.
/// This function reads an 'ar' archive stream and dispatches to the correct
/// decompressor based on the member name.
///
/// Parameters:
///   fd: The C-style file descriptor for the open .deb file.
///
/// Returns:
///   The integer result from the specific extraction function on success, or an
///   error on failure.
pub fn packageExtractSelf(file: std.fs.File) !void {
    var read_buffer: [4 * 1024]u8 = undefined;
    var file_reader = file.reader(&read_buffer);
    const reader = &file_reader.interface;
    var it = try ar.Iterator.init(gpa, reader);
    defer it.deinit();

    var found_debian_binary: bool = false;
    var found_data_file: bool = false;

    while (try it.next()) |f| {
        // 3. Identify the member and act on it.
        if (std.mem.eql(u8, f.name, "debian-binary")) {
            found_debian_binary = true;
            if (f.size != DEBIAN_BINARY_CONTENT.len) return error.InvalidDebianBinary;
            var info_buf: [DEBIAN_BINARY_CONTENT.len]u8 = undefined;
            var info_writer: std.Io.Writer = .fixed(&info_buf);
            try it.streamRemaining(f, &info_writer);
            if (!std.mem.eql(u8, &info_buf, DEBIAN_BINARY_CONTENT)) {
                return error.InvalidDebianBinary;
            }
        } else if (std.mem.eql(u8, f.name, "data.tar.bz2")) {
            found_data_file = true;
            defer it.unread_file_bytes = 0; // we are using reader directly
            return try packageExtractSelfBz(reader, f.size);
        } else if (std.mem.eql(u8, f.name, "data.tar.gz")) {
            found_data_file = true;
            defer it.unread_file_bytes = 0; // we are using reader directly
            return try packageExtractSelfGz(reader, f.size);
        } else if (std.mem.eql(u8, f.name, "data.tar.xz")) {
            found_data_file = true;
            defer it.unread_file_bytes = 0; // we are using reader directly
            return packageExtractSelfXz(reader, f.size);
        } else if (std.mem.eql(u8, f.name, "data.tar")) {
            found_data_file = true;
            defer it.unread_file_bytes = 0; // we are using reader directly
            return try packageExtractSelfNull(reader, f.size);
        }
    }

    if (!found_data_file or !found_debian_binary) {
        log.err("found_data_file={}, found_debain_binary={}", .{
            found_data_file,
            found_debian_binary,
        });
        return error.InvalidDebianPackage;
    }
}

export fn package_get_local_filename(package: [*c]c.di_package) [*c]const u8 {
    const filename = mem.span(package.*.filename);
    return std.fs.path.basename(filename).ptr;
}

export fn package_extract(package: [*c]c.di_package) c_int {
    const filename = mem.span(package.*.filename);
    log.debug("extract {s} to {s}", .{ filename, c.target_root });

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/var/cache/bootstrap/{s}", .{
        c.target_root,
        std.fs.path.basename(filename),
    }) catch |err| {
        log.err("path name exceeds max allowed: {t}", .{err});
        return -1;
    };

    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        log.err("failed to open file '{s}': {t}", .{ path, err });
        return -1;
    };
    defer file.close();

    packageExtractSelf(file) catch |err| {
        log.err("failed to extract file '{s}': {t}", .{ path, err });
        return -1;
    };

    log.debug("package extraction success {s}", .{filename});
    return 0;
}
