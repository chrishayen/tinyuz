// decompress.odin
// TinyUZ decompression implementation
//
// Decodes TinyUZ compressed data with minimal memory footprint.

package tinyuz

// Memory-based decompression state
Mem_Stream :: struct {
	in_code:      []byte,
	in_code_pos:  int,
	types:        u8,
	type_count:   u8,
}

// Read one byte from compressed stream
@(private)
mem_read_byte :: proc(self: ^Mem_Stream) -> (result: u8, ok: bool) {
	if self.in_code_pos < len(self.in_code) {
		result = self.in_code[self.in_code_pos]
		self.in_code_pos += 1
		return result, true
	}
	return 0, false
}

// Read low bits from type buffer
@(private)
mem_read_lowbits :: proc(self: ^Mem_Stream, bit_count: u8) -> u8 {
	count := self.type_count
	result := self.types

	if count >= bit_count {
		self.type_count = count - bit_count
		self.types = result >> bit_count
		return result
	} else {
		if self.in_code_pos < len(self.in_code) {
			v := self.in_code[self.in_code_pos]
			self.in_code_pos += 1
			bit_count := bit_count - count
			self.type_count = TUZ_K_MAX_TYPE_BIT_COUNT - bit_count
			self.types = v >> bit_count
			return result | (v << count)
		} else {
			return 0
		}
	}
}

// Unpack variable-length integer (2-bit encoding)
@(private)
mem_unpack_len :: proc(self: ^Mem_Stream) -> uint {
	v: uint = 0
	for {
		lowbit := mem_read_lowbits(self, 2)
		v = (v << 1) + uint(lowbit & 1)
		if (lowbit & 2) == 0 do return v
		v += 1
	}
}

// Unpack variable-length position (3-bit encoding)
@(private)
mem_unpack_pos_len :: proc(self: ^Mem_Stream) -> uint {
	v: uint = 0
	for {
		lowbit := mem_read_lowbits(self, 3)
		v = (v << 2) + uint(lowbit & 3)
		if (lowbit & 4) == 0 do return v
		v += 1
	}
}

// Unpack dictionary position
@(private)
mem_unpack_dict_pos :: proc(self: ^Mem_Stream) -> (result: uint, ok: bool) {
	if self.in_code_pos >= len(self.in_code) do return 0, false

	result = uint(self.in_code[self.in_code_pos])
	self.in_code_pos += 1

	if result >= DICT_POS_THRESHOLD {
		result = ((result & (DICT_POS_THRESHOLD - 1)) | (mem_unpack_pos_len(self) << 7)) + DICT_POS_THRESHOLD
	}
	return result, true
}

// Read dictionary size from beginning of compressed data
read_dict_size :: proc(in_code: []byte) -> (dict_size: uint, ok: bool) {
	return read_u32_le(in_code)
}

// Decompress state
Decompress_State :: struct {
	stream:            ^Mem_Stream,
	out_data:          []byte,
	cur_out_pos:       int,
	dict_pos_back:     uint,
	is_have_data_back: bool,
}

// Copy dictionary match from previous output
@(private)
copy_dict_match :: proc(state: ^Decompress_State, dict_pos: uint, match_len: uint) -> Result {
	// Safety checks
	if dict_pos > uint(state.cur_out_pos) {
		return .DICT_POS_ERROR
	}

	result := check_output_bounds(state.cur_out_pos, int(match_len), len(state.out_data))
	if result != .OK {
		return result
	}

	// Copy from dictionary (handles overlapping copies)
	src_pos := state.cur_out_pos - int(dict_pos)
	for i in 0..<match_len {
		state.out_data[state.cur_out_pos] = state.out_data[src_pos]
		state.cur_out_pos += 1
		src_pos += 1
	}

	return .OK
}

// Handle dictionary match
@(private)
handle_dict_match :: proc(state: ^Decompress_State, saved_len: uint, saved_dict_pos: uint) -> Result {
	dict_type_len := saved_len + TUZ_K_MIN_DICT_MATCH_LEN
	state.dict_pos_back = saved_dict_pos
	state.is_have_data_back = false

	return copy_dict_match(state, saved_dict_pos, dict_type_len)
}

// Handle literal line (15+ consecutive literal bytes)
@(private)
handle_literal_line :: proc(state: ^Decompress_State) -> Result {
	literal_len := mem_unpack_pos_len(state.stream) + TUZ_K_MIN_LITERAL_LEN

	result := check_output_bounds(state.cur_out_pos, int(literal_len), len(state.out_data))
	if result != .OK {
		return result
	}

	// Copy literal bytes from compressed stream
	for i in 0..<literal_len {
		b, ok := mem_read_byte(state.stream)
		if !ok {
			return .READ_CODE_ERROR
		}
		state.out_data[state.cur_out_pos] = b
		state.cur_out_pos += 1
	}

	state.is_have_data_back = true
	return .OK
}

// Handle control codes (CLIP_END, STREAM_END, etc)
@(private)
handle_control_code :: proc(state: ^Decompress_State, ctrl_type: uint) -> Result {
	reset_control_state(&state.dict_pos_back, &state.stream.type_count)

	if ctrl_type == TUZ_CTRL_TYPE_CLIP_END {
		return .CLIP_END
	}

	if ctrl_type == TUZ_CTRL_TYPE_STREAM_END {
		return .STREAM_END
	}

	return .CTRL_TYPE_UNKNOWN_ERROR
}

// Handle single literal byte
@(private)
handle_literal_byte :: proc(state: ^Decompress_State) -> Result {
	result := check_output_bounds(state.cur_out_pos, 1, len(state.out_data))
	if result != .OK {
		return result
	}

	b, ok := mem_read_byte(state.stream)
	if !ok {
		return .READ_CODE_ERROR
	}

	state.out_data[state.cur_out_pos] = b
	state.cur_out_pos += 1
	state.is_have_data_back = true

	return .OK
}

// Decode dictionary position from stream
@(private)
decode_dict_pos :: proc(state: ^Decompress_State, saved_len: ^uint) -> (dict_pos: uint, ok: bool) {
	if state.is_have_data_back && (mem_read_lowbits(state.stream, 1) & 1) != 0 {
		// Reuse previous position
		return state.dict_pos_back, true
	}

	// Read new position
	pos, pos_ok := mem_unpack_dict_pos(state.stream)
	if !pos_ok {
		return 0, false
	}

	// Adjust length for large positions
	if pos > TUZ_K_BIG_POS_FOR_LEN {
		saved_len^ += 1
	}

	return pos, true
}

// Decompress data from memory
//
// Args:
//     in_code: Compressed input data
//     out_data: Output buffer
//
// Returns:
//     decompressed_size: Number of bytes decompressed
//     result: Result code
decompress_mem :: proc(in_code: []byte, out_data: []byte) -> (decompressed_size: int, result: Result) {
	if len(in_code) < TUZ_K_DICT_SIZE_SAVED_BYTES {
		return 0, .READ_DICT_SIZE_ERROR
	}

	// Initialize stream
	stream := Mem_Stream{
		in_code = in_code,
		in_code_pos = TUZ_K_DICT_SIZE_SAVED_BYTES,
		types = 0,
		type_count = 0,
	}

	// Initialize state
	state := Decompress_State{
		stream = &stream,
		out_data = out_data,
		cur_out_pos = 0,
		dict_pos_back = 1,
		is_have_data_back = false,
	}

	for {
		// Read type bit
		type_bit := mem_read_lowbits(&stream, 1) & 1

		if type_bit == TUZ_CODE_TYPE_DICT {
			// Dictionary match or control
			saved_len := mem_unpack_len(&stream)
			saved_dict_pos, pos_ok := decode_dict_pos(&state, &saved_len)

			if !pos_ok {
				return 0, .READ_CODE_ERROR
			}

			state.is_have_data_back = false

			if saved_dict_pos != 0 {
				// Dictionary match
				res := handle_dict_match(&state, saved_len, saved_dict_pos)
				if res != .OK {
					return 0, res
				}
			} else {
				// Control code
				if saved_len == TUZ_CTRL_TYPE_LITERAL_LINE {
					res := handle_literal_line(&state)
					if res != .OK {
						return 0, res
					}
					continue
				}

				res := handle_control_code(&state, saved_len)
				if res == .STREAM_END {
					return state.cur_out_pos, .STREAM_END
				}
				if res == .CLIP_END {
					continue
				}
				if res != .OK {
					return 0, res
				}
			}
		} else {
			// Literal byte
			res := handle_literal_byte(&state)
			if res != .OK {
				return 0, res
			}
		}
	}

	// Should never reach here
	return 0, .CODE_ERROR
}
