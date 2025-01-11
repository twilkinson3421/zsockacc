pub const Lap = struct {
    laptime_ms: ?i32 = undefined,
    car_index: u16 = undefined,
    driver_index: u16 = undefined,
    splits: [3]?i32 = undefined,
    split_count: u8 = undefined,
    invalid: bool = undefined,
    valid_for_best: bool = undefined,
    out_lap: bool = undefined,
    in_lap: bool = undefined,
};

pub const Driver = struct {
    first_name: []const u8,
    last_name: []const u8,
    short_name: []const u8,
    category: u8,
    nationality: u16,
};

pub const Car = struct {
    car_model_type: u8 = undefined,
    team_name: []const u8 = undefined,
    race_number: i32 = undefined,
    cup_category: u8 = undefined,
    current_driver_index: u8 = undefined,
    nationality: u16 = undefined,
    drivers: []Driver = undefined,
    current_driver: Driver = undefined,
};

pub const RegistrationResult = struct {
    connection_id: i32,
    success: bool,
    read_only: bool,
    error_msg: ?[]const u8,
};

pub const RealtimeUpdate = struct {
    event_index: u16,
    session_index: u16,
    session_type: u8,
    phase: u8,
    session_time: f32,
    session_end_time: f32,
    focused_car_index: i32,
    active_camera_set: []const u8,
    active_camera: []const u8,
    current_hud_page: []const u8,
    is_replay_playing: bool,
    replay_session_time: ?f32 = null,
    replay_remaining_time: ?f32 = null,
    time_of_day: f32,
    ambient_temperature: u8,
    track_temperature: u8,
    clouds: f32,
    rain_level: f32,
    wetness: f32,
    best_session_lap: Lap,
};

pub const RealtimeCarUpdate = struct {
    car_index: u16,
    driver_index: u16,
    driver_count: u8,
    gear: i8,
    world_position_x: f32,
    world_position_y: f32,
    yaw: f32,
    car_location: u8,
    speed_kmh: u16,
    position: u16,
    cup_position: u16,
    track_position: u16,
    spline_position: f32,
    laps: u16,
    delta: i32,
    best_session_lap: Lap,
    last_lap: Lap,
    current_lap: Lap,
};

pub const TrackData = struct {
    camera_sets: struct {
        driveable: ?[]const u8 = null,
        onboard: ?[]const u8 = null,
        helicam: ?[]const u8 = null,
        pitlane: ?[]const u8 = null,
        set_1: ?[]const u8 = null,
        set_2: ?[]const u8 = null,
        set_vr: ?[]const u8 = null,
    } = undefined,
    hud_pages: ?[]const u8 = null,
    connection_id: i32 = undefined,
    track_name: []const u8 = undefined,
    track_id: i32 = undefined,
    track_length_m: i32 = undefined,
};

pub const EntryListCar = Car;

pub const BroadcastingEvent = struct {
    type: u8,
    message: []const u8,
    time_ms: i32,
    car_id: i32,
    car: Car,
};
