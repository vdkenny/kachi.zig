const std = @import("std");

const ValueTag = enum {
    simple_string,
    simple_error,
    integer,
    bulk_string,
    array,
    null,
};

const SimpleStringValue = []const u8;
const SimpleErrorValue = []const u8;
const IntegerValue = i64;
const BulkStringValue = []const u8;
const ArrayValue = []const Value; // todo: refactor repeating values

pub const Value = union(ValueTag) {
    simple_string: SimpleStringValue,
    simple_error: SimpleErrorValue,
    integer: IntegerValue,
    bulk_string: BulkStringValue,
    array: ArrayValue,
    null: void, // todo: void?
};

const SerializeErrors = error{} || std.Io.Writer.Error;
const DeserializeErrors = error{
    IncorrectFirstByte,
    NoCRLF,
    NegativeLength,
} || std.mem.Allocator.Error || std.fmt.ParseIntError;

pub const Serialize = struct {
    pub fn write(
        value: Value,
        writer: *std.Io.Writer,
    ) SerializeErrors!void {
        try switch (value) {
            .array => |v| Serialize.array(v, writer),
            .bulk_string => |v| Serialize.bulk_string(v, writer),
            .integer => |v| Serialize.integer(v, writer),
            .simple_string => |v| Serialize.simple_string(v, writer),
            .simple_error => |v| Serialize.simple_error(v, writer),
            .null => Serialize._null(writer),
        };
    }

    fn array(value: ArrayValue, writer: *std.Io.Writer) SerializeErrors!void {
        try writer.print("*{d}\r\n", .{value.len});

        for (value) |v| {
            try Serialize.write(v, writer);
        }
    }

    fn bulk_string(value: BulkStringValue, writer: *std.Io.Writer) SerializeErrors!void {
        try writer.print("${d}\r\n{s}\r\n", .{ value.len, value });
    }

    fn integer(value: IntegerValue, writer: *std.Io.Writer) SerializeErrors!void {
        try writer.print(":{d}\r\n", .{value});
    }

    fn simple_string(value: SimpleStringValue, writer: *std.Io.Writer) SerializeErrors!void {
        try writer.print("+{s}\r\n", .{value});
    }

    fn simple_error(value: SimpleErrorValue, writer: *std.Io.Writer) SerializeErrors!void {
        try writer.print("-{s}\r\n", .{value});
    }

    fn _null(writer: *std.Io.Writer) SerializeErrors!void { // todo: do not shadow null?
        try writer.print("_\r\n", .{});
    }
};

pub const Deserialize = struct {
    buf: []const u8,
    start: usize,

    pub fn init(request: []const u8) Deserialize {
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
            return error.NegativeLength; // todo: ignore instead of error? *2 $1 a *-1;
        }

        const ulen: u64 = @intCast(len.integer);
        const args = try gpa.alloc(Value, ulen);

        for (0..ulen) |i| {
            args[i] = try self.read(gpa);
        }

        return .{ .array = args };
    }

    fn bulk_string(self: *Deserialize) DeserializeErrors!Value {
        const len = try self.integer();

        if (len.integer < 0) {
            return error.NegativeLength;
        }

        const ulen: u64 = @intCast(len.integer);
        const str = self.buf[self.start..][0..ulen];

        self.start += ulen + 2; // add 2 to skip CRLF

        return .{ .bulk_string = str };
    }

    fn integer(self: *Deserialize) DeserializeErrors!Value {
        var end: usize = self.start;

        while (end < self.buf.len - 1) {
            if (end >= 2 and self.buf[end - 2] == '\r') {
                end -= 2; // ew?
                break;
            }

            end += 1;
        }

        if (end == self.start) {
            return error.NoCRLF;
        }

        const int = try std.fmt.parseInt(i64, self.buf[self.start..end], 10);
        self.start = end + 2; // add 2 to skip CRLF

        return .{ .integer = int };
    }
};
