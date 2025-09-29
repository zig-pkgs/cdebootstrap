const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.package);
const native_endian = @import("builtin").cpu.arch.endian();
const c = @import("c");

const gpa = std.heap.c_allocator;

extern const execute_io_log_handler: fn (file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void;

fn packageExtractSelfBz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        decomp: *c.struct_decompress_bz,
        err: ?anyerror = null,

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            const context: *@This() = @ptrCast(@alignCast(user_data));
            const r = c.decompress_bz(context.decomp, c.fileno(file));
            if (r <= 0) {
                context.err = error.DecompressXz;
                std.posix.close(c.fileno(file));
            }
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

    if (context.err) |err| return err;
}

fn packageExtractSelfGz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            const file_out: std.fs.File = .{ .handle = c.fileno(file) };
            var write_buf: [4 * 1024]u8 = undefined;
            var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
            var file_out_writer = file_out.writer(&write_buf);
            const context: *@This() = @ptrCast(@alignCast(user_data));
            var decompress: std.compress.flate.Decompress = .init(context.reader, .gzip, &flate_buffer);
            _ = decompress.reader.streamExact(&file_out_writer.interface, context.limit.toInt().?) catch |err| {
                if (err != error.EndOfStream) {
                    context.err = err;
                    std.posix.close(c.fileno(file));
                }
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
}

fn packageExtractSelfXz(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            const file_out: std.fs.File = .{ .handle = c.fileno(file) };
            var write_buf: [4 * 1024]u8 = undefined;
            var file_out_writer = file_out.writer(&write_buf);
            const context: *@This() = @ptrCast(@alignCast(user_data));
            var decompress = std.compress.xz.Decompress.init(context.reader, gpa, &.{}) catch |err| {
                context.err = err;
                std.posix.close(c.fileno(file));
                return;
            };
            _ = decompress.reader.streamExact(&file_out_writer.interface, context.limit.toInt().?) catch |err| {
                if (err != error.EndOfStream) {
                    context.err = err;
                    std.posix.close(c.fileno(file));
                }
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
}

fn packageExtractSelfNull(reader: *std.Io.Reader, len: usize) !void {
    const command: []const ?[*:0]const u8 = &.{ "tar", "-x", "-C", c.target_root, "-f", "-", null };

    const Context = struct {
        reader: *std.Io.Reader,
        limit: std.Io.Limit,
        err: ?anyerror = null,

        fn handler(file: ?*c.FILE, user_data: ?*anyopaque) callconv(.c) void {
            const file_out: std.fs.File = .{ .handle = c.fileno(file) };
            var write_buf: [4 * 1024]u8 = undefined;
            var file_out_writer = file_out.writer(&write_buf);
            const context: *@This() = @ptrCast(@alignCast(user_data));
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

    if (context.err) |err| return err;
}

// --- Constants for the 'ar' archive format ---
const ARMAG = "!<arch>\n";
const ARFMAG = "`\n";
const DEBIAN_BINARY_CONTENT = "2.0\n";

/// Represents the header for a single member in a Unix 'ar' archive.
/// The @c_packed struct ensures there's no padding, matching the on-disk format.
const ArHdr = extern struct {
    name: [16]u8 align(1),
    date: [12]u8 align(1),
    uid: [6]u8 align(1),
    gid: [6]u8 align(1),
    mode: [8]u8 align(1),
    size: [10]u8 align(1),
    fmag: [2]u8 align(1),
};

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

    // 1. Verify the global archive magic string: "!<arch>\n"
    const magic = try reader.takeArray(ARMAG.len);
    if (!std.mem.eql(u8, magic, ARMAG)) {
        return error.InvalidArchiveFormat;
    }

    // 2. Loop through the members until a 'data.tar.*' is found and extracted.
    while (true) {
        const arh = try reader.takeStruct(ArHdr, native_endian);

        // Verify the member's magic string: "`\n"
        if (!std.mem.eql(u8, &arh.fmag, ARFMAG)) {
            return error.InvalidMemberFormat;
        }

        const member_len = try parseMemberSize(&arh.size);

        // For comparison, trim trailing spaces and the trailing '/' common in some ar variants.
        const member_name = std.mem.trimRight(u8, &arh.name, " /");

        // 3. Identify the member and act on it.
        if (std.mem.eql(u8, member_name, "debian-binary")) {
            if (member_len != DEBIAN_BINARY_CONTENT.len) return error.InvalidDebianBinary;

            const info = try reader.takeArray(DEBIAN_BINARY_CONTENT.len);
            if (!std.mem.eql(u8, info, DEBIAN_BINARY_CONTENT)) {
                return error.InvalidDebianBinary;
            }
        } else if (std.mem.eql(u8, member_name, "data.tar.bz2")) {
            return try packageExtractSelfBz(reader, member_len);
        } else if (std.mem.eql(u8, member_name, "data.tar.gz")) {
            return try packageExtractSelfGz(reader, member_len);
        } else if (std.mem.eql(u8, member_name, "data.tar.xz")) {
            return packageExtractSelfXz(reader, member_len);
        } else if (std.mem.eql(u8, member_name, "data.tar")) {
            return try packageExtractSelfNull(reader, member_len);
        } else {
            // This is not a member we care about, so seek past its data.
            // The 'ar' format requires that each member's data is padded to an
            // even number of bytes.
            const seek_len = member_len + (member_len & 1);
            try reader.discardAll(seek_len);
        }
    }
}

export fn package_get_local_filename(package: [*c]c.di_package) [*c]const u8 {
    const filename = mem.span(package.*.filename);
    return std.fs.path.basename(filename).ptr;
}

export fn package_extract(package: [*c]c.di_package) c_int {
    const filename = mem.span(package.*.filename);

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
    return 0;
}
