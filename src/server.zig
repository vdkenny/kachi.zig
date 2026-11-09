const Server = @This();

const EventLoop = @import("event_loop.zig");
const Protocol = @import("protocol.zig");
const Handlers = @import("handlers.zig");
const Client = EventLoop.Client;
const std = @import("std");
const linux = std.os.linux;
const errno = linux.errno;
const EPOLL = linux.EPOLL;

file_descriptor: linux.fd_t = undefined,
ev: EventLoop,

kv: KV,
port: u16 = 6379,

pub const KV = std.StringHashMap([]const u8);

pub fn init(allocator: std.mem.Allocator) EventLoop.Error!Server {
    const ev: EventLoop = try .init(allocator);
    const kv: KV = .init(allocator);

    return .{
        .ev = ev,
        .kv = kv,
    };
}

pub fn listen(self: *Server) Error!void {
    const socket = try call(linux.socket(linux.AF.INET, linux.SOCK.STREAM, linux.IPPROTO.TCP));

    _ = try call(linux.setsockopt(socket, linux.SOL.SOCKET, linux.SO.REUSEADDR, &.{1}, @sizeOf(linux.socklen_t)));

    const addr = linux.sockaddr.in{
        .family = linux.AF.INET,
        .port = std.mem.nativeToBig(u16, self.port),
        .addr = std.mem.bigToNative(u32, 0x7F000001),
    };

    _ = try call(linux.bind(socket, @ptrCast(&addr), @sizeOf(linux.sockaddr.in)));
    _ = try call(linux.listen(socket, linux.SOMAXCONN));

    self.file_descriptor = socket;
    try self.ev.add(socket, null);
}

fn accept(self: *Server) ?linux.fd_t {
    while (true) {
        const rc = linux.accept4(self.file_descriptor, null, null, linux.SOCK.NONBLOCK);

        switch (errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return null,
        }
    }
}

pub fn process(self: *Server, allocator: std.mem.Allocator) void { // todo: allocator as param or in struct?
    const n = self.ev.wait();
    const events = self.ev.events[0..n];

    for (events) |event| {
        const file_descriptor = event.data.fd;

        if (file_descriptor == self.file_descriptor) {
            const connection = self.accept();

            if (connection) |v| {
                const client = Client.init(allocator, v) catch {
                    _ = linux.close(v);
                    continue;
                };
                self.ev.add(v, client) catch {
                    client.deinit(allocator);
                    continue;
                };
            }
        }

        const client = self.ev.clients[@intCast(file_descriptor)];
        if (client) |v| { // todo: decouple read & write
            if (event.events & (EPOLL.ERR | EPOLL.HUP) != 0)
                self.ev.dispatch(allocator, v);

            if (event.events & EPOLL.IN != 0) {
                const bytes = linux.recvfrom(file_descriptor, v.buffer.ptr, v.buffer.len, 0, null, null);

                switch (errno(bytes)) {
                    .SUCCESS => {
                        if (bytes == 0) {
                            self.ev.dispatch(allocator, v);
                            continue;
                        }

                        var deserialize: Protocol.Deserialize = .init(v.buffer[0..bytes]);
                        const request = deserialize.read(allocator) catch {
                            continue;
                        }; // todo: move deserializer errors to handlers-level?

                        Handlers.execute(self.kv, &v.writer.writer, request);

                        const reply = v.writer.written();
                        const sent = linux.sendto(v.file_descriptor, reply.ptr, reply.len, linux.MSG.NOSIGNAL, null, 0); // todo: decouple & handle partial reads & writes

                        _ = v.writer.writer.consume(sent); // todo: consumed bytes & sent errno
                    },
                    .AGAIN, .INTR => {},
                    else => self.ev.dispatch(allocator, v),
                }
            }

            if (event.events & EPOLL.OUT != 0) {}
        }
    }
}

fn call(rc: usize) Error!i32 {
    return switch (errno(rc)) {
        .SUCCESS => @intCast(rc),
        .ACCES => error.AccessDenied,
        .ADDRINUSE => error.AddressInUse,
        .NOBUFS, .NOMEM => error.OutOfMemory,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        else => error.Unexpected,
    };
}

pub const Error = error{
    AccessDenied,
    AddressInUse,
    OutOfMemory,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    Unexpected,
} || EventLoop.Error; // todo: not sure if merging with ev errors is a good idea
