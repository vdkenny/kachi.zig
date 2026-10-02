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
    bulk_string,
    // null_bulk_string,
    // array,
};
const Query = struct {
    command: []u8,
    type: Type,

    pub fn init(str: []const u8) !Query {
        switch (str[0]) {
            '$' => Type.bulk_string,
        }

        return .{};
    }
};

fn hash(key: []const u8) u32 {
    var h: u32 = 0;

    for (key) |v| {
        h = (h + v) * 38;
    }

    return h;
}
