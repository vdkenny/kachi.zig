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
    file_descriptor: i32,

    pub fn init() !TcpListener {
        const socket = std.os.linux.socket(AF.INET, SOCK.STREAM, IPRROTO.TCP);
        if (errno(socket) != .SUCCESS) {
            return error.Socket; // todo: name all error.*'s properly
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
            .file_descriptor = @intCast(socket),
        };
    }

    pub fn accept(self: TcpListener) !std.os.linux.fd_t {
        while (true) {
            const socket = std.os.linux.accept4(self.file_descriptor, null, null, SOCK.NONBLOCK);

            if (socket != -1 and errno(socket) != .INTR) {
                return @intCast(socket);
            }
        }

        return -1;
    }

    pub fn recv() void {}
    pub fn send() void {}
};

const Client = struct {
    file_descriptor: std.os.linux.fd_t,

    query_buf: []u8,
    query_pos: usize,

    response_buf: []u8,
    response_pos: usize,
};

const EventLoop = struct {
    file_descriptor: std.os.linux.fd_t,

    events: [512]std.os.linux.epoll_event = undefined,
    // clients: []Client,

    pub fn init() !EventLoop {
        const epoll_fd = std.os.linux.epoll_create();
        if (errno(epoll_fd) != .SUCCESS) {
            return error.Create;
        }

        return .{
            .file_descriptor = @intCast(epoll_fd),
        };
    }

    pub fn deinit(self: *EventLoop) void {
        _ = std.os.linux.close(self.file_descriptor);
    }

    pub fn wait(self: *EventLoop) u32 {
        const rc = std.os.linux.epoll_wait(self.file_descriptor, &self.events, self.events.len, -1);

        if (errno(rc) == .SUCCESS) {
            return @intCast(rc);
        }

        return 0;
    }

    pub fn add(self: *EventLoop, file_descriptor: std.os.linux.fd_t) !void {
        var ev: std.os.linux.epoll_event = .{
            .events = EPOLL.IN,
            .data = .{ .fd = file_descriptor },
        };

        if (errno(std.os.linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_ADD, file_descriptor, &ev)) != .SUCCESS) {
            _ = std.os.linux.close(file_descriptor);
            return error.Add;
        }
    }
    pub fn dispatch(self: *EventLoop, file_descriptor: std.os.linux.fd_t) void {
        _ = std.os.linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_DEL, file_descriptor, null); // < linux v2.6.9 requires non-null pointer
        _ = std.os.linux.close(file_descriptor);
    }
};

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
