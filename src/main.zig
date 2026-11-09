const std = @import("std");
const Server = @import("server.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena;

    var server: Server = try .init(gpa);
    try server.listen();

    while (true) {
        server.process(arena.allocator());
    }
}
