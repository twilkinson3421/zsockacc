const std = @import("std");
const acc = @import("root.zig");

fn handleRegistrationResult(client: *acc.Client, res: acc.msg.RegistrationResult) void {
    client.debugPrint("Received registration result\n", .{});
    client.debugPrint("Connection id: {d}\n", .{res.connection_id});
    client.debugPrint("Success: {?}\n", .{res.success});
    client.debugPrint("Read only: {?}\n", .{res.read_only});
    client.debugPrint("Error msg: {s}\n\n", .{res.error_msg orelse ""});
}

fn handleRealtimeUpdate(client: *acc.Client, res: acc.msg.RealtimeUpdate) void {
    client.debugPrint("Received realtime update\n", .{});
    client.debugPrint("Session type: {d}\n", .{res.session_type});
    client.debugPrint("Phase: {d}\n", .{res.phase});
    client.debugPrint("Session time: {d}\n", .{res.session_time});
    client.debugPrint("Time of day: {d}\n", .{res.time_of_day});
    client.debugPrint("Ambient temperature: {d}\n", .{res.ambient_temperature});
    client.debugPrint("Track temperature: {d}\n\n", .{res.track_temperature});
}

fn handleRealtimeCarUpdate(client: *acc.Client, res: acc.msg.RealtimeCarUpdate) void {
    client.debugPrint("Received realtime car update\n", .{});
    client.debugPrint("Car index: {d}\n", .{res.car_index});
    client.debugPrint("Driver index: {d}\n", .{res.driver_index});
    client.debugPrint("Gear: {d}\n", .{res.gear});
    client.debugPrint("Speed kmh: {d}\n\n", .{res.speed_kmh});
}

fn handleEntryList(client: *acc.Client, res: []u16) void {
    client.debugPrint("Received entry list\n", .{});
    client.debugPrint("Car count: {d}\n\n", .{res.len});
}

fn handleTrackData(client: *acc.Client, res: acc.msg.TrackData) void {
    client.debugPrint("Received track data\n", .{});
    client.debugPrint("Connection id: {d}\n", .{res.connection_id});
    client.debugPrint("Track name: {s}\n", .{res.track_name});
    client.debugPrint("Track id: {d}\n", .{res.track_id});
    client.debugPrint("Track length: {d}\n\n", .{res.track_length_m});
}

fn handleEntryListCar(client: *acc.Client, res: acc.msg.EntryListCar) void {
    client.debugPrint("Received entry list car\n", .{});
    client.debugPrint("Car model type: {d}\n", .{res.car_model_type});
    client.debugPrint("Team name: {s}\n", .{res.team_name});
    client.debugPrint("Race number: {d}\n", .{res.race_number});
    client.debugPrint("Cup category: {d}\n", .{res.cup_category});
    client.debugPrint("Current driver index: {d}\n", .{res.current_driver_index});
    client.debugPrint("Nationality: {d}\n\n", .{res.nationality});
}

fn handleBroadcastingEvent(client: *acc.Client, res: acc.msg.BroadcastingEvent) void {
    client.debugPrint("Received broadcasting event\n", .{});
    client.debugPrint("Type: {d}\n", .{res.type});
    client.debugPrint("Message: {s}\n", .{res.message});
    client.debugPrint("Time ms: {d}\n", .{res.time_ms});
    client.debugPrint("Car id: {d}\n\n", .{res.car_id});
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
        .debug = true,
    });

    client.setRegistrationResultCallback(&handleRegistrationResult);
    client.setRealtimeUpdateCallback(&handleRealtimeUpdate);
    client.setRealtimeCarUpdateCallback(&handleRealtimeCarUpdate);
    client.setEntryListCallback(&handleEntryList);
    client.setTrackDataCallback(&handleTrackData);
    client.setEntryListCarCallback(&handleEntryListCar);
    client.setBroadcastingEventCallback(&handleBroadcastingEvent);

    defer {
        client.terminateRecvThread();
        client.disconnect();
        client.deinit();
    }

    try client.connect();
    try client.spawnRecvThread();

    std.time.sleep(std.time.ns_per_s * 10); // simulate some time the program is running
}
