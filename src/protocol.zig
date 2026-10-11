const std = @import("std");

const ValueTag = enum {
    array,
    bulk_string,
    integer,
};

const Value = union(ValueTag) {
    array: []Value,
    bulk_string: []const u8,
    integer: i64,
};

pub const Serialize = struct {};
pub const Deserialize = struct {
    pub fn read(gpa: std.mem.Allocator, request: []const u8) !void {
        switch (request[0]) {
            '*' => try Deserialize.array(gpa, request),
            '$' => Deserialize.bulk_string(gpa, request),
            else => {},
        }
    }

    fn array(gpa: std.mem.Allocator, request: []const u8) ![]Value {
        const len = try Deserialize.integer(request);

        if (len <= 0) {
            @panic("TODO: array length is >= 0, prepare response");
        }

        const args = try gpa.alloc(Value, len);

        for (0..len) |_| {
            const value = Deserialize.read(gpa, request); // todo: track position of request to avoid inf loop
        }

        return args;
    }

    fn bulk_string(gpa: std.mem.Allocator, request: []const u8) Value.bulk_string {
        const len = try Deserialize.integer(request);

        if (len <= 0) {
            @panic("TODO: bulk string length is less than 0, prepare empty string");
        }
    }

    fn integer(request: []const u8) !Value.integer {
        var end: usize = 0;

        for (request, 0..) |v, i| {
            if (v == '\r') {
                end = i;
                break;
            }
        }

        if (end == 0) {
            return error.NoCRLF;
        }

        return std.fmt.parseInt(i64, request[1..end], 10); // 1.. skips first byte
    }
};
