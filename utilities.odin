// utilities.odin
// Shared utility functions for compression and decompression
//
// Provides endian conversion, bounds checking, and state management.

package tinyuz

// Little-endian encoding constants
DICT_POS_THRESHOLD :: (1 << 7)

// Write 32-bit unsigned integer in little-endian format
@(private)
write_u32_le :: proc(buffer: ^[dynamic]byte, value: uint) {
	remaining := value
	for i in 0..<TUZ_K_DICT_SIZE_SAVED_BYTES {
		append(buffer, byte(remaining & 0xFF))
		remaining >>= 8
	}
}

// Read 32-bit unsigned integer from little-endian format
@(private)
read_u32_le :: proc(buffer: []byte) -> (value: uint, ok: bool) {
	if len(buffer) < TUZ_K_DICT_SIZE_SAVED_BYTES {
		return 0, false
	}

	value = uint(buffer[0]) |
	        (uint(buffer[1]) << 8) |
	        (uint(buffer[2]) << 16) |
	        (uint(buffer[3]) << 24)

	return value, value > 0
}

// Check if there's enough space in output buffer
@(private)
check_output_space :: proc(cur_pos: int, required_bytes: int, buffer_size: int) -> bool {
	return (cur_pos + required_bytes) <= buffer_size
}

// Check if there's enough space, return error if not
@(private)
check_output_bounds :: proc(cur_pos: int, required_bytes: int, buffer_size: int) -> Result {
	if !check_output_space(cur_pos, required_bytes, buffer_size) {
		return .OUT_SIZE_OR_CODE_ERROR
	}
	return .OK
}

// Reset state flags for control code processing
@(private)
reset_control_state :: proc(dict_pos_back: ^uint, type_count: ^u8) {
	dict_pos_back^ = 1
	type_count^ = 0
}
