// test_internals.odin
// Tests for internal helper functions

package tinyuz

import "core:testing"

// Test count_match_length function
@(test)
test_count_match_length_identical :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 4, 5, 1, 2, 3, 4, 5}

	// Perfect match
	match_len := count_match_length(data, 0, 5, 5)
	testing.expect(t, match_len == 5, "Should find 5-byte match")
}

@(test)
test_count_match_length_partial :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 4, 5, 1, 2, 9, 9, 9}

	// Partial match (only first 2 bytes match)
	match_len := count_match_length(data, 0, 5, 10)
	testing.expect(t, match_len == 2, "Should find 2-byte match")
}

@(test)
test_count_match_length_no_match :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

	// No match
	match_len := count_match_length(data, 0, 5, 5)
	testing.expect(t, match_len == 0, "Should find no match")
}

@(test)
test_count_match_length_boundary :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 1, 2}

	// Match limited by buffer end (only 2 bytes match before end)
	match_len := count_match_length(data, 0, 3, 10)
	testing.expect(t, match_len == 2, "Should be limited by buffer end")
}

@(test)
test_count_match_length_max_limit :: proc(t: ^testing.T) {
	data := make([]byte, 100)
	defer delete(data)

	// Fill with same value
	for i in 0 ..< len(data) {
		data[i] = 0xAA
	}

	// Should be limited by max_len parameter
	match_len := count_match_length(data, 0, 1, 10)
	testing.expect(t, match_len == 10, "Should respect max_len limit")
}

// Test is_match_worthwhile function
@(test)
test_is_match_worthwhile :: proc(t: ^testing.T) {
	// Below minimum
	testing.expect(t, !is_match_worthwhile(0), "0-byte match not worthwhile")
	testing.expect(t, !is_match_worthwhile(1), "1-byte match not worthwhile")

	// At minimum (TUZ_K_MIN_DICT_MATCH_LEN = 2)
	testing.expect(t, is_match_worthwhile(2), "2-byte match is worthwhile")

	// Above minimum
	testing.expect(t, is_match_worthwhile(3), "3-byte match is worthwhile")
	testing.expect(t, is_match_worthwhile(100), "100-byte match is worthwhile")
}

// Test find_match function
@(test)
test_find_match_simple :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 1, 2, 3}

	// Should find match at position 3 for data at position 0
	match_pos, match_len := find_match(data, 3, 1024, 10)
	testing.expect(t, match_len == 3, "Should find 3-byte match")
	testing.expect(t, match_pos == 2, "Match should be at relative position 2")
}

@(test)
test_find_match_no_match :: proc(t: ^testing.T) {
	data := []byte{1, 2, 3, 4, 5, 6}

	// No repeating patterns
	match_pos, match_len := find_match(data, 3, 1024, 10)
	testing.expect(t, match_len == 0, "Should find no match")
}

@(test)
test_find_match_best_match :: proc(t: ^testing.T) {
	// Multiple potential matches, should pick longest
	// Pattern: [1,2,3,4] appears twice
	data := []byte{1, 2, 3, 4, 5, 1, 2, 3, 4}

	// At position 5, should find the 4-byte match at position 0
	match_pos, match_len := find_match(data, 5, 1024, 10)
	testing.expect(t, match_len == 4, "Should find longest match (4 bytes)")
	testing.expect(t, match_pos == 4, "Match should be at relative position 4")
}

@(test)
test_find_match_dict_size_limit :: proc(t: ^testing.T) {
	// Test that dictionary size limits the search window
	data := make([]byte, 100)
	defer delete(data)

	// Fill with pattern
	for i in 0 ..< len(data) {
		data[i] = u8(i % 10)
	}

	// Small dictionary should only look back 10 bytes
	match_pos, match_len := find_match(data, 50, 10, 20)
	testing.expect(t, match_len > 0, "Should find some match")
	testing.expect(t, match_pos <= 9, "Match position should respect dict_size")
}

@(test)
test_find_match_overlapping :: proc(t: ^testing.T) {
	// Test self-referential patterns (RLE)
	data := []byte{0xFF, 0xFF, 0xFF, 0xFF}

	// At position 1, should find match with position 0
	match_pos, match_len := find_match(data, 1, 1024, 10)
	testing.expect(t, match_len >= 2, "Should find overlapping match")
}

// Test copy_dict_match function
@(test)
test_copy_dict_match_simple :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	output := make([]byte, 20)
	defer delete(output)

	// Setup: put some data in output buffer
	output[0] = 0xAA
	output[1] = 0xBB
	output[2] = 0xCC

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 3,
		dict_pos_back = 1,
		is_have_data_back = false,
	}

	// Copy 3 bytes from position 3 (dict_pos=3 means 3 bytes back)
	result := copy_dict_match(&state, 3, 3)
	testing.expect(t, result == .OK, "Copy should succeed")
	testing.expect(t, state.cur_out_pos == 6, "Position should advance by 3")

	// Verify copied data
	testing.expect(t, output[3] == 0xAA, "First byte should match")
	testing.expect(t, output[4] == 0xBB, "Second byte should match")
	testing.expect(t, output[5] == 0xCC, "Third byte should match")
}

@(test)
test_copy_dict_match_overlapping :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	output := make([]byte, 20)
	defer delete(output)

	// Setup: RLE pattern
	output[0] = 0xFF

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 1,
		dict_pos_back = 1,
		is_have_data_back = false,
	}

	// Copy 5 bytes from position 1 (copies from itself)
	result := copy_dict_match(&state, 1, 5)
	testing.expect(t, result == .OK, "Overlapping copy should succeed")
	testing.expect(t, state.cur_out_pos == 6, "Position should advance")

	// Verify all bytes are 0xFF
	for i in 0 ..< 6 {
		testing.expect(t, output[i] == 0xFF, "All bytes should be 0xFF")
	}
}

@(test)
test_copy_dict_match_invalid_pos :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	output := make([]byte, 20)
	defer delete(output)

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 5,
		dict_pos_back = 1,
		is_have_data_back = false,
	}

	// Try to copy from position 10 (beyond current position)
	result := copy_dict_match(&state, 10, 3)
	testing.expect(t, result == .DICT_POS_ERROR, "Should fail with invalid position")
}

@(test)
test_copy_dict_match_buffer_overflow :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	output := make([]byte, 10)
	defer delete(output)

	output[0] = 0xAA

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 5,
		dict_pos_back = 1,
		is_have_data_back = false,
	}

	// Try to copy more bytes than output buffer can hold
	result := copy_dict_match(&state, 2, 10)
	testing.expect(t, result == .OUT_SIZE_OR_CODE_ERROR, "Should fail with buffer overflow")
}

// Test handle_control_code function
@(test)
test_handle_control_code_stream_end :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	state := Decompress_State{
		stream = &stream,
		dict_pos_back = 5,
	}

	result := handle_control_code(&state, TUZ_CTRL_TYPE_STREAM_END)
	testing.expect(t, result == .STREAM_END, "Should return STREAM_END")
	testing.expect(t, state.dict_pos_back == 1, "Should reset dict_pos_back")
	testing.expect(t, state.stream.type_count == 0, "Should reset type_count")
}

@(test)
test_handle_control_code_clip_end :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	state := Decompress_State{
		stream = &stream,
		dict_pos_back = 5,
	}

	result := handle_control_code(&state, TUZ_CTRL_TYPE_CLIP_END)
	testing.expect(t, result == .CLIP_END, "Should return CLIP_END")
	testing.expect(t, state.dict_pos_back == 1, "Should reset dict_pos_back")
}

@(test)
test_handle_control_code_unknown :: proc(t: ^testing.T) {
	stream := Mem_Stream{}
	state := Decompress_State{
		stream = &stream,
	}

	result := handle_control_code(&state, 99)
	testing.expect(t, result == .CTRL_TYPE_UNKNOWN_ERROR, "Should return unknown error")
}

// Test handle_literal_byte function
@(test)
test_handle_literal_byte_success :: proc(t: ^testing.T) {
	compressed := []byte{0x00, 0x00, 0x00, 0x00, 0x42}
	stream := Mem_Stream{
		in_code = compressed,
		in_code_pos = 4,
	}
	output := make([]byte, 10)
	defer delete(output)

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 0,
		is_have_data_back = false,
	}

	result := handle_literal_byte(&state)
	testing.expect(t, result == .OK, "Should succeed")
	testing.expect(t, state.cur_out_pos == 1, "Position should advance")
	testing.expect(t, output[0] == 0x42, "Should write correct byte")
	testing.expect(t, state.is_have_data_back == true, "Should set data back flag")
}

@(test)
test_handle_literal_byte_buffer_full :: proc(t: ^testing.T) {
	compressed := []byte{0x00, 0x00, 0x00, 0x00, 0x42}
	stream := Mem_Stream{
		in_code = compressed,
		in_code_pos = 4,
	}
	output := make([]byte, 5)
	defer delete(output)

	state := Decompress_State{
		stream = &stream,
		out_data = output,
		cur_out_pos = 5, // Buffer is full
		is_have_data_back = false,
	}

	result := handle_literal_byte(&state)
	testing.expect(t, result == .OUT_SIZE_OR_CODE_ERROR, "Should fail with full buffer")
}
