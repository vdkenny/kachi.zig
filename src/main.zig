const std = @import("std");
const EPOLL = std.os.linux.EPOLL;
const MSG = std.os.linux.MSG;

const EventLoop = @import("event_pool.zig").EventLoop;
const TcpListener = @import("event_pool.zig").TcpListener; // refactor: not the best design?

pub fn main() !void {
    var event_loop = try EventLoop.init();
    defer event_loop.deinit();

    const server = try TcpListener.init();
    try event_loop.add(server.file_descriptor);

    while (true) {
        const n = event_loop.wait();

        for (event_loop.events[0..n]) |event| {
            if (event.data.fd == server.file_descriptor) {
                const client = try server.accept();
                event_loop.add(client) catch {};
            } else {
                if (event.events & EPOLL.IN != -1) {
                    var buf: [4096]u8 = undefined;
                    const rc = std.os.linux.recvfrom(event.data.fd, &buf, buf.len, 0, null, null);

                    if (rc == 0) {
                        event_loop.dispatch(event.data.fd);
                    }
                }

                if (event.events & EPOLL.OUT != -1) {
                    const sent = std.os.linux.sendto(event.data.fd, "bye.zig", 7, MSG.NOSIGNAL, null, 0);

                    _ = sent; // todo: properly flush
                }
            }
        }
    }
}
