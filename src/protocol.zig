const std = @import("std");

const ValueTag = enum {
    array,
    bulk_string,
    integer,
};

const ArrayValue = []Value;
const BulkStringValue = []const u8;
const IntegerValue = i64;

const Value = union(ValueTag) {
    array: ArrayValue,
    bulk_string: BulkStringValue,
    integer: IntegerValue,
};

const DeserializeErrors = error{
    IncorrectFirstByte,
    NoCRLF,
} || std.mem.Allocator.Error || std.fmt.ParseIntError;

pub const Serialize = struct {};
pub const Deserialize = struct {
    buf: []u8,
    start: usize,

    pub fn init(request: []u8) Deserialize {
        return .{
            .buf = request,
            .start = 0,
        };
    }

    pub fn read(self: *Deserialize, gpa: std.mem.Allocator) DeserializeErrors!Value {
        const sign = self.buf[self.start];

        self.start += 1;
        return switch (sign) {
            '*' => try self.array(gpa),
            '$' => try self.bulk_string(),
            else => return error.IncorrectFirstByte,
        };
    }

    fn array(self: *Deserialize, gpa: std.mem.Allocator) DeserializeErrors!Value {
        const len = try self.integer();

        if (len.integer <= 0) {
            @panic("TODO: array length is >= 0, prepare response");
        }

        const ulen: u64 = @intCast(len.integer);
        const args = try gpa.alloc(Value, ulen);

        for (0..ulen) |i| {
            const value = try self.read(gpa);
            args[i] = value;
        }

        return .{ .array = args };
    }

    fn bulk_string(self: *Deserialize) DeserializeErrors!Value {
        const len = try self.integer();

        if (len.integer <= 0) {
            @panic("TODO: bulk string length is less than 0, prepare empty string");
        }

        const ulen: u64 = @intCast(len.integer);
        const str = self.buf[self.start..][0..ulen];

        self.start += ulen + 2;

        return .{ .bulk_string = str };
    }

    fn integer(self: *Deserialize) DeserializeErrors!Value {
        var end: usize = 0;

        for (self.buf[self.start..], self.start..) |_, i| {
            if (i >= 2 and self.buf[i - 2] == '\r') {
                end = i - 2;
                break;
            }
        }

        if (end == 0) {
            return error.NoCRLF;
        }

        const int = try std.fmt.parseInt(i64, self.buf[self.start..end], 10);
        self.start += end;

        return .{ .integer = int };
    }
};
