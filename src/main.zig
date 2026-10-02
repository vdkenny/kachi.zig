const std = @import("std");
const EPOLL = std.os.linux.EPOLL;
const MSG = std.os.linux.MSG;

const Client = @import("event_pool.zig").Client;
const EventLoop = @import("event_pool.zig").EventLoop;
const TcpListener = @import("event_pool.zig").TcpListener; // refactor: not the best design?

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var event_loop = try EventLoop.init();
    defer event_loop.deinit();

    const server = try TcpListener.init();

    const _srv: *Client = try .init(server.file_descriptor, gpa);
    try event_loop.add(_srv); // refactor: ugly + unneceseary allocation of buffers, aka waste of 16KB?

    while (true) {
        const n = event_loop.wait();

        for (event_loop.events[0..n]) |event| {
            const client: *Client = @ptrFromInt(event.data.ptr);

            if (client.file_descriptor == server.file_descriptor) {
                const new_client: *Client = try .init(server.accept(), gpa); // todo: .accept can be invalid fd_t
                try event_loop.add(new_client);
            } else {
                if (event.events & EPOLL.IN != -1) {
                    const bytes = std.os.linux.recvfrom(client.file_descriptor, client.to_read.ptr, client.to_read.len, 0, null, null);

                    if (bytes == 0) {
                        event_loop.dispatch(client);
                    }
                }

                // if (event.events & EPOLL.OUT != -1) {
                //     _ = std.os.linux.sendto(event.data.ptr.file_descriptor, event.data.ptr.to_send, length, MSG.NOSIGNAL, null, 0);
                // }
            }
        }
    }
}
