// tinyuz.odin
// Native Odin implementation of TinyUZ compression
//
// Based on the TinyUZ algorithm by HouSisong
// License: MIT License (c) 2012-2025 HouSisong
//
// Optimized for small repetitive datasets like RGB LED frames,
// sensor data, and embedded systems.
//
// Public API:
//   - compress_mem: Compress data using TinyUZ algorithm
//   - decompress_mem: Decompress TinyUZ-compressed data
//   - read_dict_size: Read dictionary size from compressed data header

package tinyuz

// Constants from tuz_types_private.h
TUZ_K_MAX_TYPE_BIT_COUNT :: 8
TUZ_K_MIN_DICT_MATCH_LEN :: 2
TUZ_K_MIN_LITERAL_LEN :: 15
TUZ_K_BIG_POS_FOR_LEN :: ((1<<11)+(1<<9)+(1<<7)-1)

// Control types
TUZ_CODE_TYPE_DICT :: 0
TUZ_CODE_TYPE_DATA :: 1
TUZ_CTRL_TYPE_LITERAL_LINE :: 1
TUZ_CTRL_TYPE_CLIP_END :: 2
TUZ_CTRL_TYPE_STREAM_END :: 3

// Dictionary size limits
TUZ_K_MAX_DICT_SIZE :: (1 << 24) - 1  // 16MB max
TUZ_K_MIN_DICT_SIZE :: 1
TUZ_K_DICT_SIZE_SAVED_BYTES :: 4  // Use 4 bytes for dict size

// Result codes for compression/decompression operations
Result :: enum {
	OK = 0,
	STREAM_END = 3,           // Control code 3 - successful decompression
	LITERAL_LINE = 1,         // Control code 1
	CLIP_END = 2,             // Control code 2
	CTRL_TYPE_UNKNOWN_ERROR = 10,
	CTRL_TYPE_STREAM_END_ERROR,
	READ_CODE_ERROR = 20,
	READ_DICT_SIZE_ERROR,
	CACHE_SIZE_ERROR,
	DICT_POS_ERROR,
	OUT_SIZE_OR_CODE_ERROR,
	CODE_ERROR,
}

