const std = @import("std");
const network = @import("network");
const binutils = @import("zbinutils");
const format = @import("format.zig");
const parse = @import("parse.zig");
const msg = @import("msg.zig");
const enums = @import("enums.zig");
const types = @import("types.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket: network.Socket,
    thread: std.Thread = undefined,
    connection: Connection,
    handlers: Handlers = .{},
    data: Data,
    debug: bool = false,

    pub const Connection = struct {
        id: ?i32 = null,
        connected: bool = false,
        recv: bool = true,
        address: []const u8 = "localhost",
        port: u16 = 9000,
        name: []const u8,
        password: []const u8,
        cmd_password: []const u8 = "",
        update_ms: u16 = 200,
    };

    pub const Data = struct {
        car_map: types.CarMap,
    };

    pub const Handlers = struct {
        registrationResult: ?*const fn (*Client, msg.RegistrationResult) void = null,
        realtimeUpdate: ?*const fn (*Client, msg.RealtimeUpdate) void = null,
        realtimeCarUpdate: ?*const fn (*Client, msg.RealtimeCarUpdate) void = null,
        entryList: ?*const fn (*Client, []u16) void = null,
        trackData: ?*const fn (*Client, msg.TrackData) void = null,
        entryListCar: ?*const fn (*Client, msg.EntryListCar) void = null,
        broadcastingEvent: ?*const fn (*Client, msg.BroadcastingEvent) void = null,
    };

    pub const InitParams = struct {
        allocator: std.mem.Allocator,
        address: []const u8 = "localhost",
        port: u16 = 9000,
        name: []const u8,
        password: []const u8,
        cmd_password: []const u8 = "",
        update_ms: u16 = 200,
        debug: bool = false,
    };

    pub fn debugPrint(self: *@This(), comptime fmt: []const u8, args: anytype) void {
        if (self.debug) std.debug.print(fmt, args);
    }

    pub fn defaultRecvTimeout(self: *@This()) u32 {
        const ums: u32 = @intCast(self.connection.update_ms);
        const us_per_s = std.time.us_per_s;
        const us_per_ms = std.time.us_per_ms;
        return @min(us_per_s, us_per_ms * ums);
    }

    pub fn init(params: InitParams) !@This() {
        try network.init();
        var client = @This(){
            .allocator = params.allocator,
            .socket = try network.connectToHost(
                params.allocator,
                params.address,
                params.port,
                .udp,
            ),
            .connection = .{
                .address = params.address,
                .port = params.port,
                .name = params.name,
                .password = params.password,
                .cmd_password = params.cmd_password,
                .update_ms = params.update_ms,
            },
            .data = .{ .car_map = types.CarMap.init(params.allocator) },
            .debug = params.debug,
        };
        client.debugPrint("Initialized network features\n", .{});
        client.debugPrint("Opended socket\n", .{});
        try client.socket.setReadTimeout(client.defaultRecvTimeout());
        return client;
    }

    pub fn deinit(self: *@This()) void {
        self.data.car_map.deinit();
        self.socket.close();
        self.debugPrint("Closed socket\n", .{});
        network.deinit();
        self.debugPrint("Network features deinitialized\n", .{});
    }

    pub fn send(self: *@This(), data: []const u8) !void {
        _ = try self.socket.send(data);
    }

    pub fn connect(self: *@This()) !void {
        if (self.connection.connected) return;
        self.debugPrint("Will connect...\n", .{});
        var writer = try format.connect(
            self.allocator,
            self.connection.name,
            self.connection.password,
            self.connection.cmd_password,
            self.connection.update_ms,
        );
        defer writer.deinit();
        try self.send(writer.asBytes());
    }

    pub fn disconnect(self: *@This()) void {
        if (!self.connection.connected) {
            self.debugPrint("Nothing to disconnect\n", .{});
            return;
        }
        self.debugPrint("Will disconnect...\n", .{});
        self.send(format.disconnect()) catch return;
        self.connection.connected = false;
        self.connection.id = null;
    }

    pub fn recv(self: *@This()) !void {
        var buf: [1024]u8 = undefined;
        const len = self.socket.receive(&buf) catch |err| switch (err) {
            error.WouldBlock => {
                self.debugPrint("Recv timeout; allow exit\n", .{});
                return;
            },
            error.ConnectionRefused => {
                self.debugPrint("Connection refused; is ACC running?\n", .{});
                std.time.sleep(self.defaultRecvTimeout());
                return;
            },
            else => return err,
        };
        const data = buf[0..len];
        var reader = binutils.Reader{ .buffer = data, .endian = .little };
        const msg_type = try std.meta.intToEnum(enums.MessageType, try reader.read(u8));
        try self.handleMessage(msg_type, &reader);
    }

    fn handleMessage(self: *@This(), msg_type: enums.MessageType, r: *binutils.Reader) !void {
        switch (msg_type) {
            .registration_result => {
                const res = try parse.registrationResult(r);
                self.connection.id = res.connection_id;
                self.connection.connected = res.success;
                if (self.handlers.registrationResult) |handler| handler(self, res);
                if (res.read_only) return;
                try self.requestEntryList();
                try self.requestTrackData();
            },
            .realtime_update => {
                const res = try parse.realtimeUpdate(r);
                if (self.handlers.realtimeUpdate) |handler| handler(self, res);
            },
            .realtime_car_update => {
                const res = try parse.realtimeCarUpdate(r);
                if (self.handlers.realtimeCarUpdate) |handler| handler(self, res);
            },
            .entry_list => {
                self.data.car_map.clearRetainingCapacity();
                const res = try parse.entryList(self.allocator, r);
                defer self.allocator.free(res);
                for (res) |id| try self.data.car_map.put(id, msg.Car{});
                if (self.handlers.entryList) |handler| handler(self, res);
            },
            .track_data => {
                var res = try parse.trackData(self.allocator, r);
                defer parse.deinitTrackData(self.allocator, &res);
                self.connection.id = res.connection_id;
                if (self.handlers.trackData) |handler| handler(self, res);
            },
            .entry_list_car => {
                const res = try parse.entryListCar(self.allocator, r, &self.data.car_map);
                defer self.allocator.free(res.drivers);
                if (self.handlers.entryListCar) |handler| handler(self, res);
            },
            .broadcasting_event => {
                const res = try parse.broadcastingEvent(r, &self.data.car_map);
                if (self.handlers.broadcastingEvent) |handler| handler(self, res);
            },
        }
    }

    fn requestEntryList(self: *@This()) !void {
        if (self.connection.id) |id| {
            self.debugPrint("Will request entry list...\n", .{});
            var writer = try format.requestEntryList(self.allocator, id);
            defer writer.deinit();
            try self.send(writer.asBytes());
        }
    }

    fn requestTrackData(self: *@This()) !void {
        if (self.connection.id) |id| {
            self.debugPrint("Will request track data...\n", .{});
            var writer = try format.requestTrackData(self.allocator, id);
            defer writer.deinit();
            try self.send(writer.asBytes());
        }
    }

    pub fn blockingRecv(self: *@This()) !void {
        self.debugPrint("Start recv...\n\n", .{});
        defer self.connection.recv = true;
        while (self.connection.recv) {
            try self.recv();
        }
        self.debugPrint("\nExiting blocking recv...\n", .{});
    }

    pub fn spawnRecvThread(self: *@This()) !void {
        self.debugPrint("Spawning recv thread...\n", .{});
        self.thread = try std.Thread.spawn(.{}, blockingRecv, .{self});
    }

    pub fn joinRecvThread(self: *@This()) void {
        self.thread.join();
        self.debugPrint("Joined recv thread\n", .{});
    }

    pub fn endRecvBlocking(self: *@This()) void {
        self.connection.recv = false;
    }

    pub fn terminateRecvThread(self: *@This()) void {
        self.endRecvBlocking();
        self.joinRecvThread();
    }
};
