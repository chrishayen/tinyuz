// test.zig
// Comprehensive tests for TinyUZ compression library

const std = @import("std");
const tinyuz = @import("tinyuz.zig");

// Helper function: compress input data
fn compressData(
    t: *std.testing.Allocator,
    input: []const u8,
    dict_size: u32,
) !struct { compressed: []u8, size: usize } {
    const compressed = try t.alloc(u8, input.len * 2 + 256);
    const size = try tinyuz.compressMem(input, compressed, dict_size, t.*);
    return .{ .compressed = compressed, .size = size };
}

// Helper function: decompress data
fn decompressData(
    t: *std.testing.Allocator,
    compressed: []const u8,
    expected_size: usize,
) ![]u8 {
    const output = try t.alloc(u8, expected_size);
    const dec_size = try tinyuz.decompressMem(compressed, output);
    try std.testing.expectEqual(expected_size, dec_size);
    return output;
}

// Helper function: verify data matches
fn verifyDataMatch(actual: []const u8, expected: []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

// Helper function: full round-trip test
fn testRoundtrip(
    input: []const u8,
    dict_size: u32,
    allocator: std.mem.Allocator,
) !void {
    var compressed_buf: [4096]u8 = undefined;
    const compressed_size = try tinyuz.compressMem(input, &compressed_buf, dict_size, allocator);

    var output: [4096]u8 = undefined;
    const decompressed_size = try tinyuz.decompressMem(compressed_buf[0..compressed_size], output[0..input.len]);

    try std.testing.expectEqual(input.len, decompressed_size);
    try verifyDataMatch(output[0..decompressed_size], input);
}

// Test: Basic compression and decompression
test "basic compression and decompression" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 3, 1, 2, 3 };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Empty input
test "empty input" {
    const allocator = std.testing.allocator;
    const input = [_]u8{};

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Single byte
test "single byte" {
    const allocator = std.testing.allocator;
    const input = [_]u8{42};

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Solid color pattern (like RGB LED)
test "solid color pattern" {
    const allocator = std.testing.allocator;
    var input: [120]u8 = undefined;

    // 40 RGB LEDs - solid red
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        input[i * 3 + 0] = 0xFF; // R
        input[i * 3 + 1] = 0x00; // G
        input[i * 3 + 2] = 0x00; // B
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Repeating pattern
test "repeating pattern" {
    const allocator = std.testing.allocator;
    var input: [300]u8 = undefined;

    // Pattern: 1,2,3 repeated 100 times
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        input[i * 3 + 0] = 1;
        input[i * 3 + 1] = 2;
        input[i * 3 + 2] = 3;
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Large block of same byte
test "large block same byte" {
    const allocator = std.testing.allocator;
    var input: [1000]u8 = undefined;
    @memset(&input, 0xAA);

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Random-like data (should not compress well)
test "random data" {
    const allocator = std.testing.allocator;
    var input: [256]u8 = undefined;

    // Fill with sequential values (simulates random-ish data)
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        input[i] = @intCast(i);
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Small dictionary size
test "small dictionary size" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 3, 1, 2, 3, 4, 5, 6, 1, 2, 3 };

    try testRoundtrip(&input, 256, allocator);
}

// Test: Two byte pattern
test "two byte pattern" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 0xAB, 0xCD, 0xAB, 0xCD, 0xAB, 0xCD };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Minimum match length (2 bytes)
test "minimum match length" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 1, 2 };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Long literal run (15+ bytes)
test "long literal run" {
    const allocator = std.testing.allocator;
    // 20 unique bytes followed by repetition
    const input = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 1, 2, 3 };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Read dictionary size from compressed data
test "read dictionary size" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 3, 4, 5 };
    const dict_size: u32 = 1024;

    var compressed: [128]u8 = undefined;
    const compressed_size = try tinyuz.compressMem(&input, &compressed, dict_size, allocator);

    const read_dict_size = try tinyuz.readDictSize(compressed[0..compressed_size]);
    try std.testing.expectEqual(dict_size, read_dict_size);
}

// Test: Multiple patterns
test "multiple patterns" {
    const allocator = std.testing.allocator;
    const input = [_]u8{
        1, 2, 3, 1, 2, 3, // Pattern 1
        4, 5, 4, 5, 4, 5, // Pattern 2
        6, 6, 6, 6, 6, 6, // Pattern 3
    };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Nested patterns
test "nested patterns" {
    const allocator = std.testing.allocator;
    const input = [_]u8{
        1, 2, 1, 2, 1, 2, // Outer pattern
        1, 2, 1, 2, 1, 2, // Repeat outer pattern
    };

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Large input
test "large input" {
    const allocator = std.testing.allocator;
    var input: [3000]u8 = undefined;

    // Fill with repeating pattern
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        input[i] = @intCast(i % 10);
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Error - Output buffer too small for compression
test "compression output buffer too small" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var compressed: [5]u8 = undefined; // Too small

    const result = tinyuz.compressMem(&input, &compressed, 65535, allocator);
    try std.testing.expectError(error.OutSizeOrCodeError, result);
}

// Test: Error - Output buffer too small for decompression
test "decompression output buffer too small" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };

    var compressed: [128]u8 = undefined;
    const compressed_size = try tinyuz.compressMem(&input, &compressed, 65535, allocator);

    var output: [5]u8 = undefined; // Too small
    const result = tinyuz.decompressMem(compressed[0..compressed_size], &output);
    try std.testing.expectError(error.OutSizeOrCodeError, result);
}

// Test: Error - Invalid compressed data (too short)
test "invalid compressed data - too short" {
    const compressed = [_]u8{ 1, 2 }; // Less than 4 bytes
    var output: [10]u8 = undefined;

    const result = tinyuz.decompressMem(&compressed, &output);
    try std.testing.expectError(error.ReadDictSizeError, result);
}

// Test: All bytes 0-255
test "all byte values" {
    const allocator = std.testing.allocator;
    var input: [256]u8 = undefined;

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        input[i] = @intCast(i);
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Alternating bytes
test "alternating bytes" {
    const allocator = std.testing.allocator;
    var input: [100]u8 = undefined;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        input[i] = if (i % 2 == 0) 0xAA else 0x55;
    }

    try testRoundtrip(&input, 65535, allocator);
}

// Test: Verify compression ratio for highly compressible data
test "compression ratio - solid data" {
    const allocator = std.testing.allocator;
    var input: [120]u8 = undefined;
    @memset(&input, 0xFF);

    var compressed: [256]u8 = undefined;
    const compressed_size = try tinyuz.compressMem(&input, &compressed, 65535, allocator);

    // Should achieve significant compression
    const ratio = @as(f32, @floatFromInt(compressed_size)) / @as(f32, @floatFromInt(input.len));
    try std.testing.expect(ratio < 0.5); // Better than 50% compression
}
