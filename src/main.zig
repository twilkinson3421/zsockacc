const std = @import("std");
const acc = @import("root.zig");

fn handleRegistrationResult(res: acc.msg.RegistrationResult) void {
    acc.debugLog("Received registration result\n", .{});
    acc.debugLog("Connection id: {d}\n", .{res.connection_id});
    acc.debugLog("Success: {?}\n", .{res.success});
    acc.debugLog("Read only: {?}\n", .{res.read_only});
    acc.debugLog("Error msg: {s}\n\n", .{res.error_msg orelse ""});
}

fn handleRealtimeUpdate(res: acc.msg.RealtimeUpdate) void {
    acc.debugLog("Received realtime update\n", .{});
    acc.debugLog("Session type: {d}\n", .{res.session_type});
    acc.debugLog("Phase: {d}\n", .{res.phase});
    acc.debugLog("Session time: {d}\n", .{res.session_time});
    acc.debugLog("Time of day: {d}\n", .{res.time_of_day});
    acc.debugLog("Ambient temperature: {d}\n", .{res.ambient_temperature});
    acc.debugLog("Track temperature: {d}\n\n", .{res.track_temperature});
}

fn handleRealtimeCarUpdate(res: acc.msg.RealtimeCarUpdate) void {
    acc.debugLog("Received realtime car update\n", .{});
    acc.debugLog("Car index: {d}\n", .{res.car_index});
    acc.debugLog("Driver index: {d}\n", .{res.driver_index});
    acc.debugLog("Gear: {d}\n", .{res.gear});
    acc.debugLog("Speed kmh: {d}\n\n", .{res.speed_kmh});
}

fn handleEntryList(res: []u16) void {
    acc.debugLog("Received entry list\n", .{});
    acc.debugLog("Car count: {d}\n\n", .{res.len});
}

fn handleTrackData(res: acc.msg.TrackData) void {
    acc.debugLog("Received track data\n", .{});
    acc.debugLog("Connection id: {d}\n", .{res.connection_id});
    acc.debugLog("Track name: {s}\n", .{res.track_name});
    acc.debugLog("Track id: {d}\n", .{res.track_id});
    acc.debugLog("Track length: {d}\n\n", .{res.track_length_m});
}

fn handleEntryListCar(res: acc.msg.EntryListCar) void {
    acc.debugLog("Received entry list car\n", .{});
    acc.debugLog("Car model type: {d}\n", .{res.car_model_type});
    acc.debugLog("Team name: {s}\n", .{res.team_name});
    acc.debugLog("Race number: {d}\n", .{res.race_number});
    acc.debugLog("Cup category: {d}\n", .{res.cup_category});
    acc.debugLog("Current driver index: {d}\n", .{res.current_driver_index});
    acc.debugLog("Nationality: {d}\n\n", .{res.nationality});
}

fn handleBroadcastingEvent(res: acc.msg.BroadcastingEvent) void {
    acc.debugLog("Received broadcasting event\n", .{});
    acc.debugLog("Type: {d}\n", .{res.type});
    acc.debugLog("Message: {s}\n", .{res.message});
    acc.debugLog("Time ms: {d}\n", .{res.time_ms});
    acc.debugLog("Car id: {d}\n\n", .{res.car_id});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var client = try acc.Client.init(.{
        .allocator = alloc,
        .address = "192.168.1.177",
        .port = 9000,
        .name = "test_client",
        .password = "asd",
        .update_ms = 400,
    });

    client.handlers.registrationResult = &handleRegistrationResult;
    client.handlers.realtimeUpdate = &handleRealtimeUpdate;
    client.handlers.realtimeCarUpdate = &handleRealtimeCarUpdate;
    client.handlers.entryList = &handleEntryList;
    client.handlers.trackData = &handleTrackData;
    client.handlers.entryListCar = &handleEntryListCar;
    client.handlers.broadcastingEvent = &handleBroadcastingEvent;

    defer {
        client.terminateRecvThread();
        client.disconnect();
        client.deinit();
    }

    try client.connect();
    try client.spawnRecvThread();

    std.time.sleep(std.time.ns_per_s * 10); // simulate some time the program is running
}
