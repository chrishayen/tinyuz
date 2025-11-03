// compress.zig
// TinyUZ compression implementation
//
// Implements LZ77 sliding window compression with bit-level encoding
// optimized for small repetitive datasets.

const std = @import("std");
const tinyuz = @import("tinyuz.zig");
const utilities = @import("utilities.zig");

// Encoder configuration
pub const CompressProps = struct {
    dict_size: usize,
    max_save_length: usize,
    is_need_literal_line: bool,
};

// Default compression properties
pub const DEFAULT_COMPRESS_PROPS = CompressProps{
    .dict_size = 64 * 1024 - 1,
    .max_save_length = 64 * 1024 - 1,
    .is_need_literal_line = true,
};

// Internal encoder state
const TuzEncoder = struct {
    code: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    is_need_literal_line: bool,
    types_index: usize,
    type_count: usize,
    dict_pos_back: usize,
    dict_size_max: usize,
    is_have_data_back: bool,
    props: CompressProps,

    fn init(props: CompressProps, allocator: std.mem.Allocator) TuzEncoder {
        return TuzEncoder{
            .code = .{},
            .allocator = allocator,
            .is_need_literal_line = props.is_need_literal_line,
            .types_index = 0,
            .type_count = 0,
            .dict_pos_back = 1,
            .dict_size_max = tinyuz.TUZ_K_MIN_DICT_SIZE,
            .is_have_data_back = false,
            .props = props,
        };
    }

    fn deinit(self: *TuzEncoder) void {
        self.code.deinit(self.allocator);
    }
};

// Variable-length encoding pack bits
const DICT_LEN_PACK_BIT = 1;
const DICT_POS_LEN_PACK_BIT = 2;

/// Output a single type bit
fn outType(encoder: *TuzEncoder, bit_value: u8) !void {
    if (encoder.type_count == 0) {
        encoder.types_index = encoder.code.items.len;
        try encoder.code.append(encoder.allocator, 0);
    }

    encoder.code.items[encoder.types_index] |= bit_value << @intCast(encoder.type_count);
    encoder.type_count += 1;

    if (encoder.type_count == tinyuz.TUZ_K_MAX_TYPE_BIT_COUNT) {
        encoder.type_count = 0;
    }
}

/// Get output count for variable-length encoding
fn getOutCount(v: usize, pack_bit: usize, dec: ?*usize) usize {
    var count: usize = 1;
    const _v = v;
    var remaining = v;

    while (true) {
        const m: usize = @as(usize, 1) << @intCast(count * pack_bit);
        if (remaining < m) break;
        remaining -= m;
        count += 1;
    }

    if (dec) |d| {
        d.* = _v - remaining;
    }
    return count;
}

/// Output variable-length encoded integer
fn outLen(encoder: *TuzEncoder, v: usize, pack_bit: usize) !void {
    var dec: usize = 0;
    const c = getOutCount(v, pack_bit, &dec);
    const remaining = v - dec;

    var i: isize = @intCast(c - 1);
    while (i >= 0) : (i -= 1) {
        const ui: usize = @intCast(i);
        var bit_idx: usize = 0;
        while (bit_idx < pack_bit) : (bit_idx += 1) {
            const shift: u6 = @intCast(ui * pack_bit + bit_idx);
            const bit: u8 = @intCast((remaining >> shift) & 1);
            try outType(encoder, bit);
        }
        try outType(encoder, if (i > 0) 1 else 0);
    }
}

/// Output dictionary size header (4 bytes little-endian)
fn outDictSize(encoder: *TuzEncoder, dict_size: usize) !void {
    try utilities.writeU32Le(&encoder.code, @intCast(dict_size), encoder.allocator);
}

/// Output literal data
fn outData(encoder: *TuzEncoder, data: []const u8) !void {
    const data_len = data.len;

    if (encoder.is_need_literal_line and data_len >= tinyuz.TUZ_K_MIN_LITERAL_LEN) {
        try outCtrl(encoder, tinyuz.TUZ_CTRL_TYPE_LITERAL_LINE);
        try outLen(encoder, data_len - tinyuz.TUZ_K_MIN_LITERAL_LEN, DICT_POS_LEN_PACK_BIT);
        for (data) |b| {
            try encoder.code.append(encoder.allocator, b);
        }
    } else {
        for (data) |b| {
            try outType(encoder, tinyuz.TUZ_CODE_TYPE_DATA);
            try encoder.code.append(encoder.allocator, b);
        }
    }

    encoder.is_have_data_back = true;
}

/// Output dictionary position
fn outDictPos(encoder: *TuzEncoder, pos: usize) !void {
    var mut_pos = pos;
    const is_out_len = mut_pos >= utilities.DICT_POS_THRESHOLD;
    if (is_out_len) {
        mut_pos -= utilities.DICT_POS_THRESHOLD;
    }

    var low_byte: u8 = @intCast(mut_pos & (utilities.DICT_POS_THRESHOLD - 1));
    if (is_out_len) {
        low_byte |= @intCast(utilities.DICT_POS_THRESHOLD);
    }
    try encoder.code.append(encoder.allocator, low_byte);

    if (is_out_len) {
        try outLen(encoder, mut_pos >> 7, DICT_POS_LEN_PACK_BIT);
    }
}

/// Output dictionary match
fn outDict(encoder: *TuzEncoder, match_len: usize, dict_pos: usize) !void {
    try outType(encoder, tinyuz.TUZ_CODE_TYPE_DICT);

    const saved_dict_pos = dict_pos + 1;
    if (saved_dict_pos > encoder.dict_size_max) {
        encoder.dict_size_max = saved_dict_pos;
    }

    const is_same_pos = encoder.dict_pos_back == saved_dict_pos;
    const is_saved_same_pos = is_same_pos and encoder.is_have_data_back;

    var len_val = match_len - tinyuz.TUZ_K_MIN_DICT_MATCH_LEN;
    if (!is_saved_same_pos and saved_dict_pos > tinyuz.TUZ_K_BIG_POS_FOR_LEN) {
        if (len_val > 0) {
            len_val -= 1;
        }
    }

    try outLen(encoder, len_val, DICT_LEN_PACK_BIT);

    if (encoder.is_have_data_back) {
        try outType(encoder, if (is_saved_same_pos) 1 else 0);
    }
    if (!is_saved_same_pos) {
        try outDictPos(encoder, saved_dict_pos);
    }

    encoder.is_have_data_back = false;
    encoder.dict_pos_back = saved_dict_pos;
}

/// Output control code
fn outCtrl(encoder: *TuzEncoder, ctrl: u32) !void {
    try outType(encoder, tinyuz.TUZ_CODE_TYPE_DICT);
    try outLen(encoder, ctrl, DICT_LEN_PACK_BIT);
    if (encoder.is_have_data_back) {
        try outType(encoder, 0);
    }
    try outDictPos(encoder, 0);
}

/// End types byte
fn outCtrlTypesEnd(encoder: *TuzEncoder) void {
    encoder.type_count = 0;
    encoder.dict_pos_back = 1;
    encoder.is_have_data_back = false;
}

/// Output stream end marker
fn outCtrlStreamEnd(encoder: *TuzEncoder) !void {
    try outCtrl(encoder, tinyuz.TUZ_CTRL_TYPE_STREAM_END);
    outCtrlTypesEnd(encoder);
}

/// Count matching bytes at two positions
fn countMatchLength(data: []const u8, pos1: usize, pos2: usize, max_len: usize) usize {
    var match_count: usize = 0;
    while (match_count < max_len and pos2 + match_count < data.len) {
        if (data[pos1 + match_count] != data[pos2 + match_count]) {
            break;
        }
        match_count += 1;
    }
    return match_count;
}

/// Simple LZ77 match finder (sliding window)
fn findMatch(data: []const u8, pos: usize, dict_size: usize, max_len: usize) struct { match_pos: usize, match_len: usize } {
    var best_len: usize = 0;
    var best_pos: usize = 0;

    const search_start = if (pos > dict_size) pos - dict_size else 0;

    var search_pos = pos;
    while (search_pos > search_start) {
        search_pos -= 1;
        const match_count = countMatchLength(data, search_pos, pos, max_len);

        if (match_count > best_len) {
            best_len = match_count;
            best_pos = pos - search_pos - 1;
        }
    }

    return .{ .match_pos = best_pos, .match_len = best_len };
}

/// Check if match is worth encoding
fn isMatchWorthwhile(match_len: usize) bool {
    return match_len >= tinyuz.TUZ_K_MIN_DICT_MATCH_LEN;
}

/// Flush pending literal data
fn flushLiterals(encoder: *TuzEncoder, data: []const u8, start: usize, end: usize) !void {
    if (end > start) {
        try outData(encoder, data[start..end]);
    }
}

/// Process match found during compression
fn processMatch(
    encoder: *TuzEncoder,
    in_data: []const u8,
    literal_start: *usize,
    pos: *usize,
    match_pos: usize,
    match_len: usize,
) !void {
    // Flush any pending literals
    try flushLiterals(encoder, in_data, literal_start.*, pos.*);

    // Output the dictionary match
    try outDict(encoder, match_len, match_pos);

    // Advance position
    pos.* += match_len;
    literal_start.* = pos.*;
}

/// Finalize compression and copy to output buffer
fn finalizeCompression(encoder: *TuzEncoder, out_code: []u8) !usize {
    if (encoder.code.items.len > out_code.len) {
        return error.OutSizeOrCodeError;
    }

    @memcpy(out_code[0..encoder.code.items.len], encoder.code.items);
    return encoder.code.items.len;
}

/// Compress data to TUZ format
pub fn compressMem(
    in_data: []const u8,
    out_code: []u8,
    dict_size: u32,
    allocator: std.mem.Allocator,
) !usize {
    const props = CompressProps{
        .dict_size = dict_size,
        .max_save_length = 64 * 1024 - 1,
        .is_need_literal_line = true,
    };

    var encoder = TuzEncoder.init(props, allocator);
    defer encoder.deinit();

    try outDictSize(&encoder, props.dict_size);

    var pos: usize = 0;
    var literal_start: usize = 0;

    // Main compression loop
    while (pos < in_data.len) {
        const match = findMatch(in_data, pos, props.dict_size, props.max_save_length);

        if (isMatchWorthwhile(match.match_len)) {
            try processMatch(&encoder, in_data, &literal_start, &pos, match.match_pos, match.match_len);
        } else {
            pos += 1;
        }
    }

    // Flush remaining literals
    try flushLiterals(&encoder, in_data, literal_start, in_data.len);

    // End the stream
    try outCtrlStreamEnd(&encoder);

    // Copy to output buffer
    return finalizeCompression(&encoder, out_code);
}
