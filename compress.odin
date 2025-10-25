// compress.odin
// TinyUZ compression implementation
//
// Implements LZ77 sliding window compression with bit-level encoding
// optimized for small repetitive datasets.

package tinyuz

// Encoder configuration
Compress_Props :: struct {
	dict_size:          int,
	max_save_length:    int,
	is_need_literal_line: bool,
}

// Default compression properties
DEFAULT_COMPRESS_PROPS :: Compress_Props {
	dict_size = 64 * 1024 - 1,
	max_save_length = 64 * 1024 - 1,
	is_need_literal_line = true,
}

// Internal encoder state
Tuz_Encoder :: struct {
	code:               [dynamic]byte,
	is_need_literal_line: bool,
	types_index:        int,
	type_count:         int,
	dict_pos_back:      int,
	dict_size_max:      int,
	is_have_data_back:  bool,
	props:              Compress_Props,
}

// Variable-length encoding pack bits
DICT_LEN_PACK_BIT :: 1
DICT_POS_LEN_PACK_BIT :: 2

// Initialize encoder
@(private)
encoder_init :: proc(props: Compress_Props) -> Tuz_Encoder {
	encoder := Tuz_Encoder {
		code = make([dynamic]byte, 0, 1024),
		is_need_literal_line = props.is_need_literal_line,
		type_count = 0,
		dict_pos_back = 1,
		dict_size_max = int(TUZ_K_MIN_DICT_SIZE),
		is_have_data_back = false,
		props = props,
	}
	return encoder
}

// Free encoder resources
@(private)
encoder_destroy :: proc(encoder: ^Tuz_Encoder) {
	delete(encoder.code)
}

// Output a single type bit
@(private)
out_type :: proc(encoder: ^Tuz_Encoder, bit_value: int) {
	if encoder.type_count == 0 {
		encoder.types_index = len(encoder.code)
		append(&encoder.code, 0)
	}

	encoder.code[encoder.types_index] |= byte(bit_value << uint(encoder.type_count))
	encoder.type_count += 1

	if encoder.type_count == TUZ_K_MAX_TYPE_BIT_COUNT {
		encoder.type_count = 0
	}
}

// Get output count for variable-length encoding
@(private)
get_out_count :: proc(v: int, pack_bit: int, dec: ^int = nil) -> int {
	count := 1
	_v := v
	remaining := v

	for {
		m := 1 << uint(count * pack_bit)
		if remaining < m do break
		remaining -= m
		count += 1
	}

	if dec != nil {
		dec^ = _v - remaining
	}
	return count
}

// Output variable-length encoded integer
@(private)
out_len :: proc(encoder: ^Tuz_Encoder, v: int, pack_bit: int) {
	dec: int
	c := get_out_count(v, pack_bit, &dec)
	remaining := v - dec

	for i := c - 1; i >= 0; i -= 1 {
		for bit_idx in 0..<pack_bit {
			bit := (remaining >> uint(i * pack_bit + bit_idx)) & 1
			out_type(encoder, bit)
		}
		out_type(encoder, i > 0 ? 1 : 0)
	}
}

// Output dictionary size header (4 bytes little-endian)
@(private)
out_dict_size :: proc(encoder: ^Tuz_Encoder, dict_size: int) {
	write_u32_le(&encoder.code, uint(dict_size))
}

// Output literal data
@(private)
out_data :: proc(encoder: ^Tuz_Encoder, data: []byte) {
	data_len := len(data)

	if encoder.is_need_literal_line && data_len >= TUZ_K_MIN_LITERAL_LEN {
		out_ctrl(encoder, .LITERAL_LINE)
		out_len(encoder, data_len - TUZ_K_MIN_LITERAL_LEN, DICT_POS_LEN_PACK_BIT)
		for b in data {
			append(&encoder.code, b)
		}
	} else {
		for b in data {
			out_type(encoder, TUZ_CODE_TYPE_DATA)
			append(&encoder.code, b)
		}
	}

	encoder.is_have_data_back = true
}

// Output dictionary position
@(private)
out_dict_pos :: proc(encoder: ^Tuz_Encoder, pos: int) {
	mut_pos := pos
	is_out_len := mut_pos >= DICT_POS_THRESHOLD
	if is_out_len {
		mut_pos -= DICT_POS_THRESHOLD
	}

	low_byte := byte(mut_pos & (DICT_POS_THRESHOLD - 1))
	if is_out_len {
		low_byte |= byte(DICT_POS_THRESHOLD)
	}
	append(&encoder.code, low_byte)

	if is_out_len {
		out_len(encoder, mut_pos >> 7, DICT_POS_LEN_PACK_BIT)
	}
}

// Output dictionary match
@(private)
out_dict :: proc(encoder: ^Tuz_Encoder, match_len: int, dict_pos: int) {
	out_type(encoder, TUZ_CODE_TYPE_DICT)

	saved_dict_pos := dict_pos + 1
	if saved_dict_pos > encoder.dict_size_max {
		encoder.dict_size_max = saved_dict_pos
	}

	is_same_pos := encoder.dict_pos_back == saved_dict_pos
	is_saved_same_pos := is_same_pos && encoder.is_have_data_back

	len_val := match_len - TUZ_K_MIN_DICT_MATCH_LEN
	if !is_saved_same_pos && saved_dict_pos > TUZ_K_BIG_POS_FOR_LEN {
		len_val -= 1
	}

	out_len(encoder, len_val, DICT_LEN_PACK_BIT)

	if encoder.is_have_data_back {
		out_type(encoder, is_saved_same_pos ? 1 : 0)
	}
	if !is_saved_same_pos {
		out_dict_pos(encoder, saved_dict_pos)
	}

	encoder.is_have_data_back = false
	encoder.dict_pos_back = saved_dict_pos
}

// Output control code
@(private)
out_ctrl :: proc(encoder: ^Tuz_Encoder, ctrl: Result) {
	out_type(encoder, TUZ_CODE_TYPE_DICT)
	out_len(encoder, int(ctrl), DICT_LEN_PACK_BIT)
	if encoder.is_have_data_back {
		out_type(encoder, 0)
	}
	out_dict_pos(encoder, 0)
}

// End types byte
@(private)
out_ctrl_types_end :: proc(encoder: ^Tuz_Encoder) {
	encoder.type_count = 0
	encoder.dict_pos_back = 1
	encoder.is_have_data_back = false
}

// Output stream end marker
@(private)
out_ctrl_stream_end :: proc(encoder: ^Tuz_Encoder) {
	out_ctrl(encoder, .STREAM_END)
	out_ctrl_types_end(encoder)
}

// Count matching bytes at two positions
@(private)
count_match_length :: proc(data: []byte, pos1: int, pos2: int, max_len: int) -> int {
	match_count := 0
	for match_count < max_len && pos2 + match_count < len(data) {
		if data[pos1 + match_count] != data[pos2 + match_count] {
			break
		}
		match_count += 1
	}
	return match_count
}

// Simple LZ77 match finder (sliding window)
@(private)
find_match :: proc(data: []byte, pos: int, dict_size: int, max_len: int) -> (match_pos: int, match_len: int) {
	best_len := 0
	best_pos := 0

	search_start := max(0, pos - dict_size)

	for search_pos := pos - 1; search_pos >= search_start; search_pos -= 1 {
		match_count := count_match_length(data, search_pos, pos, max_len)

		if match_count > best_len {
			best_len = match_count
			best_pos = pos - search_pos - 1
		}
	}

	return best_pos, best_len
}

// Check if match is worth encoding
@(private)
is_match_worthwhile :: proc(match_len: int) -> bool {
	return match_len >= TUZ_K_MIN_DICT_MATCH_LEN
}

// Flush pending literal data
@(private)
flush_literals :: proc(encoder: ^Tuz_Encoder, data: []byte, start: int, end: int) {
	if end > start {
		out_data(encoder, data[start:end])
	}
}

// Process match found during compression
@(private)
process_match :: proc(encoder: ^Tuz_Encoder, in_data: []byte, literal_start: ^int, pos: ^int, match_pos: int, match_len: int) {
	// Flush any pending literals
	flush_literals(encoder, in_data, literal_start^, pos^)

	// Output the dictionary match
	out_dict(encoder, match_len, match_pos)

	// Advance position
	pos^ += match_len
	literal_start^ = pos^
}

// Finalize compression and copy to output buffer
@(private)
finalize_compression :: proc(encoder: ^Tuz_Encoder, out_code: []byte) -> (compressed_size: int, result: Result) {
	if len(encoder.code) > len(out_code) {
		return 0, .OUT_SIZE_OR_CODE_ERROR
	}

	copy(out_code, encoder.code[:])
	return len(encoder.code), .OK
}

// Compress data to TUZ format
compress_mem :: proc(in_data: []byte, out_code: []byte, dict_size: uint = 64 * 1024 - 1, allocator := context.allocator) -> (compressed_size: int, result: Result) {
	props := Compress_Props {
		dict_size = int(dict_size),
		max_save_length = 64 * 1024 - 1,
		is_need_literal_line = true,
	}

	encoder := encoder_init(props)
	defer encoder_destroy(&encoder)

	out_dict_size(&encoder, props.dict_size)

	pos := 0
	literal_start := 0

	// Main compression loop
	for pos < len(in_data) {
		match_pos, match_len := find_match(in_data, pos, props.dict_size, props.max_save_length)

		if is_match_worthwhile(match_len) {
			process_match(&encoder, in_data, &literal_start, &pos, match_pos, match_len)
		} else {
			pos += 1
		}
	}

	// Flush remaining literals
	flush_literals(&encoder, in_data, literal_start, len(in_data))

	// End the stream
	out_ctrl_stream_end(&encoder)

	// Copy to output buffer
	return finalize_compression(&encoder, out_code)
}
