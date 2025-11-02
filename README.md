# tinyuz

Native Zig implementation of the TinyUZ compression algorithm, optimized for small repetitive datasets like RGB LED frames, sensor data, and embedded systems.

Based on the TinyUZ algorithm by HouSisong.

## Why TinyUZ?

Most compression libraries (gzip, zlib, etc.) are designed for large files and have significant overhead:
- **Header overhead**: 10+ bytes of metadata
- **Dictionary overhead**: Require 32KB+ memory windows
- **Complexity**: Thousands of bytes of decompressor code

For small datasets (< 1KB), this overhead often **exceeds** the compression gains!

**TinyUZ is purpose-built for small repetitive data:**
- **Minimal overhead**: 4-byte header only
- **Tiny footprint**: 300-600 byte decompressor (C implementation)
- **Low memory**: Configurable dictionary (256 bytes - 16MB)
- **Efficient**: Sub-microsecond operation times for small data
- **Real savings**: 90% compression on 120-byte LED frames

### Perfect For
- RGB LED frames (40 LEDs × 3 bytes = 120 bytes → ~12 bytes)
- Sensor data with repeating patterns
- Wireless transmission (save RF bandwidth)
- Flash storage (store more animation frames)
- Embedded systems (minimal RAM/ROM footprint)

### Not For
- Large files (use gzip, zstd, etc.)
- Random/unique data (will expand slightly)
- Maximum compression ratio (use bzip2, lzma)

## Features

- Pure Zig implementation with no external dependencies
- Lossless compression optimized for small, repetitive data
- Minimal RAM requirements (dict_size + cache_size)
- Comprehensive error handling and bounds checking
- Well-tested with 30+ tests

## Installation

### Using Zig's Package Manager

Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .tinyuz = .{
        .path = "path/to/tinyuz",
    },
},
```

Then in your `build.zig`:
```zig
const tinyuz = b.dependency("tinyuz", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("tinyuz", tinyuz.module("tinyuz"));
```

### Manual Installation

Copy the Zig files into your project:
```
your_project/
  src/
    main.zig
  tinyuz/
    tinyuz.zig       # Public API and constants
    compress.zig     # Compression implementation
    decompress.zig   # Decompression implementation
    utilities.zig    # Shared utilities
```

## Quick Start

```zig
const std = @import("std");
const tinyuz = @import("tinyuz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Compress
    const input = [_]u8{ 1, 2, 3, 1, 2, 3 };
    var compressed: [128]u8 = undefined;
    const compressed_size = try tinyuz.compressMem(&input, &compressed, 65535, allocator);

    // Decompress
    var output: [6]u8 = undefined;
    const decompressed_size = try tinyuz.decompressMem(compressed[0..compressed_size], &output);

    // Verify
    std.debug.assert(decompressed_size == input.len);
    std.debug.assert(std.mem.eql(u8, &output, &input));
}
```

Run the included example:
```bash
zig build run
```

Or run directly:
```bash
zig run example.zig
```

## API Reference

### compressMem
```zig
pub fn compressMem(
    in_data: []const u8,           // Data to compress
    out_code: []u8,                // Output buffer
    dict_size: u32,                // Dictionary size
    allocator: std.mem.Allocator,  // Allocator for temporary buffers
) !usize
```

Compress data using TinyUZ algorithm. Returns number of compressed bytes.

**Errors:**
- `error.OutSizeOrCodeError` - output buffer too small

### decompressMem
```zig
pub fn decompressMem(
    in_code: []const u8,    // Compressed data
    out_data: []u8,         // Output buffer
) !usize
```

Decompress TinyUZ-compressed data. Returns number of decompressed bytes.

**Errors:**
- `error.OutSizeOrCodeError` - output buffer too small
- `error.ReadCodeError` - corrupted compressed data
- `error.ReadDictSizeError` - invalid header
- `error.DictPosError` - invalid dictionary position
- `error.CtrlTypeUnknownError` - unknown control code

### readDictSize
```zig
pub fn readDictSize(in_code: []const u8) !u32
```

Read dictionary size from compressed data header without decompressing.

**Errors:**
- `error.ReadDictSizeError` - invalid header

## Format

TinyUZ compressed data format:
```
[4 bytes: dict_size (little-endian)] [compressed data...]
```

The compressed data uses:
- Bit-level encoding for type information
- Variable-length encoding for lengths and positions
- Dictionary-based matches (LZ77-style)
- Literal bytes for non-compressible data

## Examples

### RGB LED Compression (Real-World Use Case)

```zig
const std = @import("std");
const tinyuz = @import("tinyuz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 40 RGB LEDs (120 bytes) - solid red color
    var led_data: [120]u8 = undefined;
    for (0..40) |i| {
        led_data[i * 3 + 0] = 0xFF; // R
        led_data[i * 3 + 1] = 0x00; // G
        led_data[i * 3 + 2] = 0x00; // B
    }

    var compressed: [256]u8 = undefined;
    const size = try tinyuz.compressMem(&led_data, &compressed, 65535, allocator);

    std.debug.print("Compressed: 120 bytes → {} bytes\n", .{size});
    // Typically: 120 bytes → ~12 bytes (90% reduction!)
}
```

### Custom Dictionary Size

```zig
// Small dictionary for memory-constrained devices
const input = [_]u8{ 1, 2, 3, 4, 5 };
var compressed: [64]u8 = undefined;

const size = try tinyuz.compressMem(&input, &compressed, 256, allocator); // 256-byte dict
```

### Error Handling

```zig
const size = tinyuz.compressMem(input, &compressed, 65535, allocator) catch |err| {
    switch (err) {
        error.OutSizeOrCodeError => {
            // Output buffer too small
            std.debug.print("Need larger output buffer\n", .{});
        },
        else => return err,
    }
};
```

## Testing

Run the test suite:

```bash
zig build test
```

**Test coverage:**
- 30+ comprehensive tests
- Compression/decompression round trips
- Error handling (buffer overflow, corrupted data)
- Edge cases (empty data, single byte, maximum sizes)
- Performance verification

## Performance

Example compression ratios from `example.zig`:

| Data Type | Input Size | Compressed Size | Ratio |
|-----------|-----------|-----------------|-------|
| Repeating pattern (1,2,3) | 9 bytes | 11 bytes | 122% (slight expansion) |
| Solid RGB color (40 LEDs) | 120 bytes | 12 bytes | 10% (90% reduction) |
| Uniform block (0xAA) | 1000 bytes | 10 bytes | 1% (99% reduction) |

**Key characteristics:**
- Excellent compression on repetitive data
- Small expansion on incompressible data
- Minimal overhead (4-byte header)
- Fast compression/decompression

## Implementation

### Code Structure

This is a clean-room Zig implementation with modern design:

- **tinyuz.zig** - Public API, constants, and type definitions
- **compress.zig** - Compression implementation (LZ77 match finding, encoding)
- **decompress.zig** - Decompression implementation (stream parsing, decoding)
- **utilities.zig** - Shared helper functions (endian conversion, bounds checking)

### Implementation Features

- Native Zig with no external dependencies
- Idiomatic Zig code (slices, error unions, comptime)
- Comprehensive error handling
- Memory safety with bounds checking
- Well-tested (30+ tests)
- Modular design with focused functions

### Algorithm Design

**Core technique**: LZ77 sliding window with bit-level encoding

**Optimizations for small data**:
1. **Minimal header**: Only 4 bytes for dictionary size
2. **Short matches**: 2-byte minimum (vs 3-4 in other compressors)
3. **Literal encoding**: Special case for 15+ consecutive literals
4. **Variable-length coding**: Compact encoding for small values
5. **Position reuse**: Cache last match position
6. **Configurable dictionary**: Trade memory for compression ratio

**Why it works for repetitive data**:
- RGB LED frames have many repeated 3-byte patterns (colors)
- Sensor data often has trending/cycling values
- Dictionary matches replace repetition with short references
- Small dictionary (256-1024 bytes) sufficient for local patterns

## License

MIT License

This implementation is based on the TinyUZ algorithm:
- Copyright (c) 2012-2025 HouSisong
- Algorithm: https://github.com/sisong/tinyuz

## References

- Zig Programming Language: https://ziglang.org
- TinyUZ Algorithm: https://github.com/sisong/tinyuz
