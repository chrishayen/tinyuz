# tinyuz

Native Odin implementation of the TinyUZ compression algorithm, optimized for small repetitive datasets like RGB LED frames, sensor data, and embedded systems.

Based on the TinyUZ algorithm by HouSisong.

## Why TinyUZ?

Most compression libraries (gzip, zlib, etc.) are designed for large files and have significant overhead:
- **Header overhead**: 10+ bytes of metadata
- **Dictionary overhead**: Require 32KB+ memory windows
- **Complexity**: Thousands of bytes of decompressor code

For small datasets (< 1KB), this overhead often **exceeds** the compression gains!

**TinyUZ is purpose-built for small repetitive data:**
- **Minimal overhead**: 4-byte header only
- **Tiny footprint**: 300-600 byte decompressor
- **Low memory**: Configurable dictionary (256 bytes - 16MB)
- **Fast**: Optimized for patterns, not raw speed
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

- Pure Odin implementation with no external dependencies
- Lossless compression optimized for small, repetitive data
- Tiny decompressor footprint (298-626 bytes in C implementations)
- Minimal RAM requirements (dict_size + cache_size)
- Fast decompression on modern CPUs
- Ideal for embedded systems, IoT devices, and LED control

## Status

✅ **Compression**: Fully implemented with configurable dictionary size
✅ **Decompression**: Fully implemented and tested

## Installation

Copy the `tinyuz` directory into your project:

```
your_project/
  main.odin
  tinyuz/
    tinyuz.odin       # Public API and constants
    compress.odin     # Compression implementation
    decompress.odin   # Decompression implementation
    utilities.odin    # Shared utilities
```

Then import it:

```odin
import "tinyuz"
```

## Quick Start

```odin
import "tinyuz"

// Compress
input := []byte{1, 2, 3, 1, 2, 3}
compressed := make([]byte, len(input) * 2)
size, result := tinyuz.compress_mem(input, compressed)

if result == .OK {
    // Decompress
    output := make([]byte, len(input))
    dec_size, dec_result := tinyuz.decompress_mem(compressed[:size], output)

    if dec_result == .STREAM_END {
        // Success! Data in output[:dec_size]
    }
}
```

## API Reference

### compress_mem
```odin
compress_mem :: proc(
    in_data: []byte,           // Data to compress
    out_code: []byte,          // Output buffer
    dict_size: uint = 65535,   // Dictionary size (optional)
) -> (compressed_size: int, result: Result)
```

Compress data using TinyUZ algorithm. Returns compressed size and result code.
- `result == .OK` indicates success
- `result == .OUT_SIZE_OR_CODE_ERROR` means output buffer too small

### decompress_mem
```odin
decompress_mem :: proc(
    in_code: []byte,           // Compressed data
    out_data: []byte,          // Output buffer
) -> (decompressed_size: int, result: Result)
```

Decompress TinyUZ-compressed data. Returns decompressed size and result code.
- `result == .STREAM_END` indicates successful decompression
- Other values indicate errors (corrupted data, buffer too small, etc.)

### read_dict_size
```odin
read_dict_size :: proc(
    in_code: []byte,           // Compressed data
) -> (dict_size: uint, ok: bool)
```

Read dictionary size from compressed data header without decompressing.

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

TinyUZ excels at compressing repetitive small datasets like RGB LED frames:

```odin
import "tinyuz"

// 40 RGB LEDs (120 bytes) - solid red color
led_data := make([]byte, 40 * 3)
for i := 0; i < 40; i += 1 {
    led_data[i*3 + 0] = 0xFF  // R
    led_data[i*3 + 1] = 0x00  // G
    led_data[i*3 + 2] = 0x00  // B
}

compressed := make([]byte, 256)
size, _ := tinyuz.compress_mem(led_data, compressed)
// Typically: 120 bytes → ~12 bytes (90% reduction!)
```

**Use cases:**
- Wireless LED controllers (reduce RF bandwidth)
- LED animation storage (save flash memory)
- IoT sensor data with patterns
- Embedded telemetry compression

### Custom Dictionary Size

```odin
// Small dictionary for memory-constrained devices
input := []byte{1, 2, 3, 4, 5}
compressed := make([]byte, 64)

size, result := tinyuz.compress_mem(input, compressed, 256)  // 256-byte dict
```

### Error Handling

```odin
size, result := tinyuz.compress_mem(input, compressed)

switch result {
case .OK:
    // Compression succeeded
    data := compressed[:size]

case .OUT_SIZE_OR_CODE_ERROR:
    // Output buffer too small

case:
    // Other error
}
```

## Performance

### Compression Ratios

**Highly repetitive data** (best case):
- Solid colors: 90-95% reduction (120 bytes → 10-15 bytes)
- Repeating patterns: 70-90% reduction
- Sensor data with trends: 60-80% reduction

**Mixed data** (typical):
- Some repetition: 30-50% reduction
- Random data: 0-10% expansion (incompressible)

### Speed Characteristics

**Decompression** (primary optimization target):
- Lightweight bit-stream parsing
- Simple dictionary lookups
- No complex tables or state machines
- Fast enough for real-time embedded use

**Compression**:
- Simple LZ77 sliding window
- Linear search (optimized for small inputs)
- No complex hash tables or trees
- Trade-off: Simpler code over maximum speed

### Memory Usage

**Runtime**:
- Decompressor: ~dict_size bytes RAM
- Compressor: ~dict_size + output buffer
- No hidden allocations

**Code size**:
- Decompressor: 300-600 bytes (C)
- Compressor: ~2KB (C)
- This Odin implementation: Larger but includes safety checks

## Implementation

### Code Structure

This is a clean-room Odin implementation with modern design:

- **tinyuz.odin** - Public API, constants, and type definitions
- **compress.odin** - Compression implementation (LZ77 match finding, encoding)
- **decompress.odin** - Decompression implementation (stream parsing, decoding)
- **utilities.odin** - Shared helper functions (endian conversion, bounds checking)

### Implementation Features

- Native Odin with no external dependencies
- Idiomatic Odin code (slices, enums, defer)
- Comprehensive error handling
- Memory safety with bounds checking
- Well-tested (44 tests, ~95% coverage)
- Modular design with focused functions
- Helper utilities for common operations

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

## Testing

Run the test suite:

```bash
odin test . -all-packages
```

**Test coverage:**
- 44 comprehensive tests
- Compression/decompression round trips
- Error handling (buffer overflow, corrupted data)
- Edge cases (empty data, single byte, maximum sizes)
- Internal function unit tests
- ~95% code coverage

## License

MIT License

This implementation is based on the TinyUZ algorithm:
- Copyright (c) 2012-2025 HouSisong
- Algorithm: https://github.com/sisong/tinyuz

## References

- Odin Programming Language: https://odin-lang.org
- TinyUZ Algorithm: https://github.com/sisong/tinyuz
