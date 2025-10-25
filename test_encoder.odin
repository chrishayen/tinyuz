// test_encoder.odin
// Tests for TinyUZ compression/decompression

package tinyuz

import "core:testing"

@(test)
test_compress_solid_red_pattern :: proc(t: ^testing.T) {
	// Solid red pattern (40 LEDs = 120 bytes)
	input := make([]byte, 40 * 3)
	defer delete(input)

	for i := 0; i < 40; i += 1 {
		input[i * 3 + 0] = 255 // R
		input[i * 3 + 1] = 0   // G
		input[i * 3 + 2] = 0   // B
	}

	// Should compress very well (solid color)
	verify_compression_ratio(t, input, 0.5, "Solid color should compress to < 50%")
}

@(test)
test_compress_alternating_pattern :: proc(t: ^testing.T) {
	// Alternating red/blue pattern
	input := make([]byte, 40 * 3)
	defer delete(input)

	for i := 0; i < 40; i += 1 {
		if i % 2 == 0 {
			input[i * 3 + 0] = 255 // Red
			input[i * 3 + 1] = 0
			input[i * 3 + 2] = 0
		} else {
			input[i * 3 + 0] = 0   // Blue
			input[i * 3 + 1] = 0
			input[i * 3 + 2] = 255
		}
	}

	// Alternating pattern should still compress
	test_roundtrip(t, input)
}

@(test)
test_compress_large_solid_pattern :: proc(t: ^testing.T) {
	// Large solid red pattern (1000 LEDs = 3000 bytes)
	input := make([]byte, 1000 * 3)
	defer delete(input)

	for i := 0; i < 1000; i += 1 {
		input[i * 3 + 0] = 255
		input[i * 3 + 1] = 0
		input[i * 3 + 2] = 0
	}

	// Large solid pattern should compress extremely well (< 10%)
	verify_compression_ratio(t, input, 0.1, "Large solid pattern should compress to < 10%")
}

@(test)
test_compress_single_byte :: proc(t: ^testing.T) {
	input := []byte{42}
	test_roundtrip(t, input)
}

@(test)
test_compress_random_data :: proc(t: ^testing.T) {
	// Random-ish data (less compressible)
	input := make([]byte, 100)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i * 7 % 256)
	}

	// Should still round-trip correctly
	verify_low_compression(t, input)
}

@(test)
test_read_dict_size :: proc(t: ^testing.T) {
	// Create compressed data with known dict size
	input := []byte{0xFF, 0xFF, 0xFF}
	compressed := make([]byte, 64)
	defer delete(compressed)

	dict_size := uint(1024)
	compressed_size, comp_result := compress_mem(input, compressed, dict_size)
	testing.expect(t, comp_result == .OK, "Compression should succeed")

	// Read dict size
	read_size, ok := read_dict_size(compressed[:compressed_size])
	testing.expect(t, ok, "Should read dict size")
	testing.expect(t, read_size == dict_size, "Dict size should match")
}

@(test)
test_compress_with_custom_dict_size :: proc(t: ^testing.T) {
	input := []byte{1, 1, 1, 1, 1, 1, 1, 1}
	test_roundtrip(t, input, 256)
}

@(test)
test_empty_data :: proc(t: ^testing.T) {
	input := []byte{}
	test_roundtrip(t, input)
}

