// DFCP1 is intentionally planner/decoder-only in Stage B1. Nothing in this
// file resolves a turf, spawns an atom, or mutates map state.

// Table-v1 semantic IDs are defined with the shared DFCP wire constants in
// code/__DEFINES/dfgen.dm. Their paths below are append-only mappings.

// Numeric coordinates are intentionally limited to values that are exactly
// representable by all supported current-map callers. Full i32 values must use
// canonical text and the pair representation below.
#define DFCP_SAFE_COORDINATE_NUMBER 1048576

/datum/df_chunk_i32
	/// Canonical signed decimal request text. Never reconstructed through a DM number.
	var/text
	/// Two little-endian 16-bit words holding the exact i32 bit pattern.
	var/low16
	var/high16
	/// Four little-endian numeric bytes, retained for header echo comparison.
	var/list/bytes

/datum/df_chunk_seed
	/// Canonical lower-case, fixed-width u64 text.
	var/hex
	/// Eight little-endian numeric bytes. No DM number ever contains this u64.
	var/list/wire_bytes

/datum/df_chunk_request
	var/protocol_version
	var/algorithm_version
	var/table_version
	var/profile_id
	var/sections
	var/datum/df_chunk_seed/seed
	var/datum/df_chunk_i32/chunk_x
	var/datum/df_chunk_i32/chunk_y
	var/datum/df_chunk_i32/chunk_z

/datum/df_chunk_cell
	var/terrain_id
	var/material_id
	var/hardness_id
	/// Resolved only through the append-only table-v1 mappings below.
	var/terrain_path
	var/material_path

/datum/df_chunk_decoration
	var/kind
	var/local_x
	var/local_y
	var/type_id
	var/arg0
	var/arg1
	/// Keep the deterministic u32 seed exact as two 16-bit words.
	var/seed_low16
	var/seed_high16
	/// Flora, fauna, and ore type paths are table-owned. Troll-rock has no type path.
	var/semantic_path

/datum/df_chunk_plan
	var/protocol_version
	var/algorithm_version
	var/table_version
	var/profile_id
	var/flags
	var/sections
	var/record_count
	var/payload_length
	var/crc_low16
	var/crc_high16
	var/datum/df_chunk_seed/seed
	var/datum/df_chunk_i32/chunk_x
	var/datum/df_chunk_i32/chunk_y
	var/datum/df_chunk_i32/chunk_z
	var/list/cells
	var/list/decorations

	/// Returns a halo-inclusive cell for local coordinates -1 through 32.
	proc/cell_at(local_x, local_y)
		if(!isnum(local_x) || !isnum(local_y) || local_x != round(local_x) || local_y != round(local_y))
			return null
		if(local_x < -DFCP_HALO_SIZE || local_x >= DFCP_CORE_SIZE + DFCP_HALO_SIZE || local_y < -DFCP_HALO_SIZE || local_y >= DFCP_CORE_SIZE + DFCP_HALO_SIZE)
			return null
		var/index = (local_y + DFCP_HALO_SIZE) * DFCP_EXTENDED_SIZE + local_x + DFCP_HALO_SIZE + 1
		return cells?[index]

/datum/df_chunk_decode_result
	var/datum/df_chunk_plan/plan
	var/error

	proc/succeeded()
		return !isnull(plan) && isnull(error)

/datum/df_chunk_byte_result
	var/list/bytes
	var/error

// Explicit table-v1 mappings. Do not move a path to native code and do not
// repurpose an existing key; IDs are protocol data, not local implementation.
/proc/df_chunk_table_v1_terrain_paths()
	var/static/list/paths = alist(
		DFCP_TERRAIN_WATER = /turf/open/water,
		DFCP_TERRAIN_DIRT = /turf/open/floor/dirt,
		DFCP_TERRAIN_ROCK_FLOOR = /turf/open/floor/rock,
		DFCP_TERRAIN_STONE_WALL = /turf/closed/mineral/stone,
		DFCP_TERRAIN_SAND_WALL = /turf/closed/mineral/sand
	)
	return paths

/proc/df_chunk_table_v1_material_paths()
	var/static/list/paths = alist(
		DFCP_MATERIAL_STONE = /datum/material/stone,
		DFCP_MATERIAL_SANDSTONE = /datum/material/sandstone
	)
	return paths

/proc/df_chunk_table_v1_flora_paths()
	var/static/list/paths = alist(
		DFCP_FLORA_TOWERCAP = /obj/structure/plant/tree/towercap,
		DFCP_FLORA_PLUMP_HELMET = /obj/structure/plant/garden/crop/plump_helmet,
		DFCP_FLORA_PIG_TAIL = /obj/structure/plant/garden/crop/pig_tail,
		DFCP_FLORA_CAVE_WHEAT = /obj/structure/plant/garden/crop/cave_wheat
	)
	return paths

/proc/df_chunk_table_v1_fauna_paths()
	var/static/list/paths = alist(
		DFCP_FAUNA_GIANT_SPIDER = /mob/living/simple_animal/hostile/giant_spider,
		DFCP_FAUNA_TROLL = /mob/living/simple_animal/hostile/troll
	)
	return paths

/proc/df_chunk_table_v1_ore_paths()
	var/static/list/paths = alist(
		DFCP_ORE_GOLD = /obj/item/stack/ore/smeltable/gold,
		DFCP_ORE_IRON = /obj/item/stack/ore/smeltable/iron,
		DFCP_ORE_DIAMOND = /obj/item/stack/ore/gem/diamond,
		DFCP_ORE_RUBY = /obj/item/stack/ore/gem/ruby,
		DFCP_ORE_SAPPHIRE = /obj/item/stack/ore/gem/sapphire,
		DFCP_ORE_COAL = /obj/item/stack/ore/coal,
		DFCP_ORE_COPPER = /obj/item/stack/ore/smeltable/copper,
		DFCP_ORE_CASSITERITE = /obj/item/stack/ore/smeltable/cassiterite,
		DFCP_ORE_ALUMINUM = /obj/item/stack/ore/smeltable/aluminum,
		DFCP_ORE_GALENA = /obj/item/stack/ore/smeltable/galena,
		DFCP_ORE_SILVER = /obj/item/stack/ore/smeltable/silver,
		DFCP_ORE_PLATINUM = /obj/item/stack/ore/smeltable/platinum,
		DFCP_ORE_ADAMANTINE = /obj/item/stack/ore/smeltable/adamantine
	)
	return paths

/proc/df_chunk_table_v1_valid_terrain(terrain_id)
	return !isnull(df_chunk_table_v1_terrain_paths()[terrain_id])

/proc/df_chunk_table_v1_valid_material(material_id)
	return material_id == DFCP_MATERIAL_NONE || !isnull(df_chunk_table_v1_material_paths()[material_id])

/proc/df_chunk_table_v1_valid_hardness(hardness_id)
	return hardness_id >= 0 && hardness_id <= 5

/proc/df_chunk_table_v1_material_path(material_id)
	if(material_id == DFCP_MATERIAL_NONE)
		return null
	return df_chunk_table_v1_material_paths()[material_id]

/proc/df_chunk_table_v1_valid_record(kind, type_id)
	switch(kind)
		if(DFCP_RECORD_FLORA)
			return !isnull(df_chunk_table_v1_flora_paths()[type_id])
		if(DFCP_RECORD_FAUNA)
			return !isnull(df_chunk_table_v1_fauna_paths()[type_id])
		if(DFCP_RECORD_ORE)
			return !isnull(df_chunk_table_v1_ore_paths()[type_id])
		if(DFCP_RECORD_TROLL_ROCK)
			return type_id == 0
	return FALSE

/proc/df_chunk_table_v1_record_path(kind, type_id)
	switch(kind)
		if(DFCP_RECORD_FLORA)
			return df_chunk_table_v1_flora_paths()[type_id]
		if(DFCP_RECORD_FAUNA)
			return df_chunk_table_v1_fauna_paths()[type_id]
		if(DFCP_RECORD_ORE)
			return df_chunk_table_v1_ore_paths()[type_id]
	return null

/// Validates table-v1 terrain/material/hardness combinations. Mineral hardness
/// is bound to the echoed cave profile, preventing a frame from silently
/// changing the future application hardness.
/proc/df_chunk_table_v1_valid_cell(terrain_id, material_id, hardness_id, profile_id)
	if(!df_chunk_table_v1_valid_terrain(terrain_id) || !df_chunk_table_v1_valid_material(material_id) || !df_chunk_table_v1_valid_hardness(hardness_id))
		return FALSE
	switch(terrain_id)
		if(DFCP_TERRAIN_WATER, DFCP_TERRAIN_DIRT)
			return material_id == DFCP_MATERIAL_NONE && hardness_id == 0
		if(DFCP_TERRAIN_ROCK_FLOOR)
			return (material_id == DFCP_MATERIAL_STONE || material_id == DFCP_MATERIAL_SANDSTONE) && hardness_id == profile_id
		if(DFCP_TERRAIN_STONE_WALL)
			return material_id == DFCP_MATERIAL_STONE && hardness_id == profile_id
		if(DFCP_TERRAIN_SAND_WALL)
			return material_id == DFCP_MATERIAL_SANDSTONE && hardness_id == profile_id
	return FALSE

/// Type-specific v1 decoration arguments. arg1 is a signed BYOND-decisecond
/// growthdelta adjustment: towercaps have base 800 ds and cave crops base 900.
/proc/df_chunk_table_v1_valid_record_arguments(kind, type_id, arg0, arg1)
	switch(kind)
		if(DFCP_RECORD_FLORA)
			if(type_id == DFCP_FLORA_TOWERCAP)
				return arg0 >= 1 && arg0 <= 7 && arg1 >= -100 && arg1 <= 600
			return arg0 >= 0 && arg0 <= 5 && arg1 >= -180 && arg1 <= 540
		if(DFCP_RECORD_FAUNA)
			return arg0 == 0 && arg1 == 0
		if(DFCP_RECORD_ORE)
			return arg0 >= 1 && arg0 <= 5 && arg1 == 0
		if(DFCP_RECORD_TROLL_ROCK)
			return type_id == 0 && arg0 == 0 && arg1 == 0
	return FALSE

/proc/df_chunk_valid_byte(value)
	return isnum(value) && value == round(value) && value >= 0 && value <= 255

/proc/df_chunk_u16_at(list/bytes, zero_offset)
	if(!islist(bytes) || !isnum(zero_offset) || zero_offset != round(zero_offset) || zero_offset < 0 || zero_offset + 2 > bytes.len)
		return null
	var/low_byte = bytes[zero_offset + 1]
	var/high_byte = bytes[zero_offset + 2]
	if(!df_chunk_valid_byte(low_byte) || !df_chunk_valid_byte(high_byte))
		return null
	return low_byte + high_byte * 256

/proc/df_chunk_pair_at(list/bytes, zero_offset)
	var/low16 = df_chunk_u16_at(bytes, zero_offset)
	var/high16 = df_chunk_u16_at(bytes, zero_offset + 2)
	if(isnull(low16) || isnull(high16))
		return null
	return list(low16, high16)

/proc/df_chunk_pair_equal(list/left, list/right)
	return islist(left) && islist(right) && left.len == 2 && right.len == 2 && left[1] == right[1] && left[2] == right[2]

/proc/df_chunk_pair_compare_unsigned(left_low16, left_high16, right_low16, right_high16)
	if(left_high16 < right_high16)
		return -1
	if(left_high16 > right_high16)
		return 1
	if(left_low16 < right_low16)
		return -1
	if(left_low16 > right_low16)
		return 1
	return 0

/proc/df_chunk_small_to_pair(value)
	if(!isnum(value) || value != round(value) || value < 0 || value > DFCP_MAX_FRAME_BYTES)
		return null
	var/low16 = value % 65536
	return list(low16, (value - low16) / 65536)

/proc/df_chunk_pair_bytes(low16, high16)
	if(!isnum(low16) || !isnum(high16) || low16 != round(low16) || high16 != round(high16) || low16 < 0 || low16 > 65535 || high16 < 0 || high16 > 65535)
		return null
	var/low_low = low16 & 255
	var/high_low = high16 & 255
	return list(low_low, low16 >> 8, high_low, high16 >> 8)

/proc/df_chunk_append_u16(list/bytes, value)
	if(!islist(bytes) || !isnum(value) || value != round(value) || value < 0 || value > 65535)
		return FALSE
	bytes += value & 255
	bytes += value >> 8
	return TRUE

/proc/df_chunk_append_pair(list/bytes, low16, high16)
	return df_chunk_append_u16(bytes, low16) && df_chunk_append_u16(bytes, high16)

/proc/df_chunk_write_u16(list/bytes, zero_offset, value)
	if(!islist(bytes) || !isnum(zero_offset) || zero_offset != round(zero_offset) || zero_offset < 0 || zero_offset + 2 > bytes.len || !isnum(value) || value != round(value) || value < 0 || value > 65535)
		return FALSE
	bytes[zero_offset + 1] = value & 255
	bytes[zero_offset + 2] = value >> 8
	return TRUE

/proc/df_chunk_i32_from_text(value)
	if(!istext(value) || !length(value))
		return null
	var/value_length = length(value)
	var/negative = FALSE
	var/start = 1
	if(text2ascii(value, 1) == 45) // -
		negative = TRUE
		start = 2
	if(start > value_length)
		return null
	if(value_length - start + 1 > 10)
		return null
	if(text2ascii(value, start) == 48 && start < value_length)
		return null

	var/magnitude_low16 = 0
	var/magnitude_high16 = 0
	for(var/position in start to value_length)
		var/character = text2ascii(value, position)
		if(character < 48 || character > 57)
			return null
		var/digit = character - 48
		// Both products are below 655,360, so every calculation remains exact
		// even on BYOND numeric implementations with limited integer precision.
		var/low_product = magnitude_low16 * 10 + digit
		var/new_low16 = low_product % 65536
		var/carry = (low_product - new_low16) / 65536
		var/high_product = magnitude_high16 * 10 + carry
		if(high_product > 65535)
			return null
		magnitude_low16 = new_low16
		magnitude_high16 = high_product

	var/datum/df_chunk_i32/coordinate = new
	coordinate.text = value
	if(!negative)
		if(magnitude_high16 >= 32768)
			return null
		coordinate.low16 = magnitude_low16
		coordinate.high16 = magnitude_high16
	else
		if((magnitude_low16 == 0 && magnitude_high16 == 0) || magnitude_high16 > 32768 || (magnitude_high16 == 32768 && magnitude_low16 > 0))
			return null
		if(magnitude_low16)
			coordinate.low16 = 65536 - magnitude_low16
			coordinate.high16 = 65535 - magnitude_high16
		else
			coordinate.low16 = 0
			coordinate.high16 = 65536 - magnitude_high16
	coordinate.bytes = df_chunk_pair_bytes(coordinate.low16, coordinate.high16)
	return coordinate

/// The only number-to-coordinate bridge. It deliberately does not claim to
/// support general i32 numbers; callers needing large logical worlds must keep
/// the canonical text returned by their own coordinate source.
/proc/df_chunk_i32_from_safe_number(value)
	if(!isnum(value) || value < -DFCP_SAFE_COORDINATE_NUMBER || value > DFCP_SAFE_COORDINATE_NUMBER || value != round(value))
		return null
	var/whole_value = round(value)
	return df_chunk_i32_from_text("[whole_value]")

/proc/df_chunk_hex_lower_value(character)
	if(character >= 48 && character <= 57)
		return character - 48
	if(character >= 97 && character <= 102)
		return character - 87
	return -1

/proc/df_chunk_seed_from_hex(seed_hex)
	if(!istext(seed_hex) || length(seed_hex) != 16)
		return null
	var/datum/df_chunk_seed/seed = new
	seed.hex = seed_hex
	seed.wire_bytes = list(0, 0, 0, 0, 0, 0, 0, 0)
	for(var/byte_index in 1 to 8)
		var/high_nibble = df_chunk_hex_lower_value(text2ascii(seed_hex, byte_index * 2 - 1))
		var/low_nibble = df_chunk_hex_lower_value(text2ascii(seed_hex, byte_index * 2))
		if(high_nibble < 0 || low_nibble < 0)
			return null
		// Request text is conventional big-endian hex; DFCP1 stores its u64 LE.
		seed.wire_bytes[9 - byte_index] = (high_nibble << 4) | low_nibble
	return seed

/proc/df_chunk_seed_matches_header(datum/df_chunk_seed/seed, list/bytes, zero_offset)
	if(!seed || !islist(seed.wire_bytes) || seed.wire_bytes.len != 8)
		return FALSE
	for(var/byte_index in 1 to 8)
		var/header_byte_index = zero_offset + byte_index
		if(header_byte_index > bytes.len || bytes[header_byte_index] != seed.wire_bytes[byte_index])
			return FALSE
	return TRUE

/proc/_df_chunk_set_request_error(list/error_out, code, token)
	if(islist(error_out))
		error_out["error"] = _df_chunk_error(code, token)

/// Parses exactly the native endpoint's nine wire arguments. Versions and
/// small IDs are compared as canonical strings; coordinates/seed are parsed
/// into exact byte-pair representations before any native call.
/proc/df_chunk_request_from_wire(protocol_version, algorithm_version, table_version, seed_hex, profile_id, chunk_x, chunk_y, chunk_z, sections, list/error_out)
	if("[protocol_version]" != "[DFCP_PROTOCOL_VERSION]")
		_df_chunk_set_request_error(error_out, 426, "unsupported_protocol")
		return null
	if("[algorithm_version]" != "[DFCP_ALGORITHM_VERSION]")
		_df_chunk_set_request_error(error_out, 426, "unsupported_algorithm")
		return null
	if("[table_version]" != "[DFCP_TABLE_VERSION]")
		_df_chunk_set_request_error(error_out, 426, "unsupported_table")
		return null

	var/parsed_profile
	switch("[profile_id]")
		if("1")
			parsed_profile = 1
		if("2")
			parsed_profile = 2
		if("3")
			parsed_profile = 3
		if("4")
			parsed_profile = 4
		if("5")
			parsed_profile = 5
	if(isnull(parsed_profile))
		_df_chunk_set_request_error(error_out, 400, "profile_id")
		return null

	var/parsed_sections
	switch("[sections]")
		if("1")
			parsed_sections = DFCP_SECTION_CELLS
		if("2")
			parsed_sections = DFCP_SECTION_DECORATIONS
		if("3")
			parsed_sections = DFCP_SECTION_BOTH
	if(isnull(parsed_sections))
		_df_chunk_set_request_error(error_out, 400, "sections")
		return null

	var/datum/df_chunk_seed/parsed_seed = df_chunk_seed_from_hex(seed_hex)
	if(!parsed_seed)
		_df_chunk_set_request_error(error_out, 400, "seed_hex")
		return null
	var/datum/df_chunk_i32/parsed_x = df_chunk_i32_from_text(chunk_x)
	var/datum/df_chunk_i32/parsed_y = df_chunk_i32_from_text(chunk_y)
	var/datum/df_chunk_i32/parsed_z = df_chunk_i32_from_text(chunk_z)
	if(!parsed_x || !parsed_y || !parsed_z)
		_df_chunk_set_request_error(error_out, 400, "chunk_coordinate")
		return null

	var/datum/df_chunk_request/request = new
	request.protocol_version = DFCP_PROTOCOL_VERSION
	request.algorithm_version = DFCP_ALGORITHM_VERSION
	request.table_version = DFCP_TABLE_VERSION
	request.profile_id = parsed_profile
	request.sections = parsed_sections
	request.seed = parsed_seed
	request.chunk_x = parsed_x
	request.chunk_y = parsed_y
	request.chunk_z = parsed_z
	return request

/proc/df_chunk_base64url_value(character)
	if(character >= 65 && character <= 90)
		return character - 65
	if(character >= 97 && character <= 122)
		return character - 71
	if(character >= 48 && character <= 57)
		return character + 4
	if(character == 45) // -
		return 62
	if(character == 95) // _
		return 63
	return -1

/// Strict, unpadded RFC 4648 Base64URL decoder. It intentionally returns a
/// numeric-byte list instead of a DM binary string, because embedded NUL bytes
/// are not safe to carry in Dream Maker text.
/proc/df_chunk_base64url_decode(value)
	var/datum/df_chunk_byte_result/result = new
	if(!istext(value) || !length(value) || length(value) > DFCP_MAX_FRAME_ASCII || findtext(value, "="))
		result.error = _df_chunk_error(422, "base64_bounds")
		return result
	var/value_length = length(value)
	if(value_length % 4 == 1)
		result.error = _df_chunk_error(422, "base64_decode")
		return result
	var/list/decoded = list()
	for(var/position in 1 to value_length step 4)
		var/remaining = min(4, value_length - position + 1)
		if(remaining == 1)
			result.error = _df_chunk_error(422, "base64_decode")
			return result
		var/a = df_chunk_base64url_value(text2ascii(value, position))
		var/b = df_chunk_base64url_value(text2ascii(value, position + 1))
		if(a < 0 || b < 0)
			result.error = _df_chunk_error(422, "base64_alphabet")
			return result
		if(remaining == 2 && (b & 15))
			result.error = _df_chunk_error(422, "base64_noncanonical")
			return result
		decoded += (a << 2) | (b >> 4)
		if(remaining >= 3)
			var/c = df_chunk_base64url_value(text2ascii(value, position + 2))
			if(c < 0)
				result.error = _df_chunk_error(422, "base64_alphabet")
				return result
			if(remaining == 3 && (c & 3))
				result.error = _df_chunk_error(422, "base64_noncanonical")
				return result
			decoded += ((b & 15) << 4) | (c >> 2)
			if(remaining == 4)
				var/d = df_chunk_base64url_value(text2ascii(value, position + 3))
				if(d < 0)
					result.error = _df_chunk_error(422, "base64_alphabet")
					return result
				decoded += ((c & 3) << 6) | d
	if(decoded.len > DFCP_MAX_FRAME_BYTES)
		result.error = _df_chunk_error(422, "base64_noncanonical")
		return result
	result.bytes = decoded
	return result

/// Numeric-byte encoder used only by tests/fixture tooling and never as a
/// transport for binary DM text.
/proc/df_chunk_base64url_encode_bytes(list/bytes)
	if(!islist(bytes) || bytes.len > DFCP_MAX_FRAME_BYTES)
		return null
	var/alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	var/list/output = list()
	var/position = 1
	while(position <= bytes.len)
		var/first = bytes[position]
		var/remaining = min(3, bytes.len - position + 1)
		var/second = remaining >= 2 ? bytes[position + 1] : 0
		var/third = remaining >= 3 ? bytes[position + 2] : 0
		if(!df_chunk_valid_byte(first) || !df_chunk_valid_byte(second) || !df_chunk_valid_byte(third))
			return null
		output += copytext(alphabet, (first >> 2) + 1, (first >> 2) + 2)
		output += copytext(alphabet, (((first & 3) << 4) | (second >> 4)) + 1, (((first & 3) << 4) | (second >> 4)) + 2)
		if(remaining >= 2)
			output += copytext(alphabet, (((second & 15) << 2) | (third >> 6)) + 1, (((second & 15) << 2) | (third >> 6)) + 2)
		if(remaining >= 3)
			output += copytext(alphabet, (third & 63) + 1, (third & 63) + 2)
		position += 3
	return output.Join("")

/// CRC-32/ISO-HDLC represented as two 16-bit halves. The table is generated
/// with pair shifts/XORs; no 32-bit DM numeric state is ever assembled.
/proc/df_chunk_crc32_table()
	var/static/list/table
	if(!isnull(table))
		return table
	table = list()
	for(var/index in 0 to 255)
		var/low16 = index
		var/high16 = 0
		for(var/round_index in 1 to 8)
			var/low_bit = low16 & 1
			var/new_low16 = (low16 >> 1) | ((high16 & 1) << 15)
			var/new_high16 = high16 >> 1
			if(low_bit)
				// Reflected 0xedb88320 as low/high 16-bit halves.
				new_low16 = new_low16 ^ 33568
				new_high16 = new_high16 ^ 60856
			low16 = new_low16
			high16 = new_high16
		table += list(list(low16, high16))
	return table

/proc/df_chunk_crc32_iso_hdlc(list/bytes, skip_start = 0, skip_end = -1)
	if(!islist(bytes))
		return null
	var/list/table = df_chunk_crc32_table()
	var/low16 = 65535
	var/high16 = 65535
	for(var/position in 1 to bytes.len)
		if(position >= skip_start && position <= skip_end)
			continue
		var/byte = bytes[position]
		if(!df_chunk_valid_byte(byte))
			return null
		var/table_index = (low16 ^ byte) & 255
		var/list/table_entry = table[table_index + 1]
		var/shifted_low16 = (low16 >> 8) | ((high16 & 255) << 8)
		var/shifted_high16 = high16 >> 8
		low16 = shifted_low16 ^ table_entry[1]
		high16 = shifted_high16 ^ table_entry[2]
	return list(low16 ^ 65535, high16 ^ 65535)

/// Test/fixture helper: replaces the stored little-endian CRC in a raw DFCP1
/// frame after a deliberate mutation. The CRC field itself is excluded.
/proc/df_chunk_frame_recompute_crc(list/bytes)
	if(!islist(bytes) || bytes.len < DFCP_HEADER_LENGTH)
		return FALSE
	var/list/crc = df_chunk_crc32_iso_hdlc(bytes, 45, 48)
	if(!crc)
		return FALSE
	return df_chunk_write_u16(bytes, 44, crc[1]) && df_chunk_write_u16(bytes, 46, crc[2])

/proc/_df_chunk_decode_failure(code, token)
	var/datum/df_chunk_decode_result/result = new
	result.error = _df_chunk_error(code, token)
	return result

/proc/df_chunk_compare_decoration_order(datum/df_chunk_decoration/left, datum/df_chunk_decoration/right)
	if(left.local_y != right.local_y)
		return left.local_y < right.local_y ? -1 : 1
	if(left.local_x != right.local_x)
		return left.local_x < right.local_x ? -1 : 1
	if(left.kind != right.kind)
		return left.kind < right.kind ? -1 : 1
	if(left.type_id != right.type_id)
		return left.type_id < right.type_id ? -1 : 1
	if(left.arg0 != right.arg0)
		return left.arg0 < right.arg0 ? -1 : 1
	if(left.arg1 != right.arg1)
		return left.arg1 < right.arg1 ? -1 : 1
	return df_chunk_pair_compare_unsigned(left.seed_low16, left.seed_high16, right.seed_low16, right.seed_high16)

/proc/df_chunk_seed_copy(datum/df_chunk_seed/seed)
	if(!seed)
		return null
	return df_chunk_seed_from_hex(seed.hex)

/proc/df_chunk_i32_copy(datum/df_chunk_i32/coordinate)
	if(!coordinate)
		return null
	return df_chunk_i32_from_text(coordinate.text)

/// Strictly decodes a numeric-byte DFCP1 frame and validates it against an
/// already canonical request. No /datum/df_chunk_plan is returned until every
/// header, checksum, semantic, ordering, and echo check has completed.
/proc/df_chunk_decode_frame(list/bytes, datum/df_chunk_request/request)
	if(!istype(request, /datum/df_chunk_request) || !istype(request.seed, /datum/df_chunk_seed) || !istype(request.chunk_x, /datum/df_chunk_i32) || !istype(request.chunk_y, /datum/df_chunk_i32) || !istype(request.chunk_z, /datum/df_chunk_i32))
		return _df_chunk_decode_failure(400, "request")
	// The decoder accepts only a request that can be reconstructed through the
	// same canonical parser used by the wrappers. This prevents a hand-built DM
	// datum from weakening exact seed/coordinate echo validation.
	var/list/request_errors = list()
	var/datum/df_chunk_request/canonical_request = df_chunk_request_from_wire(request.protocol_version, request.algorithm_version, request.table_version, request.seed.hex, request.profile_id, request.chunk_x.text, request.chunk_y.text, request.chunk_z.text, request.sections, request_errors)
	if(!canonical_request)
		return _df_chunk_decode_failure(400, "request")
	request = canonical_request
	if(!islist(bytes) || bytes.len < DFCP_HEADER_LENGTH || bytes.len > DFCP_MAX_FRAME_BYTES)
		return _df_chunk_decode_failure(422, "frame_bounds")
	for(var/header_position in 1 to DFCP_HEADER_LENGTH)
		if(!df_chunk_valid_byte(bytes[header_position]))
			return _df_chunk_decode_failure(422, "header_bytes")
	if(bytes[1] != 68 || bytes[2] != 70 || bytes[3] != 67 || bytes[4] != 80) // DFCP
		return _df_chunk_decode_failure(422, "frame_magic")
	if(bytes[5] != DFCP_PROTOCOL_VERSION || bytes[6] != DFCP_ALGORITHM_VERSION)
		return _df_chunk_decode_failure(426, "unsupported_version")
	if(bytes[7] != DFCP_HEADER_LENGTH || bytes[9] != DFCP_CORE_SIZE || bytes[10] != DFCP_HALO_SIZE || bytes[11] != DFCP_CELL_STRIDE || bytes[12] != DFCP_RECORD_STRIDE || bytes[14] != 0)
		return _df_chunk_decode_failure(422, "header_layout")

	var/flags = bytes[8]
	if(flags != DFCP_SECTION_CELLS && flags != DFCP_SECTION_DECORATIONS && flags != DFCP_SECTION_BOTH)
		return _df_chunk_decode_failure(422, "header_flags")
	var/profile_id = bytes[13]
	if(profile_id < 1 || profile_id > 5)
		return _df_chunk_decode_failure(422, "profile_id")
	var/record_count = df_chunk_u16_at(bytes, 14)
	if(isnull(record_count))
		return _df_chunk_decode_failure(422, "header_bytes")
	if(record_count > DFCP_MAX_RECORDS)
		return _df_chunk_decode_failure(413, "record_cap")

	var/list/chunk_x = df_chunk_pair_at(bytes, 16)
	var/list/chunk_y = df_chunk_pair_at(bytes, 20)
	var/list/chunk_z = df_chunk_pair_at(bytes, 24)
	var/list/table_version = df_chunk_pair_at(bytes, 36)
	var/list/payload_length = df_chunk_pair_at(bytes, 40)
	var/list/stored_crc = df_chunk_pair_at(bytes, 44)
	if(!chunk_x || !chunk_y || !chunk_z || !table_version || !payload_length || !stored_crc)
		return _df_chunk_decode_failure(422, "header_bytes")
	if(table_version[1] != DFCP_TABLE_VERSION || table_version[2] != 0)
		return _df_chunk_decode_failure(426, "unsupported_table")

	var/includes_cells = flags == DFCP_SECTION_CELLS || flags == DFCP_SECTION_BOTH
	var/includes_records = flags == DFCP_SECTION_DECORATIONS || flags == DFCP_SECTION_BOTH
	if(!includes_records && record_count)
		return _df_chunk_decode_failure(422, "record_section_mismatch")
	var/expected_payload_length = record_count * DFCP_RECORD_STRIDE
	if(includes_cells)
		expected_payload_length += DFCP_CELL_COUNT * DFCP_CELL_STRIDE
	var/list/expected_payload_pair = df_chunk_small_to_pair(expected_payload_length)
	if(!df_chunk_pair_equal(payload_length, expected_payload_pair) || bytes.len != DFCP_HEADER_LENGTH + expected_payload_length)
		return _df_chunk_decode_failure(422, "payload_length")

	// Validate stored CRC as two little-endian halves, never a potentially lossy
	// 32-bit number. Header bytes 44..47 (DM positions 45..48) are excluded.
	var/list/calculated_crc = df_chunk_crc32_iso_hdlc(bytes, 45, 48)
	if(!calculated_crc || !df_chunk_pair_equal(stored_crc, calculated_crc))
		return _df_chunk_decode_failure(422, "crc32")

	if(request.protocol_version != bytes[5] || request.algorithm_version != bytes[6] || request.table_version != DFCP_TABLE_VERSION || request.profile_id != profile_id || request.sections != flags || !df_chunk_pair_equal(chunk_x, list(request.chunk_x.low16, request.chunk_x.high16)) || !df_chunk_pair_equal(chunk_y, list(request.chunk_y.low16, request.chunk_y.high16)) || !df_chunk_pair_equal(chunk_z, list(request.chunk_z.low16, request.chunk_z.high16)) || !df_chunk_seed_matches_header(request.seed, bytes, 28))
		return _df_chunk_decode_failure(422, "request_echo_mismatch")

	var/list/cells = list()
	var/list/decorations = list()
	var/payload_position = DFCP_HEADER_LENGTH + 1
	if(includes_cells)
		for(var/cell_index in 1 to DFCP_CELL_COUNT)
			var/terrain_id = bytes[payload_position]
			var/material_id = bytes[payload_position + 1]
			var/hardness_id = bytes[payload_position + 2]
			if(!df_chunk_table_v1_valid_cell(terrain_id, material_id, hardness_id, profile_id))
				if(!df_chunk_table_v1_valid_terrain(terrain_id) || !df_chunk_table_v1_valid_material(material_id) || !df_chunk_table_v1_valid_hardness(hardness_id))
					return _df_chunk_decode_failure(422, "unknown_cell_id")
				if((terrain_id == DFCP_TERRAIN_ROCK_FLOOR || terrain_id == DFCP_TERRAIN_STONE_WALL || terrain_id == DFCP_TERRAIN_SAND_WALL) && hardness_id != profile_id)
					return _df_chunk_decode_failure(422, "cell_hardness_profile")
				return _df_chunk_decode_failure(422, "cell_combination")
			var/datum/df_chunk_cell/cell = new
			cell.terrain_id = terrain_id
			cell.material_id = material_id
			cell.hardness_id = hardness_id
			cell.terrain_path = df_chunk_table_v1_terrain_paths()[terrain_id]
			cell.material_path = df_chunk_table_v1_material_path(material_id)
			cells += cell
			payload_position += DFCP_CELL_STRIDE

	var/datum/df_chunk_decoration/previous_record
	for(var/record_index in 1 to record_count)
		var/kind = bytes[payload_position]
		var/local_x = bytes[payload_position + 1]
		var/local_y = bytes[payload_position + 2]
		var/type_id = bytes[payload_position + 3]
		var/arg0 = df_chunk_u16_at(bytes, payload_position + 3)
		var/arg1_raw = df_chunk_u16_at(bytes, payload_position + 5)
		var/list/record_seed = df_chunk_pair_at(bytes, payload_position + 7)
		if(isnull(arg0) || isnull(arg1_raw) || !record_seed)
			return _df_chunk_decode_failure(422, "record_bytes")
		var/arg1 = arg1_raw >= 32768 ? arg1_raw - 65536 : arg1_raw
		if(local_x >= DFCP_CORE_SIZE || local_y >= DFCP_CORE_SIZE)
			return _df_chunk_decode_failure(422, "record_coordinate")
		if(!df_chunk_table_v1_valid_record(kind, type_id))
			return _df_chunk_decode_failure(422, "unknown_record_id")
		if(!df_chunk_table_v1_valid_record_arguments(kind, type_id, arg0, arg1))
			switch(kind)
				if(DFCP_RECORD_FLORA)
					return _df_chunk_decode_failure(422, "flora_arguments")
				if(DFCP_RECORD_FAUNA)
					return _df_chunk_decode_failure(422, "fauna_arguments")
				if(DFCP_RECORD_ORE)
					return _df_chunk_decode_failure(422, "ore_arguments")
				if(DFCP_RECORD_TROLL_ROCK)
					return _df_chunk_decode_failure(422, "troll_arguments")
			return _df_chunk_decode_failure(422, "record_arguments")
		var/datum/df_chunk_decoration/record = new
		record.kind = kind
		record.local_x = local_x
		record.local_y = local_y
		record.type_id = type_id
		record.arg0 = arg0
		record.arg1 = arg1
		record.seed_low16 = record_seed[1]
		record.seed_high16 = record_seed[2]
		record.semantic_path = df_chunk_table_v1_record_path(kind, type_id)
		if(previous_record && df_chunk_compare_decoration_order(previous_record, record) >= 0)
			return _df_chunk_decode_failure(422, "record_order")
		decorations += record
		previous_record = record
		payload_position += DFCP_RECORD_STRIDE
	if(payload_position != bytes.len + 1)
		return _df_chunk_decode_failure(422, "payload_length")

	var/datum/df_chunk_plan/plan = new
	plan.protocol_version = bytes[5]
	plan.algorithm_version = bytes[6]
	plan.table_version = DFCP_TABLE_VERSION
	plan.profile_id = profile_id
	plan.flags = flags
	plan.sections = flags
	plan.record_count = record_count
	plan.payload_length = expected_payload_length
	plan.crc_low16 = stored_crc[1]
	plan.crc_high16 = stored_crc[2]
	plan.seed = df_chunk_seed_copy(request.seed)
	plan.chunk_x = df_chunk_i32_copy(request.chunk_x)
	plan.chunk_y = df_chunk_i32_copy(request.chunk_y)
	plan.chunk_z = df_chunk_i32_copy(request.chunk_z)
	plan.cells = cells
	plan.decorations = decorations
	var/datum/df_chunk_decode_result/result = new
	result.plan = plan
	return result

/// Strictly decodes a native synchronous response. Pass the same canonical
/// request datum that was sent; a frame without an exact echo is rejected.
/proc/df_chunk_decode_plan(value, datum/df_chunk_request/request)
	if(!_df_chunk_has_prefix(value, DFCP_PLAN_PREFIX))
		return _df_chunk_decode_failure(422, "plan_prefix")
	var/encoded = copytext(value, length(DFCP_PLAN_PREFIX) + 1)
	var/datum/df_chunk_byte_result/decoded = df_chunk_base64url_decode(encoded)
	if(decoded.error)
		var/datum/df_chunk_decode_result/result = new
		result.error = decoded.error
		return result
	return df_chunk_decode_frame(decoded.bytes, request)

// Short alias for callers that only have a DFCP1 response string.
/proc/df_chunk_decode(value, datum/df_chunk_request/request)
	return df_chunk_decode_plan(value, request)
