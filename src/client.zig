const std = @import("std");
const linux = std.os.linux;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const socket = linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0);
    if (linux.errno(socket) != .SUCCESS) {
        return error.Socket;
    }

    const addr: linux.sockaddr.in = .{
        .port = std.mem.nativeToBig(u16, 6379),
        .addr = std.mem.bigToNative(u32, 0x7F000001),
    };

    const connection = linux.connect(@intCast(socket), @ptrCast(&addr), @sizeOf(linux.sockaddr.in));
    if (linux.errno(connection) != .SUCCESS) {
        return error.UnableToConnect;
    }

    const read_buf: []u8 = try gpa.alloc(u8, 2048);
    const buf: []u8 = try gpa.alloc(u8, 2048);

    while (true) {
        _ = linux.write(0, "> ", 2);
        const n = linux.read(0, read_buf.ptr, read_buf.len);

        if (linux.errno(n) != .SUCCESS) {
            continue;
        }

        replace(read_buf, buf); // todo: use protocol.zig -> serializer
        std.debug.print("\x1b[38;5;245m: {any}\n: {any}\n", .{ read_buf[0..n], buf[0..n] });
        std.debug.print("\x1b[0m", .{});
    }
}

fn replace(buf: []u8, dest: []u8) void { // worst way to do ig
    var i: usize = 0;

    for (buf) |v| {
        if (i >= buf.len) break;

        if (v == ' ') {
            @memcpy(dest[i..][0..2], "\r\n");
            i += 1;
        } else {
            dest[i] = v;
        }

        i += 1;
    }
}
