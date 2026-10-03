const std = @import("std");

const KvEntry = struct {
    key: []u8,
    value: []u8,
};

pub const Database = struct {
    items: []KvEntry,
    capacity: usize,

    pub fn get(self: *Database, key: []u8) ?[]u8 {
        for (self.items) |entry| {
            if (std.mem.eql(u8, key, entry.key)) {
                return entry.value;
            }
        }

        return null;
    }
};

const Type = enum {
    // simple_string,
    // simple_error,
    // integer,
    // bulk_string,
    // null_bulk_string,
    array,
};
pub const Query = struct {
    type: Type,
    commands: []Command,

    pub fn parse(str: []const u8) !Query {
        const query_type = switch (str[0]) {
            '*' => Type.array,
            else => return error.Protocol,
        };

        // const length = try std.fmt.parseInt(u32, str[..], 10);
        //
        // const commands = switch (query_type) {
        //     Type.array => &Query.array(length),
        // };

        std.debug.print("{s} : {}\n", .{ @tagName(query_type), 0 });

        return .{
            .type = query_type,
            .commands = &.{},
        };
    }

    pub fn execute(self: *Query) !void {
        for (self.commands) |command| {
            command.execute();
        }
    }

    fn array(length: u32) void {
        _ = length;
    }
};

const Command = struct {
    type: enum {
        get,
        set,
    },
    args: []void,

    pub fn parse(str: []const u8) !Command {
        _ = str;
    }
    pub fn execute(self: *Command) void {
        _ = self;
    }
};

fn hash(key: []const u8) u32 {
    var h: u32 = 0;

    for (key) |v| {
        h = (h + v) * 38;
    }

    return h;
}
