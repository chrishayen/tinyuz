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

- Pure Odin implementation with no external dependencies
- Lossless compression optimized for small, repetitive data
- Minimal RAM requirements (dict_size + cache_size)
- Comprehensive error handling and bounds checking
- Well-tested with 54 tests and ~95% code coverage

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

Benchmarks run on Linux x86-64 with `-o:speed` optimization.

### Compression Ratios

| Data Type | Ratio | Example |
|-----------|-------|---------|
| Solid colors | 90-95% reduction | 120 bytes → 12 bytes |
| Repeating patterns | 95%+ reduction | 300 bytes → 13 bytes |
| Large blocks | 99%+ reduction | 3000 bytes → 13 bytes |
| Semi-random | 50% reduction | 500 bytes → 268 bytes |

### Speed (Average per Operation)

| Data Type | Compression | Decompression |
|-----------|-------------|---------------|
| Solid color (120 bytes) | 340 MB/s (337ns) | 1,900 MB/s (60ns) |
| Repeating (300 bytes) | 660 MB/s (432ns) | 2,270 MB/s (126ns) |
| Large (3000 bytes) | 1,760 MB/s (1.6µs) | 2,300 MB/s (1.2µs) |
| Semi-random (500 bytes) | 12 MB/s (40µs) | 12,000 MB/s (39ns) |

**Key Characteristics**:
- Decompression is 5-10x faster than compression
- Sub-microsecond operation times for small data (60ns - 1.6µs)

See [BENCHMARKS.md](BENCHMARKS.md) for detailed results.

### Memory Usage

**Runtime**:
- Decompressor: ~dict_size bytes RAM
- Compressor: ~dict_size + output buffer
- No hidden allocations

**Code size**:
- Decompressor: 300-600 bytes (C reference)
- Compressor: ~2KB (C reference)
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
- 48 comprehensive tests (44 functional + 4 benchmarks)
- Compression/decompression round trips
- Error handling (buffer overflow, corrupted data)
- Edge cases (empty data, single byte, maximum sizes)
- Internal function unit tests
- Performance benchmarks
- ~95% code coverage

## License

MIT License

This implementation is based on the TinyUZ algorithm:
- Copyright (c) 2012-2025 HouSisong
- Algorithm: https://github.com/sisong/tinyuz

## References

- Odin Programming Language: https://odin-lang.org
- TinyUZ Algorithm: https://github.com/sisong/tinyuz
