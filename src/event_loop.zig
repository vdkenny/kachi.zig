const EventLoop = @This();

const std = @import("std");
const linux = std.os.linux;
const errno = linux.errno;
const EPOLL = linux.EPOLL;

file_descriptor: linux.fd_t,

events: [1024]linux.epoll_event = undefined,
clients: []?*Client,

pub fn init(allocator: std.mem.Allocator) Error!EventLoop {
    const file_descriptor = try call(linux.epoll_create());

    const clients = try allocator.alloc(?*Client, 10240); // todo: config maxclients & overflow
    @memset(clients, null);

    return .{
        .file_descriptor = file_descriptor,
        .clients = clients,
    };
}

pub fn deinit(self: *EventLoop) void {
    _ = linux.close(self.file_descriptor);
}

pub fn wait(self: *EventLoop) u32 {
    const rc = linux.epoll_wait(self.file_descriptor, &self.events, self.events.len, -1);

    if (errno(rc) == .SUCCESS) {
        return @intCast(rc);
    }

    return 0;
}

pub fn add(self: *EventLoop, file_descriptor: linux.fd_t, client: ?*Client) Error!void {
    var ev: linux.epoll_event = .{
        .events = EPOLL.IN,
        .data = .{ .fd = file_descriptor },
    };

    _ = try call(linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_ADD, file_descriptor, &ev));

    if (client) |v| {
        self.clients[@intCast(v.file_descriptor)] = v; // todo: 2x intcast, get rid of
    }
}

pub fn mod(self: *EventLoop, file_descriptor: linux.fd_t, events: u32) Error!void {
    var ev: linux.epoll_event = .{
        .events = events,
        .data = .{ .fd = file_descriptor },
    };

    _ = try call(linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_MOD, file_descriptor, &ev));
}

pub fn dispatch(self: *EventLoop, gpa: std.mem.Allocator, client: *Client) void {
    _ = linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_DEL, client.file_descriptor, null); // < linux v2.6.9 requires non-null pointer
    _ = linux.close(client.file_descriptor);

    self.clients[@intCast(client.file_descriptor)] = null; // todo: 3x intcast get, rid of
    client.deinit(gpa);
}

pub const Error = error{
    OutOfMemory,
    UserResourceLimitReached,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    Unexpected,
} || std.mem.Allocator.Error;

fn call(rc: usize) Error!i32 {
    return switch (errno(rc)) {
        .SUCCESS => @intCast(rc),
        .NOMEM => error.OutOfMemory,
        .NOSPC => error.UserResourceLimitReached,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        else => error.Unexpected,
    };
}

pub const Client = struct {
    file_descriptor: linux.fd_t,

    writer: std.Io.Writer.Allocating,
    buffer: []u8,
    end: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, file_descriptor: linux.fd_t) Error!*Client {
        const client = try gpa.create(Client);

        client.* = .{
            .file_descriptor = file_descriptor,
            .writer = .init(gpa),
            .buffer = try gpa.alloc(u8, 8192),
        };

        return client;
    }

    pub fn deinit(self: *Client, gpa: std.mem.Allocator) void {
        _ = linux.close(self.file_descriptor);

        self.writer.deinit();
        gpa.free(self.buffer);

        gpa.destroy(self);
    }
};
