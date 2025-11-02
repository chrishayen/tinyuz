// example.zig
// Example usage of the TinyUZ Zig library

const std = @import("std");
const tinyuz = @import("tinyuz.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("TinyUZ Zig Example\n", .{});
    std.debug.print("==================\n\n", .{});

    // Example 1: Simple data
    {
        std.debug.print("Example 1: Simple repeating pattern\n", .{});
        const input = [_]u8{ 1, 2, 3, 1, 2, 3, 1, 2, 3 };
        var compressed: [128]u8 = undefined;
        var output: [9]u8 = undefined;

        const compressed_size = try tinyuz.compressMem(&input, &compressed, 65535, allocator);
        std.debug.print("  Input:  {} bytes\n", .{input.len});
        std.debug.print("  Compressed: {} bytes ({}% of original)\n", .{ compressed_size, (compressed_size * 100) / input.len });

        const decompressed_size = try tinyuz.decompressMem(compressed[0..compressed_size], &output);
        std.debug.print("  Decompressed: {} bytes\n", .{decompressed_size});
        std.debug.print("  Match: {}\n\n", .{std.mem.eql(u8, &input, &output)});
    }

    // Example 2: RGB LED data
    {
        std.debug.print("Example 2: RGB LED frames (40 LEDs, solid red)\n", .{});
        var led_data: [120]u8 = undefined;
        for (0..40) |i| {
            led_data[i * 3 + 0] = 0xFF; // R
            led_data[i * 3 + 1] = 0x00; // G
            led_data[i * 3 + 2] = 0x00; // B
        }

        var compressed: [256]u8 = undefined;
        var output: [120]u8 = undefined;

        const compressed_size = try tinyuz.compressMem(&led_data, &compressed, 65535, allocator);
        std.debug.print("  Input:  {} bytes (40 LEDs × 3 bytes/LED)\n", .{led_data.len});
        std.debug.print("  Compressed: {} bytes ({}% of original)\n", .{ compressed_size, (compressed_size * 100) / led_data.len });
        std.debug.print("  Savings: {} bytes ({}% reduction)\n", .{ led_data.len - compressed_size, 100 - (compressed_size * 100) / led_data.len });

        const decompressed_size = try tinyuz.decompressMem(compressed[0..compressed_size], &output);
        std.debug.print("  Decompressed: {} bytes\n", .{decompressed_size});
        std.debug.print("  Match: {}\n\n", .{std.mem.eql(u8, &led_data, &output)});
    }

    // Example 3: Large block of same byte
    {
        std.debug.print("Example 3: Large block (1000 bytes, all 0xAA)\n", .{});
        var input: [1000]u8 = undefined;
        @memset(&input, 0xAA);

        var compressed: [2048]u8 = undefined;
        var output: [1000]u8 = undefined;

        const compressed_size = try tinyuz.compressMem(&input, &compressed, 65535, allocator);
        std.debug.print("  Input:  {} bytes\n", .{input.len});
        std.debug.print("  Compressed: {} bytes ({}% of original)\n", .{ compressed_size, (compressed_size * 100) / input.len });
        std.debug.print("  Savings: {} bytes ({}% reduction)\n", .{ input.len - compressed_size, 100 - (compressed_size * 100) / input.len });

        const decompressed_size = try tinyuz.decompressMem(compressed[0..compressed_size], &output);
        std.debug.print("  Decompressed: {} bytes\n", .{decompressed_size});
        std.debug.print("  Match: {}\n\n", .{std.mem.eql(u8, &input, &output)});
    }

    // Example 4: Read dictionary size
    {
        std.debug.print("Example 4: Read dictionary size from compressed data\n", .{});
        const input = [_]u8{ 1, 2, 3, 4, 5 };
        const dict_size: u32 = 1024;

        var compressed: [128]u8 = undefined;
        const compressed_size = try tinyuz.compressMem(&input, &compressed, dict_size, allocator);

        const read_dict_size = try tinyuz.readDictSize(compressed[0..compressed_size]);
        std.debug.print("  Dictionary size used: {}\n", .{dict_size});
        std.debug.print("  Dictionary size read: {}\n", .{read_dict_size});
        std.debug.print("  Match: {}\n\n", .{dict_size == read_dict_size});
    }

    std.debug.print("All examples completed successfully!\n", .{});
}
