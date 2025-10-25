// test_errors.odin
// Error handling and edge case tests

package tinyuz

import "core:testing"

@(test)
test_decompress_buffer_too_small :: proc(t: ^testing.T) {
	// Compress some data first
	input := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	compressed := make([]byte, 64)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Compression should succeed")

	// Try to decompress into a buffer that's too small
	output := make([]byte, 5)
	defer delete(output)

	_, decomp_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, decomp_result != .STREAM_END, "Should fail with small buffer")
	testing.expect(t, decomp_result == .OUT_SIZE_OR_CODE_ERROR, "Should return buffer size error")
}

@(test)
test_compress_buffer_too_small :: proc(t: ^testing.T) {
	// Random data that won't compress well
	input := make([]byte, 100)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i * 13 % 256)
	}

	// Provide a very small output buffer
	compressed := make([]byte, 10)
	defer delete(compressed)

	_, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OUT_SIZE_OR_CODE_ERROR, "Should fail with small output buffer")
}

@(test)
test_decompress_corrupted_header :: proc(t: ^testing.T) {
	// Create data that's too short to contain header
	corrupted := []byte{0x00, 0x01}
	output := make([]byte, 100)
	defer delete(output)

	_, result := decompress_mem(corrupted, output)
	testing.expect(t, result == .READ_DICT_SIZE_ERROR, "Should fail with corrupted header")
}

@(test)
test_decompress_truncated_data :: proc(t: ^testing.T) {
	// Compress valid data
	input := []byte{1, 2, 3, 4, 5}
	compressed := make([]byte, 64)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Compression should succeed")

	// Truncate the compressed data
	truncated := compressed[:compressed_size/2]
	output := make([]byte, len(input))
	defer delete(output)

	_, decomp_result := decompress_mem(truncated, output)
	testing.expect(t, decomp_result != .STREAM_END, "Should fail with truncated data")
}

@(test)
test_decompress_invalid_dict_pos :: proc(t: ^testing.T) {
	// Create malformed compressed data with invalid dictionary position
	// Header: dict_size = 64 (0x40, 0x00, 0x00, 0x00)
	// Then add malformed control codes
	corrupted := []byte{
		0x40, 0x00, 0x00, 0x00, // dict_size = 64
		0x00, // type bit = dict
		0xFF, // Invalid position that references before start
	}
	output := make([]byte, 100)
	defer delete(output)

	_, result := decompress_mem(corrupted, output)
	testing.expect(t, result != .STREAM_END, "Should fail with invalid dict position")
}

@(test)
test_read_dict_size_invalid :: proc(t: ^testing.T) {
	// Too short
	short_data := []byte{0x00, 0x01}
	_, ok := read_dict_size(short_data)
	testing.expect(t, !ok, "Should fail with too-short data")

	// Zero dict size
	zero_dict := []byte{0x00, 0x00, 0x00, 0x00}
	_, ok2 := read_dict_size(zero_dict)
	testing.expect(t, !ok2, "Should fail with zero dict size")
}

@(test)
test_compress_very_large_dict :: proc(t: ^testing.T) {
	// Test with maximum dictionary size
	input := make([]byte, 100)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i % 256)
	}

	compressed := make([]byte, 256)
	defer delete(compressed)

	// Use maximum dict size
	max_dict := uint(TUZ_K_MAX_DICT_SIZE)
	compressed_size, comp_result := compress_mem(input, compressed, max_dict)
	testing.expect(t, comp_result == .OK, "Should handle max dict size")

	// Verify dict size in header
	dict_size, ok := read_dict_size(compressed[:compressed_size])
	testing.expect(t, ok, "Should read dict size")
	testing.expect(t, dict_size == max_dict, "Should preserve max dict size")
}

@(test)
test_compress_minimum_dict :: proc(t: ^testing.T) {
	// Test with minimum dictionary size
	input := []byte{1, 2, 3, 4, 5}

	compressed := make([]byte, 64)
	defer delete(compressed)

	// Use minimum dict size
	min_dict := uint(TUZ_K_MIN_DICT_SIZE)
	compressed_size, comp_result := compress_mem(input, compressed, min_dict)
	testing.expect(t, comp_result == .OK, "Should handle min dict size")

	// Verify it decompresses correctly
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress with min dict")
	testing.expect(t, dec_size == len(input), "Should match input size")
}

@(test)
test_compress_literal_line_threshold :: proc(t: ^testing.T) {
	// Create data that's exactly at the LITERAL_LINE threshold (15 bytes)
	input := make([]byte, TUZ_K_MIN_LITERAL_LEN)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i * 17 % 256)
	}

	compressed := make([]byte, 128)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should compress literal line threshold")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == input[i], "Data should match")
	}
}

@(test)
test_compress_below_literal_threshold :: proc(t: ^testing.T) {
	// Create data just below LITERAL_LINE threshold (14 bytes)
	input := make([]byte, TUZ_K_MIN_LITERAL_LEN - 1)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i * 23 % 256)
	}

	compressed := make([]byte, 128)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should compress below literal threshold")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")
}

@(test)
test_compress_long_match_sequence :: proc(t: ^testing.T) {
	// Create data with a very long repeating sequence
	input := make([]byte, 1000)
	defer delete(input)

	// Fill with same pattern
	pattern := []byte{0xAA, 0xBB, 0xCC}
	for i in 0 ..< len(input) {
		input[i] = pattern[i % len(pattern)]
	}

	compressed := make([]byte, 2000)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should compress long match")
	testing.expect(t, compressed_size < len(input) / 5, "Should compress very well")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == input[i], "Data should match")
	}
}

@(test)
test_compress_all_zeros :: proc(t: ^testing.T) {
	// All zeros (maximum compression)
	input := make([]byte, 500)
	defer delete(input)
	// Already zeroed by make

	compressed := make([]byte, 1000)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should compress all zeros")
	testing.expect(t, compressed_size < 50, "Should compress extremely well")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == 0, "Should be zero")
	}
}

@(test)
test_compress_all_different :: proc(t: ^testing.T) {
	// All different bytes (minimal compression)
	input := make([]byte, 256)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = u8(i)
	}

	compressed := make([]byte, 512)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should handle non-compressible data")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == input[i], "Data should match")
	}
}

@(test)
test_compress_two_byte_match :: proc(t: ^testing.T) {
	// Test minimum match length (2 bytes)
	input := []byte{0xAA, 0xBB, 0xAA, 0xBB, 0xCC, 0xDD}

	compressed := make([]byte, 64)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should compress 2-byte matches")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == input[i], "Data should match")
	}
}

@(test)
test_compress_overlapping_match :: proc(t: ^testing.T) {
	// Test self-referential pattern (like RLE)
	// "AAAA" can be encoded as "A" + dict_match(pos=1, len=3)
	input := make([]byte, 20)
	defer delete(input)

	for i in 0 ..< len(input) {
		input[i] = 0xFF
	}

	compressed := make([]byte, 64)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should handle overlapping matches")
	testing.expect(t, compressed_size < len(input), "Should compress")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == 0xFF, "All bytes should be 0xFF")
	}
}

@(test)
test_compress_binary_data :: proc(t: ^testing.T) {
	// Test with binary data including null bytes
	input := []byte{
		0x00, 0x01, 0x02, 0x00, 0x00, 0xFF, 0xFE, 0xFD,
		0x00, 0x01, 0x02, 0x00, 0x00, 0xFF, 0xFE, 0xFD,
	}

	compressed := make([]byte, 128)
	defer delete(compressed)

	compressed_size, comp_result := compress_mem(input, compressed)
	testing.expect(t, comp_result == .OK, "Should handle binary data")

	// Verify decompression
	output := make([]byte, len(input))
	defer delete(output)

	dec_size, dec_result := decompress_mem(compressed[:compressed_size], output)
	testing.expect(t, dec_result == .STREAM_END, "Should decompress")
	testing.expect(t, dec_size == len(input), "Size should match")

	for i in 0 ..< len(input) {
		testing.expect(t, output[i] == input[i], "Binary data should match")
	}
}
