// utilities.zig
// Shared utility functions for compression and decompression
//
// Provides endian conversion, bounds checking, and state management.

const std = @import("std");
const tinyuz = @import("tinyuz.zig");

// Little-endian encoding constants
pub const DICT_POS_THRESHOLD = 1 << 7;

/// Write 32-bit unsigned integer in little-endian format
pub fn writeU32Le(buffer: *std.ArrayList(u8), value: u32, allocator: std.mem.Allocator) !void {
    var remaining = value;
    var i: usize = 0;
    while (i < tinyuz.TUZ_K_DICT_SIZE_SAVED_BYTES) : (i += 1) {
        try buffer.append(allocator, @intCast(remaining & 0xFF));
        remaining >>= 8;
    }
}

/// Read 32-bit unsigned integer from little-endian format
pub fn readU32Le(buffer: []const u8) !u32 {
    if (buffer.len < tinyuz.TUZ_K_DICT_SIZE_SAVED_BYTES) {
        return error.ReadDictSizeError;
    }

    const value = @as(u32, buffer[0]) |
        (@as(u32, buffer[1]) << 8) |
        (@as(u32, buffer[2]) << 16) |
        (@as(u32, buffer[3]) << 24);

    if (value == 0) {
        return error.ReadDictSizeError;
    }

    return value;
}

/// Check if there's enough space in output buffer
pub fn checkOutputSpace(cur_pos: usize, required_bytes: usize, buffer_size: usize) bool {
    return (cur_pos + required_bytes) <= buffer_size;
}

/// Check if there's enough space, return error if not
pub fn checkOutputBounds(cur_pos: usize, required_bytes: usize, buffer_size: usize) !void {
    if (!checkOutputSpace(cur_pos, required_bytes, buffer_size)) {
        return error.OutSizeOrCodeError;
    }
}

/// Reset state flags for control code processing
pub fn resetControlState(dict_pos_back: *u32, type_count: *u8) void {
    dict_pos_back.* = 1;
    type_count.* = 0;
}

// Tests
test "writeU32Le and readU32Le" {
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(std.testing.allocator);

    try writeU32Le(&buffer, 0x12345678, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), buffer.items.len);

    const value = try readU32Le(buffer.items);
    try std.testing.expectEqual(@as(u32, 0x12345678), value);
}

test "checkOutputSpace" {
    try std.testing.expect(checkOutputSpace(0, 10, 20));
    try std.testing.expect(checkOutputSpace(10, 10, 20));
    try std.testing.expect(!checkOutputSpace(11, 10, 20));
}

test "checkOutputBounds" {
    try checkOutputBounds(0, 10, 20);
    try checkOutputBounds(10, 10, 20);

    const result = checkOutputBounds(11, 10, 20);
    try std.testing.expectError(error.OutSizeOrCodeError, result);
}
