#ifndef DFLIB

/* This comment bypasses grep checks */ /var/__dflib

/proc/__detect_dflib()
	if (world.system_type == UNIX)
		if (fexists("./libdflib.so"))
			// No need for LD_LIBRARY_PATH badness.
			return __dflib = "./libdflib.so"
		else if (fexists("./dflib"))
			// Old dumb filename.
			return __dflib = "./dflib"
		else if (fexists("[world.GetConfig("env", "HOME")]/.byond/bin/dflib"))
			// Old dumb filename in `~/.byond/bin`.
			return __dflib = "dflib"
		else
			// It's not in the current directory, so try others
			return __dflib = "libdflib.so"
	else
		return __dflib = "dflib"

#define DFLIB (__dflib || __detect_dflib())
#endif

/proc/fbm(x=100, y=100, seed=null, frequency=0.03, octaves=5, lacunarity=2, persistence=0.5)
	if(!seed) seed = rand(1, 2000)
	var/res = LIBCALL(DFLIB,"fbm")("[x]", "[y]" ,"[seed]", "[frequency]", "[octaves]", "[lacunarity]", "[persistence]")
	var/list/lres = splittext(res, ",")
	return lres

// Defining default seed because it will never provide coherent noise if seed on every run would be different
/proc/fbm3d(x=100, y=100, z=1, seed=1, frequency=0.03, octaves=5, lacunarity=2, persistence=0.5)
	var/res = LIBCALL(DFLIB,"fbm3d")("[x]", "[y]", "[z]" ,"[seed]", "[frequency]", "[octaves]", "[lacunarity]", "[persistence]")
	var/list/lres = splittext(res, ",")
	return lres

// DFLib 0.2 DFCP1. Keep these wire values separate from future map-application
// work: this stage only asks for and validates immutable planner data.
#define DFCP_PROTOCOL_VERSION 1
#define DFCP_ALGORITHM_VERSION 1
#define DFCP_TABLE_VERSION 1
#define DFCP_CORE_SIZE 32
#define DFCP_HALO_SIZE 1
#define DFCP_EXTENDED_SIZE 34
#define DFCP_CELL_STRIDE 3
#define DFCP_RECORD_STRIDE 12
#define DFCP_HEADER_LENGTH 48
#define DFCP_CELL_COUNT 1156
#define DFCP_MAX_RECORDS 4096
#define DFCP_MAX_FRAME_BYTES 52668
#define DFCP_MAX_FRAME_ASCII 70224
#define DFCP_SECTION_CELLS 1
#define DFCP_SECTION_DECORATIONS 2
#define DFCP_SECTION_BOTH 3
#define DFCP_PLAN_PREFIX "DFCP1."
#define DFCP_JOB_PREFIX "DFJ1."
#define DFCP_POLL_PENDING "DFP1.pending"
#define DFCP_POLL_READY_PREFIX "DFP1.ready."
#define DFCP_FORGET_OK "DFK1.ok"
#define DFCP_CAPABILITIES "DFCAP1.p1.a1.t1.c32.h1.s3.r12.j256"

// Table-v1 semantic IDs are protocol constants. Their DM type mappings live
// in dwarfs/code/modules/mapgen/chunk_protocol.dm and are append-only.
#define DFCP_TERRAIN_WATER 1
#define DFCP_TERRAIN_DIRT 2
#define DFCP_TERRAIN_ROCK_FLOOR 3
#define DFCP_TERRAIN_STONE_WALL 4
#define DFCP_TERRAIN_SAND_WALL 5
#define DFCP_MATERIAL_NONE 0
#define DFCP_MATERIAL_STONE 1
#define DFCP_MATERIAL_SANDSTONE 2
#define DFCP_RECORD_FLORA 1
#define DFCP_RECORD_FAUNA 2
#define DFCP_RECORD_ORE 3
#define DFCP_RECORD_TROLL_ROCK 4
#define DFCP_FLORA_TOWERCAP 1
#define DFCP_FLORA_PLUMP_HELMET 2
#define DFCP_FLORA_PIG_TAIL 3
#define DFCP_FLORA_CAVE_WHEAT 4
#define DFCP_FAUNA_GIANT_SPIDER 1
#define DFCP_FAUNA_TROLL 2
#define DFCP_ORE_GOLD 1
#define DFCP_ORE_IRON 2
#define DFCP_ORE_DIAMOND 3
#define DFCP_ORE_RUBY 4
#define DFCP_ORE_SAPPHIRE 5
#define DFCP_ORE_COAL 6
#define DFCP_ORE_COPPER 7
#define DFCP_ORE_CASSITERITE 8
#define DFCP_ORE_ALUMINUM 9
#define DFCP_ORE_GALENA 10
#define DFCP_ORE_SILVER 11
#define DFCP_ORE_PLATINUM 12
#define DFCP_ORE_ADAMANTINE 13

// `null` means the capability probe has not run. A failed probe is cached too:
// repeatedly attempting to load a missing/incompatible native library is noisy
// and cannot make it compatible during a running world.
GLOBAL_VAR(df_chunk_capability_state)
GLOBAL_VAR(df_chunk_capability_response)
GLOBAL_VAR(df_chunk_capability_native_response)

/proc/_df_chunk_error(code, token)
	return "DFE1.[code].[token]"

/proc/_df_chunk_has_prefix(value, prefix)
	if(!istext(value) || length(value) < length(prefix))
		return FALSE
	return copytext(value, 1, length(prefix) + 1) == prefix

/// Accept only the deliberately small, safe native error grammar before
/// forwarding it to callers. This keeps wrapper failures structured even if a
/// wrong .so was loaded.
/proc/_df_chunk_is_error_string(value)
	if(!_df_chunk_has_prefix(value, "DFE1."))
		return FALSE
	var/value_length = length(value)
	var/position = 6
	var/code_digits = 0
	while(position <= value_length)
		var/character = text2ascii(value, position)
		if(character == 46) // .
			break
		if(character < 48 || character > 57)
			return FALSE
		code_digits++
		position++
	if(!code_digits || position > value_length)
		return FALSE
	position++
	if(position > value_length)
		return FALSE
	while(position <= value_length)
		var/character = text2ascii(value, position)
		if(!((character >= 48 && character <= 57) || (character >= 65 && character <= 90) || (character >= 97 && character <= 122) || character == 95)) // 0-9 A-Z a-z _
			return FALSE
		position++
	return TRUE

/proc/_df_chunk_is_job_id(value)
	if(!_df_chunk_has_prefix(value, DFCP_JOB_PREFIX) || length(value) != 21)
		return FALSE
	for(var/position in 6 to 21)
		var/character = text2ascii(value, position)
		if(!((character >= 48 && character <= 57) || (character >= 97 && character <= 102))) // 0-9 a-f
			return FALSE
	return TRUE

/// Calls and caches the one native capability advertisement. A missing symbol
/// or library is caught where BYOND exposes it as an exception; all callers see
/// a protocol-shaped error rather than a null/native runtime value.
/proc/df_chunk_capabilities()
	if(!isnull(GLOB.df_chunk_capability_response))
		return GLOB.df_chunk_capability_response

	var/response
	try
		response = LIBCALL(DFLIB, "df_chunk_capabilities")()
	catch
		response = null
	GLOB.df_chunk_capability_native_response = response

	if(response == DFCP_CAPABILITIES)
		GLOB.df_chunk_capability_state = TRUE
		GLOB.df_chunk_capability_response = response
	else
		GLOB.df_chunk_capability_state = FALSE
		if(_df_chunk_is_error_string(response))
			GLOB.df_chunk_capability_response = response
		else if(istext(response) && length(response))
			GLOB.df_chunk_capability_response = _df_chunk_error(426, "capability_mismatch")
		else
			GLOB.df_chunk_capability_response = _df_chunk_error(503, "dflib_unavailable")
	return GLOB.df_chunk_capability_response

/proc/df_chunk_protocol_compatible()
	df_chunk_capabilities()
	return GLOB.df_chunk_capability_state == TRUE

/proc/_df_chunk_require_compatible()
	var/capabilities = df_chunk_capabilities()
	if(GLOB.df_chunk_capability_state == TRUE)
		return null
	return capabilities

/proc/_df_chunk_plan_response_or_error(response)
	if(_df_chunk_is_error_string(response))
		return response
	if(_df_chunk_has_prefix(response, DFCP_PLAN_PREFIX) && length(response) > length(DFCP_PLAN_PREFIX))
		return response
	return _df_chunk_error(502, "plan_response")

/proc/_df_chunk_submit_response_or_error(response)
	if(_df_chunk_is_error_string(response))
		return response
	if(_df_chunk_is_job_id(response))
		return response
	return _df_chunk_error(502, "submit_response")

/// Synchronous DFCP1 request. Coordinate arguments are deliberately required
/// to be canonical text; df_chunk_i32_from_safe_number() is the bounded bridge
/// for current-map numeric coordinates.
/proc/df_chunk_plan(protocol_version, algorithm_version, table_version, seed_hex, profile_id, chunk_x, chunk_y, chunk_z, sections)
	var/compatibility_error = _df_chunk_require_compatible()
	if(compatibility_error)
		return compatibility_error
	var/list/errors = list()
	var/datum/df_chunk_request/request = df_chunk_request_from_wire(protocol_version, algorithm_version, table_version, seed_hex, profile_id, chunk_x, chunk_y, chunk_z, sections, errors)
	if(!request)
		return errors["error"] || _df_chunk_error(400, "request")
	var/response
	try
		response = LIBCALL(DFLIB, "df_chunk_plan")("[request.protocol_version]", "[request.algorithm_version]", "[request.table_version]", request.seed.hex, "[request.profile_id]", request.chunk_x.text, request.chunk_y.text, request.chunk_z.text, "[request.sections]")
	catch
		return _df_chunk_error(503, "dflib_unavailable")
	return _df_chunk_plan_response_or_error(response)

/// Async DFCP1 request. Call df_chunk_forget() for every returned DFJ1 ID.
/proc/df_chunk_submit(protocol_version, algorithm_version, table_version, seed_hex, profile_id, chunk_x, chunk_y, chunk_z, sections)
	var/compatibility_error = _df_chunk_require_compatible()
	if(compatibility_error)
		return compatibility_error
	var/list/errors = list()
	var/datum/df_chunk_request/request = df_chunk_request_from_wire(protocol_version, algorithm_version, table_version, seed_hex, profile_id, chunk_x, chunk_y, chunk_z, sections, errors)
	if(!request)
		return errors["error"] || _df_chunk_error(400, "request")
	var/response
	try
		response = LIBCALL(DFLIB, "df_chunk_submit")("[request.protocol_version]", "[request.algorithm_version]", "[request.table_version]", request.seed.hex, "[request.profile_id]", request.chunk_x.text, request.chunk_y.text, request.chunk_z.text, "[request.sections]")
	catch
		return _df_chunk_error(503, "dflib_unavailable")
	return _df_chunk_submit_response_or_error(response)

/proc/df_chunk_poll(job_id)
	var/compatibility_error = _df_chunk_require_compatible()
	if(compatibility_error)
		return compatibility_error
	if(!_df_chunk_is_job_id(job_id))
		return _df_chunk_error(400, "job_id")
	var/response
	try
		response = LIBCALL(DFLIB, "df_chunk_poll")(job_id)
	catch
		return _df_chunk_error(503, "dflib_unavailable")
	if(_df_chunk_is_error_string(response) || response == DFCP_POLL_PENDING)
		return response
	if(_df_chunk_has_prefix(response, "[DFCP_POLL_READY_PREFIX][DFCP_PLAN_PREFIX]") && length(response) > length(DFCP_POLL_READY_PREFIX) + length(DFCP_PLAN_PREFIX))
		return response
	return _df_chunk_error(502, "poll_response")

/proc/df_chunk_forget(job_id)
	var/compatibility_error = _df_chunk_require_compatible()
	if(compatibility_error)
		return compatibility_error
	if(!_df_chunk_is_job_id(job_id))
		return _df_chunk_error(400, "job_id")
	var/response
	try
		response = LIBCALL(DFLIB, "df_chunk_forget")(job_id)
	catch
		return _df_chunk_error(503, "dflib_unavailable")
	if(_df_chunk_is_error_string(response) || response == DFCP_FORGET_OK)
		return response
	return _df_chunk_error(502, "forget_response")
