const std = @import("std");
const network = @import("network");
const binutils = @import("zbinutils");
const format = @import("format.zig");
const parse = @import("parse.zig");
const msg = @import("msg.zig");
const enums = @import("enums.zig");
const types = @import("types.zig");

const DEBUG = true;

pub fn debugLog(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG) std.debug.print(fmt, args);
}

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket: network.Socket,
    thread: std.Thread = undefined,
    connection: Connection,
    handlers: Handlers = .{},
    data: Data,

    pub const Connection = struct {
        id: ?i32 = null,
        connected: bool = false,
        terminate: bool = false,
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
        registrationResult: ?*const fn (msg.RegistrationResult) void = null,
        realtimeUpdate: ?*const fn (msg.RealtimeUpdate) void = null,
        realtimeCarUpdate: ?*const fn (msg.RealtimeCarUpdate) void = null,
        entryList: ?*const fn ([]u16) void = null,
        trackData: ?*const fn (msg.TrackData) void = null,
        entryListCar: ?*const fn (msg.EntryListCar) void = null,
        broadcastingEvent: ?*const fn (msg.BroadcastingEvent) void = null,
    };

    pub const InitParams = struct {
        allocator: std.mem.Allocator,
        address: []const u8 = "localhost",
        port: u16 = 9000,
        name: []const u8,
        password: []const u8,
        cmd_password: []const u8 = "",
        update_ms: u16 = 200,
    };

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
        };
        const ums: u32 = @intCast(client.connection.update_ms);
        const us_per_s = std.time.us_per_s;
        const us_per_ms = std.time.us_per_ms;
        try client.socket.setReadTimeout(@min(us_per_s, us_per_ms * ums));
        return client;
    }

    pub fn deinit(self: *@This()) void {
        self.data.car_map.deinit();
        self.socket.close();
        network.deinit();
    }

    pub fn send(self: *@This(), data: []const u8) !void {
        debugLog("Sending bytes: {x:0>2}\n\n", .{data});
        _ = try self.socket.send(data);
    }

    pub fn connect(self: *@This()) !void {
        if (self.connection.connected) return;
        debugLog("Will connect...\n", .{});
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
            debugLog("Nothing to disconnect\n", .{});
            return;
        }
        debugLog("Will disconnect...\n", .{});
        self.send(format.disconnect()) catch return;
        self.connection.connected = false;
        self.connection.id = null;
    }

    pub fn recv(self: *@This()) !void {
        var buf: [1024]u8 = undefined;
        const len = self.socket.receive(&buf) catch |err| switch (err) {
            error.WouldBlock => {
                debugLog("Recv timeout; allow exit\n", .{});
                return;
            },
            else => return err,
        };
        const data = buf[0..len];
        // debugLog("Received {d} bytes: {x:0>2}\n\n", .{ len, data });
        var reader = binutils.Reader{ .buffer = data, .endian = .little };
        const msg_type = try std.meta.intToEnum(enums.MessageType, try reader.read(u8));
        try self.handleMessage(msg_type, &reader);
    }

    fn handleMessage(self: *@This(), msg_type: enums.MessageType, r: *binutils.Reader) !void {
        switch (msg_type) {
            .registration_result => {
                const res = try parse.registrationResult(r);
                {
                    debugLog("Received registration result\n", .{});
                    debugLog("Connection id: {d}\n", .{res.connection_id});
                    debugLog("Success: {?}\n", .{res.success});
                    debugLog("Read only: {?}\n", .{res.read_only});
                    debugLog("Error msg: {s}\n\n", .{res.error_msg orelse ""});
                }
                self.connection.id = res.connection_id;
                self.connection.connected = res.success;
                if (self.handlers.registrationResult) |handler| handler(res);
                if (res.read_only) return;
                try self.requestEntryList();
                try self.requestTrackData();
            },
            .realtime_update => {
                const res = try parse.realtimeUpdate(r);
                {
                    debugLog("Received realtime update\n", .{});
                    debugLog("Session type: {d}\n", .{res.session_type});
                    debugLog("Phase: {d}\n", .{res.phase});
                    debugLog("Session time: {d}\n", .{res.session_time});
                    debugLog("Time of day: {d}\n", .{res.time_of_day});
                    debugLog("Ambient temperature: {d}\n", .{res.ambient_temperature});
                    debugLog("Track temperature: {d}\n\n", .{res.track_temperature});
                }
                if (self.handlers.realtimeUpdate) |handler| handler(res);
            },
            .realtime_car_update => {
                const res = try parse.realtimeCarUpdate(r);
                {
                    debugLog("Received realtime car update\n", .{});
                    debugLog("Car index: {d}\n", .{res.car_index});
                    debugLog("Driver index: {d}\n", .{res.driver_index});
                    debugLog("Gear: {d}\n", .{res.gear});
                    debugLog("Speed kmh: {d}\n\n", .{res.speed_kmh});
                }
                if (self.handlers.realtimeCarUpdate) |handler| handler(res);
            },
            .entry_list => {
                self.data.car_map.clearRetainingCapacity();
                const res = try parse.entryList(self.allocator, r);
                defer self.allocator.free(res);
                for (res) |id| try self.data.car_map.put(id, msg.Car{});
                {
                    debugLog("Received entry list\n", .{});
                    debugLog("Car count: {d}\n\n", .{res.len});
                }
                if (self.handlers.entryList) |handler| handler(res);
            },
            .track_data => {
                const res = try parse.trackData(self.allocator, r);
                // better to return a struct with a deinit function instead of this mess
                // probably do the same for other messages which require frees
                defer {
                    if (res.hud_pages) |m| self.allocator.free(m);
                    if (res.camera_sets.driveable) |m| self.allocator.free(m);
                    if (res.camera_sets.onboard) |m| self.allocator.free(m);
                    if (res.camera_sets.helicam) |m| self.allocator.free(m);
                    if (res.camera_sets.pitlane) |m| self.allocator.free(m);
                    if (res.camera_sets.set_1) |m| self.allocator.free(m);
                    if (res.camera_sets.set_2) |m| self.allocator.free(m);
                    if (res.camera_sets.set_vr) |m| self.allocator.free(m);
                }
                self.connection.id = res.connection_id;
                {
                    debugLog("Received track data\n", .{});
                    debugLog("Connection id: {d}\n", .{res.connection_id});
                    debugLog("Track name: {s}\n", .{res.track_name});
                    debugLog("Track id: {d}\n", .{res.track_id});
                    debugLog("Track length: {d}\n\n", .{res.track_length_m});
                }
                if (self.handlers.trackData) |handler| handler(res);
            },
            .entry_list_car => {
                const res = try parse.entryListCar(self.allocator, r, &self.data.car_map);
                defer self.allocator.free(res.drivers);
                {
                    debugLog("Received entry list car\n", .{});
                    debugLog("Car model type: {d}\n", .{res.car_model_type});
                    debugLog("Team name: {s}\n", .{res.team_name});
                    debugLog("Race number: {d}\n", .{res.race_number});
                    debugLog("Cup category: {d}\n", .{res.cup_category});
                    debugLog("Current driver index: {d}\n", .{res.current_driver_index});
                    debugLog("Nationality: {d}\n\n", .{res.nationality});
                }
                if (self.handlers.entryListCar) |handler| handler(res);
            },
            .broadcasting_event => {
                const res = try parse.broadcastingEvent(r, &self.data.car_map);
                {
                    debugLog("Received broadcasting event\n", .{});
                    debugLog("Type: {d}\n", .{res.type});
                    debugLog("Message: {s}\n", .{res.message});
                    debugLog("Time ms: {d}\n", .{res.time_ms});
                    debugLog("Car id: {d}\n\n", .{res.car_id});
                }
                if (self.handlers.broadcastingEvent) |handler| handler(res);
            },
        }
    }

    fn requestEntryList(self: *@This()) !void {
        if (self.connection.id) |id| {
            debugLog("Will request entry list...\n", .{});
            var writer = try format.requestEntryList(self.allocator, id);
            defer writer.deinit();
            try self.send(writer.asBytes());
        }
    }

    fn requestTrackData(self: *@This()) !void {
        if (self.connection.id) |id| {
            debugLog("Will request track data...\n", .{});
            var writer = try format.requestTrackData(self.allocator, id);
            defer writer.deinit();
            try self.send(writer.asBytes());
        }
    }

    pub fn blockingRecv(self: *@This()) !void {
        defer self.connection.terminate = false;
        while (!self.connection.terminate) {
            debugLog("Waiting for data...\n", .{});
            try self.recv();
        }
        debugLog("\nExiting blocking recv...\n", .{});
    }

    pub fn spawnRecvThread(self: *@This()) !void {
        debugLog("Spawning recv thread...\n\n", .{});
        self.thread = try std.Thread.spawn(.{}, blockingRecv, .{self});
    }

    pub fn joinRecvThread(self: *@This()) void {
        self.thread.join();
        debugLog("Joined recv thread\n", .{});
    }

    pub fn endRecvBlocking(self: *@This()) void {
        self.connection.terminate = true;
    }

    pub fn terminateRecvThread(self: *@This()) void {
        self.endRecvBlocking();
        self.joinRecvThread();
    }
};
