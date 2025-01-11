const std = @import("std");
const binutils = @import("zbinutils");

pub fn connect(
    allocator: std.mem.Allocator,
    name: []const u8,
    password: []const u8,
    cmd: []const u8,
    update_ms: u16,
) !binutils.WriterKnownSize {
    const size = @sizeOf(u8) + @sizeOf(u8) +
        @sizeOf(u16) + name.len +
        @sizeOf(u16) + password.len +
        @sizeOf(u16) +
        @sizeOf(u16) + cmd.len;
    var writer = try binutils.WriterKnownSize.init(allocator, size);
    writer.endian = .little;

    writer.write(u8, 0x01);
    writer.write(u8, 0x04);
    writer.write(u16, @intCast(name.len));
    writer.writeBytes(name);
    writer.write(u16, @intCast(password.len));
    writer.writeBytes(password);
    writer.write(u16, update_ms);
    writer.write(u16, @intCast(cmd.len));
    writer.writeBytes(cmd);

    return writer;
}

pub fn disconnect() []const u8 {
    return &.{0x09};
}

pub fn requestEntryList(allocator: std.mem.Allocator, id: i32) !binutils.WriterKnownSize {
    const size = @sizeOf(u8) + @sizeOf(i32);
    var writer = try binutils.WriterKnownSize.init(allocator, size);
    writer.endian = .little;
    writer.write(u8, 0x0A);
    writer.write(i32, id);
    return writer;
}

pub fn requestTrackData(allocator: std.mem.Allocator, id: i32) !binutils.WriterKnownSize {
    const size = @sizeOf(u8) + @sizeOf(i32);
    var writer = try binutils.WriterKnownSize.init(allocator, size);
    writer.endian = .little;
    writer.write(u8, 0x0B);
    writer.write(i32, id);
    return writer;
}
