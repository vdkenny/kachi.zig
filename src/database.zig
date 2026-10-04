const std = @import("std");

const KvEntry = struct {
    key: []u8,
    value: []u8,
};

pub const Database = struct {
    items: []KvEntry,
    used: usize,
    capacity: usize,

    pub fn init(gpa: std.mem.Allocator) !*Database {
        const db = try gpa.create(Database);

        db.* = .{
            .items = try gpa.alloc(KvEntry, 10_000),
            .used = 0,
            .capacity = 10_000,
        };

        return db;
    }

    pub fn get(self: *Database, key: []const u8) ?[]u8 {
        for (self.items[0..self.used]) |*entry| {
            if (std.mem.eql(u8, key, entry.key)) {
                return entry.value;
            }
        }

        return null;
    }

    pub fn set(self: *Database, gpa: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        self.items[self.used] = .{
            .key = try gpa.dupe(u8, key),
            .value = try gpa.dupe(u8, value),
        };

        self.used += 1;
    }
};

pub const Query = struct {
    commands: []Command, // todo: pipelining

    pub fn parse(gpa: std.mem.Allocator, str: []const u8, len: usize) !*Query {
        const query = try gpa.create(Query);

        if (str[0] != '*') {
            return error.Protocol;
        }

        const index = std.mem.indexOfScalar(u8, str, '\r') orelse return error.Protocol;
        const length = try std.fmt.parseInt(u32, str[1..index], 10);

        query.* = .{
            .commands = try gpa.alloc(Command, 1),
        };

        const cmd: *Command = try .parse(gpa, str[index + 2 .. len], length);
        query.commands[0] = cmd.*;

        return query;
    }

    pub fn deinit(self: *Query, gpa: std.mem.Allocator) void {
        for (self.commands) |v| {
            gpa.free(v.args);
        }

        gpa.free(self.commands);
        gpa.destroy(self);
    }
};

const Command = struct {
    args: [][]const u8,

    pub fn parse(gpa: std.mem.Allocator, str: []const u8, argc: u32) !*Command {
        const cmd = try gpa.create(Command);
        const args = try gpa.alloc([]const u8, argc);

        var start: usize = 0;
        for (0..argc) |i| {
            const index = std.mem.indexOfScalar(u8, str[start..], '\r') orelse return error.Protocol;
            const length = try std.fmt.parseInt(u32, str[start + 1 .. start + index], 10);

            args[i] = str[start + index + 2 .. start + index + 2 + length];
            start += index + 4 + length;
        }

        cmd.* = .{
            .args = args,
        };

        return cmd;
    }

    pub fn execute(self: *const Command, gpa: std.mem.Allocator, db: *Database) !?[]u8 {
        if (std.mem.eql(u8, self.args[0], "GET")) {
            if (db.get(self.args[1])) |v| {
                return try gpa.dupe(u8, v);
            }
        } else if (std.mem.eql(u8, self.args[0], "SET")) {
            try db.set(gpa, self.args[1], self.args[2]);
        }

        return null;
    }
};

fn hash(key: []const u8) u32 {
    var h: u32 = 0;

    for (key) |v| {
        h = (h + v) * 19;
    }

    return h % 10_000;
}
