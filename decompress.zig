// decompress.zig
// TinyUZ decompression implementation
//
// Decodes TinyUZ compressed data with minimal memory footprint.

const std = @import("std");
const tinyuz = @import("tinyuz.zig");
const utilities = @import("utilities.zig");

// Memory-based decompression state
const MemStream = struct {
    in_code: []const u8,
    in_code_pos: usize,
    types: u8,
    type_count: u8,
};

/// Read one byte from compressed stream
fn memReadByte(self: *MemStream) ?u8 {
    if (self.in_code_pos < self.in_code.len) {
        const result = self.in_code[self.in_code_pos];
        self.in_code_pos += 1;
        return result;
    }
    return null;
}

/// Read low bits from type buffer
fn memReadLowbits(self: *MemStream, bit_count: u8) u8 {
    const count = self.type_count;
    const result = self.types;

    if (count >= bit_count) {
        self.type_count = count - bit_count;
        self.types = result >> @intCast(bit_count);
        return result;
    } else {
        if (self.in_code_pos < self.in_code.len) {
            const v = self.in_code[self.in_code_pos];
            self.in_code_pos += 1;
            const needed_bits = bit_count - count;
            self.type_count = tinyuz.TUZ_K_MAX_TYPE_BIT_COUNT - needed_bits;
            self.types = v >> @intCast(needed_bits);
            return result | (v << @intCast(count));
        } else {
            return 0;
        }
    }
}

/// Unpack variable-length integer (2-bit encoding)
fn memUnpackLen(self: *MemStream) u32 {
    var v: u32 = 0;
    while (true) {
        const lowbit = memReadLowbits(self, 2);
        v = (v << 1) + @as(u32, lowbit & 1);
        if ((lowbit & 2) == 0) return v;
        v += 1;
    }
}

/// Unpack variable-length position (3-bit encoding)
fn memUnpackPosLen(self: *MemStream) u32 {
    var v: u32 = 0;
    while (true) {
        const lowbit = memReadLowbits(self, 3);
        v = (v << 2) + @as(u32, lowbit & 3);
        if ((lowbit & 4) == 0) return v;
        v += 1;
    }
}

/// Unpack dictionary position
fn memUnpackDictPos(self: *MemStream) ?u32 {
    if (self.in_code_pos >= self.in_code.len) return null;

    var result: u32 = self.in_code[self.in_code_pos];
    self.in_code_pos += 1;

    if (result >= utilities.DICT_POS_THRESHOLD) {
        result = ((result & (utilities.DICT_POS_THRESHOLD - 1)) | (memUnpackPosLen(self) << 7)) + utilities.DICT_POS_THRESHOLD;
    }
    return result;
}

/// Read dictionary size from beginning of compressed data
pub fn readDictSize(in_code: []const u8) !u32 {
    return utilities.readU32Le(in_code);
}

// Decompress state
const DecompressState = struct {
    stream: *MemStream,
    out_data: []u8,
    cur_out_pos: usize,
    dict_pos_back: u32,
    is_have_data_back: bool,
};

/// Copy dictionary match from previous output
fn copyDictMatch(state: *DecompressState, dict_pos: u32, match_len: u32) !void {
    // Safety checks
    if (dict_pos > state.cur_out_pos) {
        return error.DictPosError;
    }

    try utilities.checkOutputBounds(state.cur_out_pos, match_len, state.out_data.len);

    // Copy from dictionary (handles overlapping copies)
    var src_pos = state.cur_out_pos - dict_pos;
    var i: u32 = 0;
    while (i < match_len) : (i += 1) {
        state.out_data[state.cur_out_pos] = state.out_data[src_pos];
        state.cur_out_pos += 1;
        src_pos += 1;
    }
}

/// Handle dictionary match
fn handleDictMatch(state: *DecompressState, saved_len: u32, saved_dict_pos: u32) !void {
    const dict_type_len = saved_len + tinyuz.TUZ_K_MIN_DICT_MATCH_LEN;
    state.dict_pos_back = saved_dict_pos;
    state.is_have_data_back = false;

    try copyDictMatch(state, saved_dict_pos, dict_type_len);
}

/// Handle literal line (15+ consecutive literal bytes)
fn handleLiteralLine(state: *DecompressState) !void {
    const literal_len = memUnpackPosLen(state.stream) + tinyuz.TUZ_K_MIN_LITERAL_LEN;

    try utilities.checkOutputBounds(state.cur_out_pos, literal_len, state.out_data.len);

    // Copy literal bytes from compressed stream
    var i: u32 = 0;
    while (i < literal_len) : (i += 1) {
        const b = memReadByte(state.stream) orelse return error.ReadCodeError;
        state.out_data[state.cur_out_pos] = b;
        state.cur_out_pos += 1;
    }

    state.is_have_data_back = true;
}

/// Handle control codes (CLIP_END, STREAM_END, etc)
fn handleControlCode(state: *DecompressState, ctrl_type: u32) !tinyuz.Result {
    utilities.resetControlState(&state.dict_pos_back, &state.stream.type_count);

    if (ctrl_type == tinyuz.TUZ_CTRL_TYPE_CLIP_END) {
        return tinyuz.Result.CLIP_END;
    }

    if (ctrl_type == tinyuz.TUZ_CTRL_TYPE_STREAM_END) {
        return tinyuz.Result.STREAM_END;
    }

    return tinyuz.Result.CTRL_TYPE_UNKNOWN_ERROR;
}

/// Handle single literal byte
fn handleLiteralByte(state: *DecompressState) !void {
    try utilities.checkOutputBounds(state.cur_out_pos, 1, state.out_data.len);

    const b = memReadByte(state.stream) orelse return error.ReadCodeError;

    state.out_data[state.cur_out_pos] = b;
    state.cur_out_pos += 1;
    state.is_have_data_back = true;
}

/// Decode dictionary position from stream
fn decodeDictPos(state: *DecompressState, saved_len: *u32) ?u32 {
    if (state.is_have_data_back and (memReadLowbits(state.stream, 1) & 1) != 0) {
        // Reuse previous position
        return state.dict_pos_back;
    }

    // Read new position
    const pos = memUnpackDictPos(state.stream) orelse return null;

    // Adjust length for large positions
    if (pos > tinyuz.TUZ_K_BIG_POS_FOR_LEN) {
        saved_len.* += 1;
    }

    return pos;
}

/// Decompress data from memory
///
/// Args:
///     in_code: Compressed input data
///     out_data: Output buffer
///
/// Returns:
///     Number of bytes decompressed
pub fn decompressMem(in_code: []const u8, out_data: []u8) !usize {
    if (in_code.len < tinyuz.TUZ_K_DICT_SIZE_SAVED_BYTES) {
        return error.ReadDictSizeError;
    }

    // Initialize stream
    var stream = MemStream{
        .in_code = in_code,
        .in_code_pos = tinyuz.TUZ_K_DICT_SIZE_SAVED_BYTES,
        .types = 0,
        .type_count = 0,
    };

    // Initialize state
    var state = DecompressState{
        .stream = &stream,
        .out_data = out_data,
        .cur_out_pos = 0,
        .dict_pos_back = 1,
        .is_have_data_back = false,
    };

    while (true) {
        // Read type bit
        const type_bit = memReadLowbits(&stream, 1) & 1;

        if (type_bit == tinyuz.TUZ_CODE_TYPE_DICT) {
            // Dictionary match or control
            var saved_len = memUnpackLen(&stream);
            const saved_dict_pos = decodeDictPos(&state, &saved_len) orelse return error.ReadCodeError;

            state.is_have_data_back = false;

            if (saved_dict_pos != 0) {
                // Dictionary match
                try handleDictMatch(&state, saved_len, saved_dict_pos);
            } else {
                // Control code
                if (saved_len == tinyuz.TUZ_CTRL_TYPE_LITERAL_LINE) {
                    try handleLiteralLine(&state);
                    continue;
                }

                const res = try handleControlCode(&state, saved_len);
                if (res == tinyuz.Result.STREAM_END) {
                    return state.cur_out_pos;
                }
                if (res == tinyuz.Result.CLIP_END) {
                    continue;
                }
                return error.CtrlTypeUnknownError;
            }
        } else {
            // Literal byte
            try handleLiteralByte(&state);
        }
    }

    // Should never reach here
    return error.CodeError;
}
