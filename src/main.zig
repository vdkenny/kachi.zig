const std = @import("std");

const AF = std.os.linux.AF;
const SOCK = std.os.linux.SOCK;
const IPRROTO = std.os.linux.IPPROTO;
const EPOLL = std.os.linux.EPOLL;
const MSG = std.os.linux.MSG;
const SOL = std.os.linux.SOL;
const SO = std.os.linux.SO;
const errno = std.os.linux.errno;
const sockaddr = std.os.linux.sockaddr;

const TcpListener = struct {
    socket: i32,

    pub fn init() !TcpListener {
        const socket = std.os.linux.socket(AF.INET, SOCK.STREAM, IPRROTO.TCP);
        if (errno(socket) != .SUCCESS) {
            return error.Socket;
        }

        _ = std.os.linux.setsockopt(@intCast(socket), SOL.SOCKET, SO.REUSEADDR, &.{1}, @sizeOf(std.os.linux.socklen_t));

        const addr = sockaddr.in{
            .family = AF.INET,
            .port = std.mem.nativeToBig(u16, 6379),
            .addr = std.mem.nativeToBig(u32, 0),
        };

        if (errno(std.os.linux.bind(@intCast(socket), @ptrCast(&addr), @sizeOf(sockaddr.in))) != .SUCCESS) {
            return error.Bind;
        }
        if (errno(std.os.linux.listen(@intCast(socket), std.os.linux.SOMAXCONN)) != .SUCCESS) {
            return error.Listen;
        }

        return .{
            .socket = @intCast(socket),
        };
    }

    pub fn accept(self: TcpListener) !std.os.linux.fd_t {
        const connection = std.os.linux.accept4(self.socket, null, null, SOCK.NONBLOCK);

        if (errno(connection) == .SUCCESS) { // todo: treat enetdown, eproto, etc. as eagain retry & epoll.
            return @intCast(connection);
        }

        return -1;
    }
};

pub fn main() !void {
    const epoll_fd: std.os.linux.fd_t = block: {
        const status = std.os.linux.epoll_create();
        if (errno(status) != .SUCCESS) {
            return error.Create;
        }

        break :block @intCast(status);
    };
    defer _ = std.os.linux.close(epoll_fd);

    var events: [1024]std.os.linux.epoll_event = undefined;
    const server = try TcpListener.init();

    var ev: std.os.linux.epoll_event = .{
        .events = EPOLL.IN,
        .data = .{ .fd = server.socket },
    };
    _ = std.os.linux.epoll_ctl(epoll_fd, EPOLL.CTL_ADD, server.socket, &ev);

    while (true) {
        const n = std.os.linux.epoll_wait(epoll_fd, &events, events.len, 10_000);

        for (0..n) |i| {
            const event = events[i];

            std.debug.print("{}: {}\n", .{ event.events & EPOLL.IN != 1, event.events & EPOLL.OUT != 1 });

            if (event.data.fd == server.socket) {
                const client = try server.accept();

                ev = .{
                    .events = EPOLL.IN | EPOLL.OUT,
                    .data = .{ .fd = client },
                };
                if (errno(std.os.linux.epoll_ctl(epoll_fd, EPOLL.CTL_ADD, client, &ev)) != .SUCCESS) {
                    _ = std.os.linux.close(client);
                }
            } else if (event.events & EPOLL.IN != -1) {
                var buf: [4096]u8 = undefined;
                const read = std.os.linux.recvfrom(event.data.fd, &buf, buf.len, 0, null, null);

                if (errno(read) != .AGAIN) { // .AGAIN also means EWOULDBLOCK
                    _ = std.os.linux.epoll_ctl(epoll_fd, EPOLL.CTL_DEL, event.data.fd, null); // < linux v2.6.9 requires non-null pointer
                    _ = std.os.linux.close(event.data.fd); // fixme: we close socket even if socket is still writable.
                }
            } else if (event.events & EPOLL.OUT != -1) {
                const sent = std.os.linux.sendto(event.data.fd, "bye.zig", 7, MSG.NOSIGNAL, null, 0);

                _ = sent; // todo: properly flush
            }
        }
    }
}
