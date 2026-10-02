const std = @import("std");

const linux = std.os.linux;
const errno = linux.errno;

const AF = linux.AF;
const SOCK = linux.SOCK;
const EPOLL = linux.EPOLL;

pub const Client = struct {
    file_descriptor: linux.fd_t,
    node: std.DoublyLinkedList.Node = .{},

    to_send: []u8,
    to_send_index: u32 = 0,

    to_read: []u8,
    to_read_index: u32 = 0,

    pub fn init(file_descriptor: linux.fd_t, gpa: std.mem.Allocator) !*Client {
        const client = try gpa.create(Client);

        client.* = .{
            .file_descriptor = file_descriptor,

            .to_send = try gpa.alloc(u8, 8192),
            .to_read = try gpa.alloc(u8, 8192),
        };

        return client;
    }

    pub fn deinit(self: *Client, gpa: std.mem.Allocator) void {
        _ = linux.close(self.file_descriptor);

        gpa.free(self.to_send);
        gpa.free(self.to_read);
        gpa.destroy(self);
    }
};

pub const TcpListener = struct {
    file_descriptor: linux.fd_t,

    pub fn init() !TcpListener {
        const socket = linux.socket(AF.INET, SOCK.STREAM, linux.IPPROTO.TCP);
        if (errno(socket) != .SUCCESS) {
            return error.Socket; // todo: name all error.*'s properly
        }

        _ = linux.setsockopt(@intCast(socket), linux.SOL.SOCKET, linux.SO.REUSEADDR, &.{1}, @sizeOf(linux.socklen_t));

        const addr = linux.sockaddr.in{
            .family = linux.AF.INET,
            .port = std.mem.nativeToBig(u16, 6379),
            .addr = std.mem.nativeToBig(u32, 0),
        };

        if (errno(linux.bind(@intCast(socket), @ptrCast(&addr), @sizeOf(linux.sockaddr.in))) != .SUCCESS) {
            return error.Bind;
        }
        if (errno(linux.listen(@intCast(socket), linux.SOMAXCONN)) != .SUCCESS) {
            return error.Listen;
        }

        return .{
            .file_descriptor = @intCast(socket),
        };
    }

    pub fn accept(self: TcpListener) linux.fd_t {
        while (true) {
            const socket = linux.accept4(self.file_descriptor, null, null, SOCK.NONBLOCK);

            if (socket != -1 and errno(socket) != .INTR) {
                return @intCast(socket);
            }
        }

        return -1;
    }
};

pub const EventLoop = struct {
    file_descriptor: linux.fd_t,

    events: [1024]linux.epoll_event = undefined,
    clients: std.DoublyLinkedList = .{},

    pub fn init() !EventLoop {
        const epoll_fd = linux.epoll_create();
        if (errno(epoll_fd) != .SUCCESS) {
            return error.Create;
        }

        return .{
            .file_descriptor = @intCast(epoll_fd),
        };
    }

    pub fn deinit(self: *EventLoop) void { // todo: we start event_loop only once, does it make sense to clean manually instead of os?
        _ = linux.close(self.file_descriptor);
    }

    pub fn wait(self: *EventLoop) u32 {
        const rc = linux.epoll_wait(self.file_descriptor, &self.events, self.events.len, -1);

        if (errno(rc) == .SUCCESS) {
            return @intCast(rc);
        }

        return 0;
    }

    pub fn add(self: *EventLoop, client: *Client) !void {
        var ev: linux.epoll_event = .{
            .events = EPOLL.IN,
            .data = .{ .ptr = @intFromPtr(client) },
        };

        if (errno(linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_ADD, client.file_descriptor, &ev)) != .SUCCESS) {
            _ = linux.close(client.file_descriptor);

            return error.Add;
        }

        self.clients.append(&client.node);
    }

    pub fn dispatch(self: *EventLoop, client: *Client) void {
        self.clients.remove(&client.node);

        _ = linux.epoll_ctl(self.file_descriptor, EPOLL.CTL_DEL, client.file_descriptor, null); // < linux v2.6.9 requires non-null pointer
        _ = linux.close(client.file_descriptor);
    }
};
