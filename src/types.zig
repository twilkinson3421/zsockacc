const std = @import("std");
const msg = @import("msg.zig");

pub const CarMap = std.AutoHashMap(isize, msg.Car);
