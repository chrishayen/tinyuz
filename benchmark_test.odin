// benchmark_test.odin
// Performance benchmarks for TinyUZ compression

package tinyuz

import "core:fmt"
import "core:time"
import "core:testing"

Benchmark_Result :: struct {
	name:              string,
	input_size:        int,
	compressed_size:   int,
	compress_time:     time.Duration,
	decompress_time:   time.Duration,
	compression_ratio: f32,
}

run_compression_benchmark :: proc(name: string, input: []byte, iterations: int = 1000) -> Benchmark_Result {
	compressed := make([]byte, len(input) * 2)
	defer delete(compressed)

	output := make([]byte, len(input))
	defer delete(output)

	// Warmup
	for i in 0 ..< 5 {
		compress_mem(input, compressed)
	}

	// Benchmark compression
	compress_start := time.now()
	compressed_size := 0
	for i in 0 ..< iterations {
		size, _ := compress_mem(input, compressed)
		compressed_size = size
	}
	compress_end := time.now()
	compress_time := time.diff(compress_start, compress_end)

	// Benchmark decompression
	decompress_start := time.now()
	for i in 0 ..< iterations {
		decompress_mem(compressed[:compressed_size], output)
	}
	decompress_end := time.now()
	decompress_time := time.diff(decompress_start, decompress_end)

	return Benchmark_Result{
		name = name,
		input_size = len(input),
		compressed_size = compressed_size,
		compress_time = compress_time / time.Duration(iterations),
		decompress_time = decompress_time / time.Duration(iterations),
		compression_ratio = f32(compressed_size) / f32(len(input)),
	}
}

@(test)
benchmark_solid_color :: proc(t: ^testing.T) {
	data := make([]byte, 120)
	defer delete(data)

	for i in 0 ..< 40 {
		data[i*3 + 0] = 0xFF
		data[i*3 + 1] = 0x00
		data[i*3 + 2] = 0x00
	}

	result := run_compression_benchmark("Solid color (40 LEDs)", data, 1000)

	fmt.printf("\n%-40s\n", result.name)
	fmt.printf("  Input: %d bytes → Compressed: %d bytes (%.1f%%)\n",
	           result.input_size, result.compressed_size, result.compression_ratio * 100)
	fmt.printf("  Compression:   %v (%.2f MB/s)\n",
	           result.compress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.compress_time))
	fmt.printf("  Decompression: %v (%.2f MB/s)\n",
	           result.decompress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.decompress_time))
}

@(test)
benchmark_repeating_pattern :: proc(t: ^testing.T) {
	data := make([]byte, 300)
	defer delete(data)

	for i in 0 ..< 100 {
		data[i*3 + 0] = 0xAA
		data[i*3 + 1] = 0xBB
		data[i*3 + 2] = 0xCC
	}

	result := run_compression_benchmark("Repeating pattern (100 LEDs)", data, 1000)

	fmt.printf("\n%-40s\n", result.name)
	fmt.printf("  Input: %d bytes → Compressed: %d bytes (%.1f%%)\n",
	           result.input_size, result.compressed_size, result.compression_ratio * 100)
	fmt.printf("  Compression:   %v (%.2f MB/s)\n",
	           result.compress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.compress_time))
	fmt.printf("  Decompression: %v (%.2f MB/s)\n",
	           result.decompress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.decompress_time))
}

@(test)
benchmark_large_solid :: proc(t: ^testing.T) {
	data := make([]byte, 3000)
	defer delete(data)

	for i in 0 ..< 1000 {
		data[i*3 + 0] = 0xFF
		data[i*3 + 1] = 0x00
		data[i*3 + 2] = 0x00
	}

	result := run_compression_benchmark("Large solid (1000 LEDs)", data, 1000)

	fmt.printf("\n%-40s\n", result.name)
	fmt.printf("  Input: %d bytes → Compressed: %d bytes (%.1f%%)\n",
	           result.input_size, result.compressed_size, result.compression_ratio * 100)
	fmt.printf("  Compression:   %v (%.2f MB/s)\n",
	           result.compress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.compress_time))
	fmt.printf("  Decompression: %v (%.2f MB/s)\n",
	           result.decompress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.decompress_time))
}

@(test)
benchmark_semi_random :: proc(t: ^testing.T) {
	data := make([]byte, 500)
	defer delete(data)

	for i in 0 ..< len(data) {
		data[i] = u8(i * 13 % 256)
	}

	result := run_compression_benchmark("Semi-random data", data, 1000)

	fmt.printf("\n%-40s\n", result.name)
	fmt.printf("  Input: %d bytes → Compressed: %d bytes (%.1f%%)\n",
	           result.input_size, result.compressed_size, result.compression_ratio * 100)
	fmt.printf("  Compression:   %v (%.2f MB/s)\n",
	           result.compress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.compress_time))
	fmt.printf("  Decompression: %v (%.2f MB/s)\n",
	           result.decompress_time,
	           f64(result.input_size) / (1024 * 1024) / time.duration_seconds(result.decompress_time))
}
