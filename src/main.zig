const std = @import("std");
const EPOLL = std.os.linux.EPOLL;
const MSG = std.os.linux.MSG;

const Client = @import("event_pool.zig").Client;
const EventLoop = @import("event_pool.zig").EventLoop;
const TcpListener = @import("event_pool.zig").TcpListener; // refactor: not the best design?
const Protocol = @import("protocol.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var event_loop = try EventLoop.init();
    defer event_loop.deinit();

    const server = try TcpListener.init(6379);
    var kv: std.StringHashMap([]const u8) = .init(gpa);

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

                    const errno = std.os.linux.errno(bytes);
                    if (errno != .SUCCESS) {
                        if (errno != .AGAIN) {
                            event_loop.dispatch(gpa, client);
                        }
                    } else {
                        var smth: Protocol.Deserialize = .init(client.to_read); // todo: use new deserializer
                        _ = try smth.read(gpa);

                        //     if (response) |v| {
                        //         client.to_send_end = v.len;
                        //         client.to_send = v;
                        //         try event_loop.mod(client, EPOLL.IN | EPOLL.OUT);
                        //     }
                    }
                }

                if (event.events & EPOLL.OUT != -1) {
                    const sent = std.os.linux.sendto(
                        client.file_descriptor,
                        client.to_send[client.to_send_index..client.to_send_end].ptr,
                        client.to_send_end - client.to_send_index,
                        MSG.NOSIGNAL,
                        null,
                        0,
                    );

                    if (std.os.linux.errno(sent) == .SUCCESS) {
                        // event_loop.dispatch(gpa, client);
                    } else if (std.os.linux.errno(sent) == .AGAIN) {
                        try event_loop.mod(client, EPOLL.IN | EPOLL.OUT);
                    }
                }
            }
        }
    }
}
