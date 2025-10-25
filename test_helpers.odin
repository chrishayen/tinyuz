// test_helpers.odin
// Helper functions for testing compression/decompression

package tinyuz

import "core:testing"

// Compress input data and verify compression succeeded
compress_data :: proc(t: ^testing.T, input: []byte, dict_size: uint = 64 * 1024 - 1) -> (compressed: []byte, compressed_size: int) {
	compressed = make([]byte, len(input) * 2 + 256)

	comp_size, comp_result := compress_mem(input, compressed, dict_size)
	testing.expect(t, comp_result == .OK, "Compression should succeed")

	return compressed, comp_size
}

// Decompress data and verify decompression succeeded
decompress_data :: proc(t: ^testing.T, compressed: []byte, expected_size: int) -> []byte {
	output := make([]byte, expected_size)

	dec_size, dec_result := decompress_mem(compressed, output)
	testing.expect(t, dec_result == .STREAM_END, "Decompression should succeed")
	testing.expect(t, dec_size == expected_size, "Decompressed size should match expected")

	return output
}

// Verify two byte slices are identical
verify_data_match :: proc(t: ^testing.T, actual: []byte, expected: []byte, message: string = "Data should match") {
	testing.expect(t, len(actual) == len(expected), "Lengths should match")

	for i in 0 ..< len(expected) {
		if actual[i] != expected[i] {
			testing.expectf(t, false, "%s (mismatch at byte %d: got %d, expected %d)",
			                message, i, actual[i], expected[i])
			return
		}
	}
}

// Full round-trip test: compress, decompress, and verify
test_roundtrip :: proc(t: ^testing.T, input: []byte, dict_size: uint = 64 * 1024 - 1) -> bool {
	// Compress
	compressed, compressed_size := compress_data(t, input, dict_size)
	defer delete(compressed)

	// Decompress
	output := decompress_data(t, compressed[:compressed_size], len(input))
	defer delete(output)

	// Verify
	verify_data_match(t, output, input)

	return true
}

// Test round-trip and return compression ratio
test_roundtrip_with_ratio :: proc(t: ^testing.T, input: []byte, dict_size: uint = 64 * 1024 - 1) -> (ratio: f32, compressed_size: int) {
	// Compress
	compressed, comp_size := compress_data(t, input, dict_size)
	defer delete(compressed)

	// Decompress
	output := decompress_data(t, compressed[:comp_size], len(input))
	defer delete(output)

	// Verify
	verify_data_match(t, output, input)

	// Calculate ratio
	if len(input) > 0 {
		ratio = f32(comp_size) / f32(len(input))
	}

	return ratio, comp_size
}

// Verify compression achieves expected ratio
verify_compression_ratio :: proc(t: ^testing.T, input: []byte, max_ratio: f32, message: string = "Should compress well") {
	ratio, compressed_size := test_roundtrip_with_ratio(t, input)
	testing.expectf(t, ratio <= max_ratio, "%s (ratio: %.2f, size: %d -> %d)",
	                message, ratio, len(input), compressed_size)
}

// Verify compression expands or maintains size (for incompressible data)
verify_low_compression :: proc(t: ^testing.T, input: []byte) {
	compressed, compressed_size := compress_data(t, input)
	defer delete(compressed)

	// Should still decompress correctly even if not well compressed
	output := decompress_data(t, compressed[:compressed_size], len(input))
	defer delete(output)

	verify_data_match(t, output, input)
}
