// DFCP1 decoder/ABI tests. Fixtures are numeric bytes, never binary DM text.

/proc/df_chunk_protocol_test_request(sections = DFCP_SECTION_CELLS)
	var/list/errors = list()
	return df_chunk_request_from_wire("1", "1", "1", "0123456789abcdef", "3", "-17", "42", "-3", "[sections]", errors)

/proc/df_chunk_protocol_test_header(datum/df_chunk_request/request, flags, record_count, payload_length)
	var/list/frame = list(68, 70, 67, 80) // DFCP
	frame += DFCP_PROTOCOL_VERSION
	frame += DFCP_ALGORITHM_VERSION
	frame += DFCP_HEADER_LENGTH
	frame += flags
	frame += DFCP_CORE_SIZE
	frame += DFCP_HALO_SIZE
	frame += DFCP_CELL_STRIDE
	frame += DFCP_RECORD_STRIDE
	frame += request.profile_id
	frame += 0
	if(!df_chunk_append_u16(frame, record_count))
		return null
	if(!df_chunk_append_pair(frame, request.chunk_x.low16, request.chunk_x.high16) || !df_chunk_append_pair(frame, request.chunk_y.low16, request.chunk_y.high16) || !df_chunk_append_pair(frame, request.chunk_z.low16, request.chunk_z.high16))
		return null
	for(var/byte in request.seed.wire_bytes)
		frame += byte
	if(!df_chunk_append_pair(frame, DFCP_TABLE_VERSION, 0))
		return null
	var/list/payload_pair = df_chunk_small_to_pair(payload_length)
	if(!payload_pair || !df_chunk_append_pair(frame, payload_pair[1], payload_pair[2]))
		return null
	frame += list(0, 0, 0, 0)
	return frame

/proc/df_chunk_protocol_test_append_record(list/frame, kind, local_x, local_y, type_id, arg0, arg1, seed_low16, seed_high16)
	if(!islist(frame) || !df_chunk_valid_byte(kind) || !df_chunk_valid_byte(local_x) || !df_chunk_valid_byte(local_y) || !df_chunk_valid_byte(type_id) || arg1 < -32768 || arg1 > 32767)
		return FALSE
	frame += kind
	frame += local_x
	frame += local_y
	frame += type_id
	if(!df_chunk_append_u16(frame, arg0) || !df_chunk_append_u16(frame, arg1 < 0 ? 65536 + arg1 : arg1) || !df_chunk_append_pair(frame, seed_low16, seed_high16))
		return FALSE
	return TRUE

/proc/df_chunk_protocol_test_cells_frame(datum/df_chunk_request/request)
	var/payload_length = DFCP_CELL_COUNT * DFCP_CELL_STRIDE
	var/list/frame = df_chunk_protocol_test_header(request, DFCP_SECTION_CELLS, 0, payload_length)
	if(!frame)
		return null
	for(var/cell_index in 1 to DFCP_CELL_COUNT)
		frame += DFCP_TERRAIN_STONE_WALL
		frame += DFCP_MATERIAL_STONE
		frame += request.profile_id
	if(!df_chunk_frame_recompute_crc(frame))
		return null
	return frame

/proc/df_chunk_protocol_test_records_frame(datum/df_chunk_request/request)
	var/list/frame = df_chunk_protocol_test_header(request, DFCP_SECTION_DECORATIONS, 2, 2 * DFCP_RECORD_STRIDE)
	if(!frame)
		return null
	// Same y, increasing x: strict canonical order. Crop values use the v1
	// type-specific range instead of the old generic flora range.
	if(!df_chunk_protocol_test_append_record(frame, DFCP_RECORD_FLORA, 2, 1, DFCP_FLORA_PLUMP_HELMET, 3, -120, 1, 0) || !df_chunk_protocol_test_append_record(frame, DFCP_RECORD_ORE, 3, 1, DFCP_ORE_GOLD, 2, 0, 2, 0))
		return null
	if(!df_chunk_frame_recompute_crc(frame))
		return null
	return frame

/// A maximum-size valid frame exercises the decoder's bounded representation:
/// 1156 cells plus 4096 canonical troll-rock records is 70,230 ASCII bytes
/// with the DFCP1 prefix, below 71 KiB.
/proc/df_chunk_protocol_test_large_frame(datum/df_chunk_request/request)
	var/record_count = DFCP_MAX_RECORDS
	var/payload_length = DFCP_CELL_COUNT * DFCP_CELL_STRIDE + record_count * DFCP_RECORD_STRIDE
	var/list/frame = df_chunk_protocol_test_header(request, DFCP_SECTION_BOTH, record_count, payload_length)
	if(!frame)
		return null
	for(var/cell_index in 1 to DFCP_CELL_COUNT)
		frame += DFCP_TERRAIN_STONE_WALL
		frame += DFCP_MATERIAL_STONE
		frame += request.profile_id
	for(var/local_y in 0 to 31)
		for(var/local_x in 0 to 31)
			for(var/seed_low16 in 0 to 3)
				if(!df_chunk_protocol_test_append_record(frame, DFCP_RECORD_TROLL_ROCK, local_x, local_y, 0, 0, 0, seed_low16, 0))
					return null
	if(!df_chunk_frame_recompute_crc(frame))
		return null
	return frame

/proc/df_chunk_protocol_test_decode(list/frame, datum/df_chunk_request/request)
	var/encoded = df_chunk_base64url_encode_bytes(frame)
	if(!encoded)
		return null
	return df_chunk_decode_plan("[DFCP_PLAN_PREFIX][encoded]", request)

/datum/unit_test/df_chunk_protocol
	var/list/chunk_jobs = list()

/datum/unit_test/df_chunk_protocol/Destroy()
	// The native registry retains completed jobs too. This teardown handles
	// every early assertion return in Run().
	for(var/job_id in chunk_jobs)
		df_chunk_forget(job_id)
	chunk_jobs.Cut()
	return ..()

/datum/unit_test/df_chunk_protocol/Run()
	var/datum/df_chunk_request/cells_request = df_chunk_protocol_test_request(DFCP_SECTION_CELLS)
	TEST_ASSERT(cells_request, "fixture request must be canonical")
	var/list/cells_frame = df_chunk_protocol_test_cells_frame(cells_request)
	TEST_ASSERT(cells_frame, "cells fixture must build")
	var/datum/df_chunk_decode_result/cells_result = df_chunk_protocol_test_decode(cells_frame, cells_request)
	TEST_ASSERT(cells_result?.succeeded(), "valid cells fixture failed: [cells_result?.error]")
	TEST_ASSERT_EQUAL(cells_result.plan.cells.len, DFCP_CELL_COUNT, "cell count")
	TEST_ASSERT_EQUAL(cells_result.plan.decorations.len, 0, "cells-only decoration count")
	TEST_ASSERT_EQUAL(cells_result.plan.seed.hex, "0123456789abcdef", "exact u64 seed text")
	TEST_ASSERT_EQUAL(cells_result.plan.chunk_x.text, "-17", "negative coordinate text")
	TEST_ASSERT_EQUAL(cells_result.plan.chunk_x.low16, 65519, "negative coordinate low word")
	TEST_ASSERT_EQUAL(cells_result.plan.chunk_x.high16, 65535, "negative coordinate high word")
	TEST_ASSERT_EQUAL(cells_result.plan.seed.wire_bytes[1], 239, "u64 seed little-endian first byte")
	TEST_ASSERT_EQUAL(cells_result.plan.seed.wire_bytes[8], 1, "u64 seed little-endian last byte")
	var/datum/df_chunk_i32/i32_minimum = df_chunk_i32_from_text("-2147483648")
	var/datum/df_chunk_i32/i32_maximum = df_chunk_i32_from_text("2147483647")
	TEST_ASSERT(i32_minimum && i32_maximum, "i32 extrema parse without DM numeric conversion")
	TEST_ASSERT_EQUAL(i32_minimum.low16, 0, "i32 minimum low word")
	TEST_ASSERT_EQUAL(i32_minimum.high16, 32768, "i32 minimum high word")
	TEST_ASSERT_EQUAL(i32_maximum.low16, 65535, "i32 maximum low word")
	TEST_ASSERT_EQUAL(i32_maximum.high16, 32767, "i32 maximum high word")
	TEST_ASSERT_EQUAL(cells_result.plan.cells[1].terrain_path, /turf/closed/mineral/stone, "terrain table path")
	TEST_ASSERT_EQUAL(cells_result.plan.cells[1].material_path, /datum/material/stone, "material table path")

	var/list/crc_check = list(49, 50, 51, 52, 53, 54, 55, 56, 57) // "123456789"
	var/list/crc = df_chunk_crc32_iso_hdlc(crc_check)
	TEST_ASSERT(crc, "CRC vector should calculate")
	TEST_ASSERT_EQUAL(crc[1], 14630, "CRC-32/ISO-HDLC low half for 123456789") // 0x3926
	TEST_ASSERT_EQUAL(crc[2], 52212, "CRC-32/ISO-HDLC high half for 123456789") // 0xcbf4
	var/datum/df_chunk_byte_result/nul_byte = df_chunk_base64url_decode("AA")
	TEST_ASSERT(!nul_byte.error && nul_byte.bytes.len == 1 && nul_byte.bytes[1] == 0, "Base64URL NUL must stay a numeric byte")
	TEST_ASSERT(df_chunk_base64url_decode("AB").error == _df_chunk_error(422, "base64_noncanonical"), "noncanonical trailing Base64URL bits rejected")
	TEST_ASSERT(df_chunk_base64url_decode("AA=").error, "padded Base64URL rejected")

	var/list/truncated_frame = cells_frame.Copy()
	var/truncated_encoded = df_chunk_base64url_encode_bytes(truncated_frame)
	var/datum/df_chunk_decode_result/truncated_result = df_chunk_decode_plan("[DFCP_PLAN_PREFIX][copytext(truncated_encoded, 1, length(truncated_encoded))]", cells_request)
	TEST_ASSERT(truncated_result.error, "truncated frame rejected")
	TEST_ASSERT(df_chunk_decode_plan("DFCP1.!A", cells_request).error, "bad Base64URL alphabet rejected")

	var/list/version_frame = cells_frame.Copy()
	version_frame[5] = 2
	TEST_ASSERT(df_chunk_frame_recompute_crc(version_frame), "version fixture CRC")
	var/datum/df_chunk_decode_result/version_result = df_chunk_protocol_test_decode(version_frame, cells_request)
	TEST_ASSERT_EQUAL(version_result.error, _df_chunk_error(426, "unsupported_version"), "unsupported frame version")

	var/list/crc_frame = cells_frame.Copy()
	crc_frame[45] ^= 1
	var/datum/df_chunk_decode_result/crc_result = df_chunk_protocol_test_decode(crc_frame, cells_request)
	TEST_ASSERT_EQUAL(crc_result.error, _df_chunk_error(422, "crc32"), "bad stored CRC")

	var/list/id_frame = cells_frame.Copy()
	id_frame[49] = 255
	TEST_ASSERT(df_chunk_frame_recompute_crc(id_frame), "unknown cell ID fixture CRC")
	var/datum/df_chunk_decode_result/id_result = df_chunk_protocol_test_decode(id_frame, cells_request)
	TEST_ASSERT_EQUAL(id_result.error, _df_chunk_error(422, "unknown_cell_id"), "unknown cell ID")

	var/list/hardness_frame = cells_frame.Copy()
	hardness_frame[51] = 2
	TEST_ASSERT(df_chunk_frame_recompute_crc(hardness_frame), "hardness fixture CRC")
	var/datum/df_chunk_decode_result/hardness_result = df_chunk_protocol_test_decode(hardness_frame, cells_request)
	TEST_ASSERT_EQUAL(hardness_result.error, _df_chunk_error(422, "cell_hardness_profile"), "mineral hardness must echo profile")

	var/datum/df_chunk_request/wrong_echo_request = df_chunk_request_from_wire("1", "1", "1", "0123456789abcdef", "3", "-18", "42", "-3", "1", list())
	var/datum/df_chunk_decode_result/echo_result = df_chunk_protocol_test_decode(cells_frame, wrong_echo_request)
	TEST_ASSERT_EQUAL(echo_result.error, _df_chunk_error(422, "request_echo_mismatch"), "chunk echo rejection")

	var/datum/df_chunk_request/records_request = df_chunk_protocol_test_request(DFCP_SECTION_DECORATIONS)
	var/list/records_frame = df_chunk_protocol_test_records_frame(records_request)
	TEST_ASSERT(records_frame, "records fixture must build")
	var/datum/df_chunk_decode_result/records_result = df_chunk_protocol_test_decode(records_frame, records_request)
	TEST_ASSERT(records_result?.succeeded(), "valid records fixture failed: [records_result?.error]")
	TEST_ASSERT_EQUAL(records_result.plan.decorations.len, 2, "record count")
	TEST_ASSERT_EQUAL(records_result.plan.decorations[1].semantic_path, /obj/structure/plant/garden/crop/plump_helmet, "flora table path")
	TEST_ASSERT_EQUAL(records_result.plan.decorations[2].semantic_path, /obj/item/stack/ore/smeltable/gold, "ore table path")

	var/list/record_id_frame = records_frame.Copy()
	record_id_frame[52] = 255
	TEST_ASSERT(df_chunk_frame_recompute_crc(record_id_frame), "unknown record ID fixture CRC")
	var/datum/df_chunk_decode_result/record_id_result = df_chunk_protocol_test_decode(record_id_frame, records_request)
	TEST_ASSERT_EQUAL(record_id_result.error, _df_chunk_error(422, "unknown_record_id"), "unknown record ID")

	var/list/record_args_frame = records_frame.Copy()
	record_args_frame[53] = 6 // crop stage must be 0..5
	TEST_ASSERT(df_chunk_frame_recompute_crc(record_args_frame), "record arguments fixture CRC")
	var/datum/df_chunk_decode_result/record_args_result = df_chunk_protocol_test_decode(record_args_frame, records_request)
	TEST_ASSERT_EQUAL(record_args_result.error, _df_chunk_error(422, "flora_arguments"), "type-specific flora arguments")

	var/list/record_order_frame = records_frame.Copy()
	record_order_frame[62] = 1 // second record x before first record x
	TEST_ASSERT(df_chunk_frame_recompute_crc(record_order_frame), "record order fixture CRC")
	var/datum/df_chunk_decode_result/record_order_result = df_chunk_protocol_test_decode(record_order_frame, records_request)
	TEST_ASSERT_EQUAL(record_order_result.error, _df_chunk_error(422, "record_order"), "strict record order")

	var/list/hidden_records_frame = records_frame.Copy()
	hidden_records_frame[8] = DFCP_SECTION_CELLS
	TEST_ASSERT(df_chunk_frame_recompute_crc(hidden_records_frame), "hidden records fixture CRC")
	var/datum/df_chunk_decode_result/hidden_records_result = df_chunk_protocol_test_decode(hidden_records_frame, records_request)
	TEST_ASSERT_EQUAL(hidden_records_result.error, _df_chunk_error(422, "record_section_mismatch"), "records without records flag")

	var/datum/df_chunk_request/large_request = df_chunk_protocol_test_request(DFCP_SECTION_BOTH)
	var/list/large_frame = df_chunk_protocol_test_large_frame(large_request)
	TEST_ASSERT(large_frame && large_frame.len == DFCP_MAX_FRAME_BYTES, "maximum representative frame bytes")
	var/large_encoded = df_chunk_base64url_encode_bytes(large_frame)
	TEST_ASSERT(large_encoded && length(DFCP_PLAN_PREFIX) + length(large_encoded) <= 71 * 1024, "representative decoded frame remains bounded below 71 KiB ASCII")
	var/decode_started = REALTIMEOFDAY
	var/datum/df_chunk_decode_result/large_result = df_chunk_decode_plan("[DFCP_PLAN_PREFIX][large_encoded]", large_request)
	var/decode_elapsed = REALTIMEOFDAY - decode_started
	TEST_ASSERT(large_result?.succeeded(), "maximum representative frame decodes: [large_result?.error]")
	TEST_ASSERT_EQUAL(large_result.plan.decorations.len, DFCP_MAX_RECORDS, "maximum record count")
	log_test("DFCP1 decoded [length(DFCP_PLAN_PREFIX) + length(large_encoded)] ASCII bytes in [decode_elapsed / 10]s (bounded performance fixture; no timing threshold)")

	var/capabilities = df_chunk_capabilities()
	if(capabilities != DFCP_CAPABILITIES)
		if(capabilities == _df_chunk_error(503, "dflib_unavailable"))
			log_test("DFCP1 native capability/lifecycle tests skipped: [capabilities]")
			return
		Fail("DFCP1 capabilities failed: [capabilities]")
		return
	TEST_ASSERT(df_chunk_protocol_compatible(), "capability compatibility cache")

	var/list/native_errors = list()
	var/datum/df_chunk_request/native_request = df_chunk_request_from_wire("1", "1", "1", "0123456789abcdef", "3", "-17", "42", "-3", "3", native_errors)
	TEST_ASSERT(native_request, "native request canonical: [native_errors["error"]]")
	var/synchronous = df_chunk_plan(1, 1, 1, "0123456789abcdef", 3, "-17", "42", "-3", 3)
	TEST_ASSERT(_df_chunk_has_prefix(synchronous, DFCP_PLAN_PREFIX), "synchronous plan: [synchronous]")
	var/synchronous_repeat = df_chunk_plan(1, 1, 1, "0123456789abcdef", 3, "-17", "42", "-3", 3)
	TEST_ASSERT_EQUAL(synchronous_repeat, synchronous, "repeated synchronous request deterministic")
	var/datum/df_chunk_decode_result/synchronous_result = df_chunk_decode_plan(synchronous, native_request)
	TEST_ASSERT(synchronous_result?.succeeded(), "native synchronous decode: [synchronous_result?.error]")
	TEST_ASSERT_EQUAL(synchronous_result.plan.sections, DFCP_SECTION_BOTH, "native BOTH plan preserves both sections")
	TEST_ASSERT_EQUAL(synchronous_result.plan.cells.len, DFCP_CELL_COUNT, "native BOTH plan has halo cells")
	TEST_ASSERT_EQUAL(synchronous_result.plan.decorations.len, synchronous_result.plan.record_count, "native BOTH plan record count matches decoded records")
	var/datum/df_chunk_decode_result/synchronous_repeat_result = df_chunk_decode_plan(synchronous_repeat, native_request)
	TEST_ASSERT(synchronous_repeat_result?.succeeded(), "repeated native BOTH decode: [synchronous_repeat_result?.error]")
	TEST_ASSERT_EQUAL(synchronous_repeat_result.plan.decorations.len, synchronous_result.plan.decorations.len, "repeated seed record count deterministic")
	for(var/record_index in 1 to synchronous_result.plan.decorations.len)
		var/datum/df_chunk_decoration/first_record = synchronous_result.plan.decorations[record_index]
		var/datum/df_chunk_decoration/repeated_record = synchronous_repeat_result.plan.decorations[record_index]
		TEST_ASSERT_EQUAL(repeated_record.kind, first_record.kind, "repeated seed record kind [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.local_x, first_record.local_x, "repeated seed record x [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.local_y, first_record.local_y, "repeated seed record y [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.arg0, first_record.arg0, "repeated seed record arg0 [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.arg1, first_record.arg1, "repeated seed record arg1 [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.seed_low16, first_record.seed_low16, "repeated seed record low word [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.seed_high16, first_record.seed_high16, "repeated seed record high word [record_index]")
		TEST_ASSERT_EQUAL(repeated_record.semantic_path, first_record.semantic_path, "repeated seed semantic path [record_index]")

	var/job_id = df_chunk_submit(1, 1, 1, "0123456789abcdef", 3, "-17", "42", "-3", 3)
	TEST_ASSERT(_df_chunk_is_job_id(job_id), "async submit: [job_id]")
	chunk_jobs += job_id
	var/asynchronous
	for(var/attempt in 1 to 200)
		var/poll_response = df_chunk_poll(job_id)
		if(poll_response == DFCP_POLL_PENDING)
			sleep(1)
			continue
		if(_df_chunk_has_prefix(poll_response, DFCP_POLL_READY_PREFIX))
			asynchronous = copytext(poll_response, length(DFCP_POLL_READY_PREFIX) + 1)
			break
		Fail("unexpected async poll response: [poll_response]")
		return
	TEST_ASSERT(asynchronous, "async job did not become ready")
	TEST_ASSERT_EQUAL(asynchronous, synchronous, "sync and async frames match")
	var/datum/df_chunk_decode_result/asynchronous_result = df_chunk_decode_plan(asynchronous, native_request)
	TEST_ASSERT(asynchronous_result?.succeeded(), "native async decode: [asynchronous_result?.error]")
	TEST_ASSERT_EQUAL(df_chunk_forget(job_id), DFCP_FORGET_OK, "async forget")
	chunk_jobs -= job_id
	TEST_ASSERT(_df_chunk_has_prefix(df_chunk_poll(job_id), "DFE1.404."), "forgotten job is released")
