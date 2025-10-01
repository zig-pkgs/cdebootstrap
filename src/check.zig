const std = @import("std");
const log = std.log.scoped(.check);
const mem = std.mem;
const Sha256 = std.crypto.hash.sha2.Sha256;
const assert = std.debug.assert;
const c = @import("c");
const buf_size = 4 * 1024;

fn checkSum(
    target_maybe: ?[*:0]const u8,
    sum_maybe: ?[*:0]const u8,
    message: ?[*:0]const u8,
) bool {
    return checkSumAllowFail(target_maybe, sum_maybe, message) catch |err| {
        log.err("unexpected checksum failure for {s}: {t}", .{ target_maybe.?, err });
        return false;
    };
}

fn checkSumAllowFail(
    target_maybe: ?[*:0]const u8,
    sum_maybe: ?[*:0]const u8,
    message: ?[*:0]const u8,
) !bool {
    assert(sum_maybe != null);
    assert(target_maybe != null);
    const sum = mem.span(sum_maybe.?);
    const target = mem.span(target_maybe.?);
    c.log_message(c.LOG_MESSAGE_INFO_DOWNLOAD_VALIDATE, message);

    var file = try std.fs.cwd().openFile(target, .{});
    defer file.close();

    var buf_reader: [buf_size]u8 = undefined;
    var buf_hasher: [buf_size]u8 = undefined;

    var reader = file.reader(&buf_reader);
    var sha256_writer: std.Io.Writer.Hashing(Sha256) = .init(&buf_hasher);
    _ = try reader.interface.streamRemaining(&sha256_writer.writer);
    sha256_writer.writer.flush() catch unreachable;
    const target_hash = sha256_writer.hasher.finalResult();
    const hash_hex = std.fmt.bytesToHex(target_hash, .lower);
    return mem.eql(u8, &hash_hex, sum[0..hash_hex.len]);
}

export fn check_deb(
    target: ?[*:0]const u8,
    package: ?*c.di_package,
    message: ?[*:0]const u8,
) c_int {
    assert(package != null);
    return @intFromBool(!checkSum(target, package.?.sha256, message));
}

export fn check_packages(
    target: ?[*:0]const u8,
    ext: ?[*:0]const u8,
    rel: ?*c.di_release,
) c_int {
    assert(target != null);
    assert(ext != null);
    assert(rel != null);

    var buf_name: [64]u8 = undefined;
    var buf_file: [128]u8 = undefined;
    const name = std.fmt.bufPrintZ(&buf_name, "Packages{s}", .{ext.?}) catch |err| {
        log.err("Can't format name: {t}", .{err});
        return 1;
    };
    const file = std.fmt.bufPrintZ(&buf_file, "main/binary-{s}/Packages{s}", .{ c.arch, ext.? }) catch |err| {
        log.err("Can't format file: {t}", .{err});
        return 1;
    };

    const key: c.di_rstring = .{
        .size = @intCast(file.len),
        .string = file.ptr,
    };

    const item: ?*c.di_release_file = @ptrCast(@alignCast(c.di_hash_table_lookup(rel.?.sha256, &key)));
    if (item == null) {
        c.log_text(c.DI_LOG_LEVEL_ERROR, "Can't find checksum for Packages file");
        return 1;
    }

    if (item.?.sum[1] != null) {
        return @intFromBool(!checkSum(target, item.?.sum[1], name.ptr));
    }

    return 1;
}
