const std = @import("std");
const Protocol = @import("protocol.zig");
const Serialize = Protocol.Serialize;
const Value = Protocol.Value;
const KV = @import("server.zig").KV;

const Command = enum {
    get,
    set,
    ping,
};
const Error = error{
    NoRequest,
    Unknown,
};

pub fn command_from_value(value: Value) Error!Command {
    if (value != .array) {
        return error.NoRequest;
    }

    const array = value.array;
    if (array[0] != .bulk_string) {
        return error.NoRequest;
    }

    const name = array[0].bulk_string;

    if (std.mem.eql(u8, name, "GET")) { // todo: case insensitive
        return .get;
    } else if (std.mem.eql(u8, name, "SET")) {
        return .set;
    } else if (std.mem.eql(u8, name, "PING")) {
        return .ping;
    } else {
        return error.Unknown;
    }
}

pub fn execute(kv: KV, writer: *std.Io.Writer, value: Value) void {
    const command = command_from_value(value) catch {
        Serialize.write(.{ .simple_error = "ERR unknown command" }, writer) catch {};

        return;
    };

    switch (command) {
        .get => get(kv, writer, value),
        .set => set(kv, writer, value),
        .ping => ping(writer, value),
    }
}

// todo: is writing errors directly to client in handlers desirable?
fn get(kv: KV, writer: *std.Io.Writer, value: Value) void {
    const array = value.array;

    if (array.len < 2) {
        Serialize.write(.{ .simple_error = "ERR no key specified" }, writer) catch {};
        return;
    }

    const key = array[1];
    const data = kv.get(key.bulk_string);

    if (data) |v| {
        Serialize.write(.{ .bulk_string = v }, writer) catch {};
    } else {
        Serialize.write(.null, writer) catch {};
    }
}

fn set(kv: KV, writer: *std.Io.Writer, value: Value) void {
    _ = .{ kv, writer, value };
    @panic("TODO: handlers.set");
}

fn ping(writer: *std.Io.Writer, value: Value) void {
    _ = .{ writer, value };
    @panic("TODO: handlers.ping");
}
