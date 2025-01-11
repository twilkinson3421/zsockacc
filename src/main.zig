const std = @import("std");
const acc = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var client = try acc.Client.init(.{
        .allocator = alloc,
        // .address = "192.168.1.230",
        .address = "192.168.1.177",
        .port = 9000,
        .name = "test_client",
        .password = "asd",
    });

    defer {
        client.terminateRecvThread();
        client.disconnect();
        client.deinit();
    }

    try client.connect();
    try client.spawnRecvThread();

    std.time.sleep(std.time.ns_per_s * 10); // simulate some time the program is running
}
