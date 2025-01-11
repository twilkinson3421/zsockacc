const std = @import("std");
const binutils = @import("zbinutils");
const util = @import("zutil");
const msg = @import("msg.zig");
const enums = @import("enums.zig");

pub fn parseLap(reader: *binutils.Reader) !msg.Lap {
    var lap = msg.Lap{};
    lap.laptime_ms = try reader.read(i32);
    if (lap.laptime_ms == std.math.maxInt(i32)) lap.laptime_ms = null;
    lap.car_index = try reader.read(u16);
    lap.driver_index = try reader.read(u16);
    var split_count = try reader.read(u8);
    while (split_count > 0) : (split_count -= 1) {
        const split = try reader.read(i32);
        lap.splits[3 - split_count] = if (split == std.math.maxInt(i32)) null else split;
    }
    lap.invalid = try reader.read(u8) != 0;
    lap.valid_for_best = try reader.read(u8) != 0;
    lap.out_lap = try reader.read(u8) != 0;
    lap.in_lap = try reader.read(u8) != 0;
    return lap;
}

pub fn parseDriver(reader: *binutils.Reader) !msg.Driver {
    return msg.Driver{
        .first_name = try reader.readBytesWithLen(u16),
        .last_name = try reader.readBytesWithLen(u16),
        .short_name = try reader.readBytesWithLen(u16),
        .category = try reader.read(u8),
        .nationality = try reader.read(u16),
    };
}

pub fn registrationResult(reader: *binutils.Reader) !msg.RegistrationResult {
    return msg.RegistrationResult{
        .connection_id = try reader.read(i32),
        .success = try reader.read(u8) != 0,
        .read_only = try reader.read(u8) != 0,
        .error_msg = try reader.readBytesWithLen(u16),
    };
}

pub fn realtimeUpdate(reader: *binutils.Reader) !msg.RealtimeUpdate {
    var is_replay_playing = false;
    return msg.RealtimeUpdate{
        .event_index = try reader.read(u16),
        .session_index = try reader.read(u16),
        .session_type = try reader.read(u8),
        .phase = try reader.read(u8),
        .session_time = try reader.read(f32),
        .session_end_time = try reader.read(f32),
        .focused_car_index = try reader.read(i32),
        .active_camera_set = try reader.readBytesWithLen(u16),
        .active_camera = try reader.readBytesWithLen(u16),
        .current_hud_page = try reader.readBytesWithLen(u16),
        .is_replay_playing = util.andCopy(bool, &is_replay_playing, try reader.read(u8) != 0),
        .replay_session_time = if (is_replay_playing) try reader.read(f32) else null,
        .replay_remaining_time = if (is_replay_playing) try reader.read(f32) else null,
        .time_of_day = try reader.read(f32),
        .ambient_temperature = try reader.read(u8),
        .track_temperature = try reader.read(u8),
        .clouds = @as(f32, @floatFromInt(try reader.read(u8))) / 10,
        .rain_level = @as(f32, @floatFromInt(try reader.read(u8))) / 10,
        .wetness = @as(f32, @floatFromInt(try reader.read(u8))) / 10,
        .best_session_lap = try parseLap(reader),
    };
}

pub fn realtimeCarUpdate(reader: *binutils.Reader) !msg.RealtimeCarUpdate {
    return msg.RealtimeCarUpdate{
        .car_index = try reader.read(u16),
        .driver_index = try reader.read(u16),
        .driver_count = try reader.read(u8),
        .gear = @intCast(try reader.read(u8) - 1),
        .world_position_x = try reader.read(f32),
        .world_position_y = try reader.read(f32),
        .yaw = try reader.read(f32),
        .car_location = try reader.read(u8),
        .speed_kmh = try reader.read(u16),
        .position = try reader.read(u16),
        .cup_position = try reader.read(u16),
        .track_position = try reader.read(u16),
        .spline_position = try reader.read(f32),
        .laps = try reader.read(u16),
        .delta = try reader.read(i32),
        .best_session_lap = try parseLap(reader),
        .last_lap = try parseLap(reader),
        .current_lap = try parseLap(reader),
    };
}

pub fn entryList(allocator: std.mem.Allocator, reader: *binutils.Reader) ![]u16 {
    _ = try reader.read(i32); // throw away connection_id
    var entry_list = try std.ArrayList(u16).initCapacity(allocator, try reader.read(u16));
    errdefer entry_list.deinit();
    while (entry_list.items.len < entry_list.capacity)
        entry_list.appendAssumeCapacity(try reader.read(u16));
    return entry_list.toOwnedSlice();
}

pub fn trackData(allocator: std.mem.Allocator, reader: *binutils.Reader) !msg.TrackData {
    var track_data = msg.TrackData{};
    track_data.connection_id = try reader.read(i32);
    track_data.track_name = try reader.readBytesWithLen(u16);
    track_data.track_id = try reader.read(i32);
    track_data.track_length_m = try reader.read(i32);
    track_data.camera_sets = .{};

    var camera_set_count = try reader.read(u8);
    while (camera_set_count > 0) : (camera_set_count -= 1) {
        const set_name = try reader.readBytesWithLen(u16);
        var camera_count = try reader.read(u8);
        var camera_list = std.ArrayList(u8).init(allocator);
        defer camera_list.deinit();

        while (camera_count > 0) : ({
            camera_count -= 1;
            try camera_list.append(0);
        }) for (try reader.readBytesWithLen(u16)) |c| try camera_list.append(c);

        const CameraEnum = enums.CameraSetName;
        const camera_set_case = std.meta.stringToEnum(CameraEnum, set_name) orelse continue;
        const camera_set = switch (camera_set_case) {
            .Driveable => &track_data.camera_sets.driveable,
            .Onboard => &track_data.camera_sets.onboard,
            .Helicam => &track_data.camera_sets.helicam,
            .Pitlane => &track_data.camera_sets.pitlane,
            .Set1 => &track_data.camera_sets.pitlane,
            .Set2 => &track_data.camera_sets.pitlane,
            .SetVR => &track_data.camera_sets.pitlane,
        };
        camera_set.* = try camera_list.toOwnedSlice();
    }

    var hud_pages_count = try reader.read(u8);
    var hud_pages = std.ArrayList(u8).init(allocator);
    errdefer hud_pages.deinit();
    while (hud_pages_count > 0) : ({
        hud_pages_count -= 1;
        try hud_pages.append(0);
    }) for (try reader.readBytesWithLen(u16)) |c| try hud_pages.append(c);
    track_data.hud_pages = try hud_pages.toOwnedSlice();

    return track_data;
}

pub fn deinitTrackData(allocator: std.mem.Allocator, track_data: *msg.TrackData) void {
    if (track_data.hud_pages) |m| allocator.free(m);
    if (track_data.camera_sets.driveable) |m| allocator.free(m);
    if (track_data.camera_sets.onboard) |m| allocator.free(m);
    if (track_data.camera_sets.helicam) |m| allocator.free(m);
    if (track_data.camera_sets.pitlane) |m| allocator.free(m);
    if (track_data.camera_sets.set_1) |m| allocator.free(m);
    if (track_data.camera_sets.set_2) |m| allocator.free(m);
    if (track_data.camera_sets.set_vr) |m| allocator.free(m);
}

pub fn entryListCar(
    allocator: std.mem.Allocator,
    reader: *binutils.Reader,
    car_map: *std.AutoHashMap(isize, msg.Car),
) !msg.EntryListCar {
    var entry_list_car = msg.EntryListCar{};
    const car_id = try reader.read(u16);
    entry_list_car.car_model_type = try reader.read(u8);
    entry_list_car.team_name = try reader.readBytesWithLen(u16);
    entry_list_car.race_number = try reader.read(i32);
    entry_list_car.cup_category = try reader.read(u8);
    entry_list_car.current_driver_index = try reader.read(u8);
    entry_list_car.nationality = try reader.read(u16);
    var drivers_count = try reader.read(u8);
    var drivers = std.ArrayList(msg.Driver).init(allocator);
    errdefer drivers.deinit();
    while (drivers_count > 0) : (drivers_count -= 1) try drivers.append(try parseDriver(reader));
    entry_list_car.drivers = try drivers.toOwnedSlice();
    entry_list_car.current_driver = entry_list_car.drivers[entry_list_car.current_driver_index];
    try car_map.put(car_id, entry_list_car);
    return entry_list_car;
}

pub fn broadcastingEvent(
    reader: *binutils.Reader,
    car_map: *std.AutoHashMap(isize, msg.Car),
) !msg.BroadcastingEvent {
    var car_id: i32 = 0;
    return msg.BroadcastingEvent{
        .type = try reader.read(u8),
        .message = try reader.readBytesWithLen(u16),
        .time_ms = try reader.read(i32),
        .car_id = util.andCopy(i32, &car_id, try reader.read(i32)),
        .car = car_map.get(car_id) orelse return error.CarNotFound,
    };
}
