# TinyUZ Performance Benchmarks

Benchmarks run on Linux x86-64 with optimization level `-o:speed`.

## Compression Performance

All benchmarks use 1000 iterations (average times reported).

### Highly Compressible Data

| Test Case | Input Size | Compressed Size | Ratio | Compress Speed | Decompress Speed |
|-----------|------------|-----------------|-------|----------------|------------------|
| Solid color (40 LEDs) | 120 bytes | 12 bytes | 10.0% | 339 MB/s | 1,907 MB/s |
| Repeating pattern (100 LEDs) | 300 bytes | 13 bytes | 4.3% | 662 MB/s | 2,270 MB/s |
| Large solid (1000 LEDs) | 3000 bytes | 13 bytes | 0.4% | 1,761 MB/s | 2,298 MB/s |

### Less Compressible Data

| Test Case | Input Size | Compressed Size | Ratio | Compress Speed | Decompress Speed |
|-----------|------------|-----------------|-------|----------------|------------------|
| Semi-random data | 500 bytes | 268 bytes | 53.6% | 11.7 MB/s | 12,226 MB/s |

## Key Observations

### Compression Ratios
- **Solid colors**: Compress to ~10% of original size (90% reduction)
- **Repeating patterns**: Compress to ~4-5% (95% reduction)
- **Large solid blocks**: Compress to < 1% (99%+ reduction)
- **Semi-random data**: Compresses to ~50% (50% reduction)

### Speed Characteristics

**Compression**:
- **Best case** (repetitive data): 300-1,700 MB/s
- **Worst case** (random data): 12 MB/s
- Scales well with data size (larger blocks = faster per-byte)

**Decompression**:
- **Typical**: 1,900-2,300 MB/s
- **Random data**: 12,000+ MB/s (minimal dictionary lookups)
- Consistently fast across all data types
- 5-10x faster than compression

### Efficiency

- **Time per operation**: 60ns - 1.6µs
- **Overhead**: Minimal (4-byte header only)
- **Memory**: Proportional to dictionary size (default 64KB)

## Conclusions

TinyUZ delivers good performance for small repetitive datasets:
- **90-99% compression** on solid colors and patterns (LED use case)
- **Sub-microsecond** compression/decompression times (60ns - 1.6µs)

## Running Benchmarks

```bash
odin test . -all-packages -o:speed -define:ODIN_TEST_NAMES=tinyuz.benchmark_solid_color,tinyuz.benchmark_repeating_pattern,tinyuz.benchmark_large_solid,tinyuz.benchmark_semi_random
```
