// tinyuz.zig
// Native Zig implementation of TinyUZ compression
//
// Based on the TinyUZ algorithm by HouSisong
// License: MIT License (c) 2012-2025 HouSisong
//
// Optimized for small repetitive datasets like RGB LED frames,
// sensor data, and embedded systems.
//
// Public API:
//   - compressMem: Compress data using TinyUZ algorithm
//   - decompressMem: Decompress TinyUZ-compressed data
//   - readDictSize: Read dictionary size from compressed data header

const std = @import("std");

// Constants from tuz_types_private.h
pub const TUZ_K_MAX_TYPE_BIT_COUNT = 8;
pub const TUZ_K_MIN_DICT_MATCH_LEN = 2;
pub const TUZ_K_MIN_LITERAL_LEN = 15;
pub const TUZ_K_BIG_POS_FOR_LEN = (1 << 11) + (1 << 9) + (1 << 7) - 1;

// Control types
pub const TUZ_CODE_TYPE_DICT = 0;
pub const TUZ_CODE_TYPE_DATA = 1;
pub const TUZ_CTRL_TYPE_LITERAL_LINE = 1;
pub const TUZ_CTRL_TYPE_CLIP_END = 2;
pub const TUZ_CTRL_TYPE_STREAM_END = 3;

// Dictionary size limits
pub const TUZ_K_MAX_DICT_SIZE = (1 << 24) - 1; // 16MB max
pub const TUZ_K_MIN_DICT_SIZE = 1;
pub const TUZ_K_DICT_SIZE_SAVED_BYTES = 4; // Use 4 bytes for dict size

// Result codes for compression/decompression operations
pub const Result = enum(u32) {
    OK = 0,
    STREAM_END = 3, // Control code 3 - successful decompression
    LITERAL_LINE = 1, // Control code 1
    CLIP_END = 2, // Control code 2
    CTRL_TYPE_UNKNOWN_ERROR = 10,
    CTRL_TYPE_STREAM_END_ERROR = 11,
    READ_CODE_ERROR = 20,
    READ_DICT_SIZE_ERROR = 21,
    CACHE_SIZE_ERROR = 22,
    DICT_POS_ERROR = 23,
    OUT_SIZE_OR_CODE_ERROR = 24,
    CODE_ERROR = 25,
};

// Import the submodules
const utilities = @import("utilities.zig");
const compress = @import("compress.zig");
const decompress = @import("decompress.zig");

pub const writeU32Le = utilities.writeU32Le;
pub const readU32Le = utilities.readU32Le;

/// Compress data using TinyUZ algorithm
///
/// Args:
///     in_data: Data to compress
///     out_code: Output buffer
///     dict_size: Dictionary size (optional, default 65535)
///     allocator: Allocator for temporary buffers
///
/// Returns:
///     Number of bytes written to out_code, or error
pub fn compressMem(
    in_data: []const u8,
    out_code: []u8,
    dict_size: u32,
    allocator: std.mem.Allocator,
) !usize {
    return compress.compressMem(in_data, out_code, dict_size, allocator);
}

/// Decompress TinyUZ-compressed data
///
/// Args:
///     in_code: Compressed data
///     out_data: Output buffer
///
/// Returns:
///     Number of bytes decompressed
pub fn decompressMem(
    in_code: []const u8,
    out_data: []u8,
) !usize {
    return decompress.decompressMem(in_code, out_data);
}

/// Read dictionary size from compressed data header
///
/// Args:
///     in_code: Compressed data
///
/// Returns:
///     Dictionary size
pub fn readDictSize(in_code: []const u8) !u32 {
    return decompress.readDictSize(in_code);
}

// Tests
test "basic compression and decompression" {
    const allocator = std.testing.allocator;

    const input = [_]u8{ 1, 2, 3, 1, 2, 3 };
    var compressed: [128]u8 = undefined;
    var output: [6]u8 = undefined;

    const compressed_size = try compressMem(&input, &compressed, 65535, allocator);
    const decompressed_size = try decompressMem(compressed[0..compressed_size], &output);

    try std.testing.expectEqual(@as(usize, 6), decompressed_size);
    try std.testing.expectEqualSlices(u8, &input, &output);
}
