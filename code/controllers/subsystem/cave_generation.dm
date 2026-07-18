// Deferred cave terrain and table-v1 decoration pipeline (B2c). Terrain stays
// on the regular ChangeTurf lifecycle; decoration application is incremental.
#define DF_CAVE_INERT 0
#define DF_CAVE_QUEUED 1
#define DF_CAVE_PLANNING 2
#define DF_CAVE_APPLYING_TERRAIN 3
#define DF_CAVE_DECORATING 4
#define DF_CAVE_SMOOTHING 5
#define DF_CAVE_LIGHTING 6
#define DF_CAVE_COMPLETE 7
#define DF_CAVE_FAILED 8

#define DF_CAVE_PRIORITY_PREWARM 1
#define DF_CAVE_PRIORITY_PROXIMITY 2
#define DF_CAVE_PRIORITY_DIRECT 3

/datum/df_cave_core_identity
	/// Immutable terrain facts captured after this chunk's regular replacement.
	/// This deliberately contains no turf reference: turf replacement reuses refs.
	var/terrain_path
	var/material_path
	var/hardness_id

/datum/df_cave_chunk
	var/datum/df_cave_level/level
	var/cx
	var/cy
	var/state = DF_CAVE_INERT
	var/datum/df_chunk_request/request
	var/job_id
	var/datum/df_chunk_plan/plan
	/// 1..1024 row-major core cursor; DFCP halo is never iterated/applied.
	var/apply_index = 1
	/// 1..plan.decorations.len cursor. Records are never retried after a runtime.
	var/decoration_index = 1
	/// Final smoothing queue cursor; queueing is also bounded by MC checks.
	var/smoothing_index = 1
	var/lighting_index = 1
	/// 3 direct demand, 2 living/client proximity, 1 center prewarm.
	var/priority = DF_CAVE_PRIORITY_PREWARM
	var/retries = 0
	var/retry_at = 0
	var/quarantined = FALSE
	var/started_at
	var/changed = 0
	/// Actual post-apply check for any exact cavesgen core left as genturf.
	var/genturf_remaining = 0
	var/list/smooth_targets = list()
	var/list/changed_core = list()
	/// Integer core-index keys only. A TRUE means this plan replaced pristine genturf.
	var/list/applied_core_mask = list()
	/// Matching immutable datum for each applied_core_mask key, never a turf ref.
	var/list/applied_core_identity = list()
	/// Per-kind counts retain only scalar protocol/application facts, never spawned refs.
	var/list/decoration_seen = list("flora" = 0, "fauna" = 0, "ore" = 0, "troll_rock" = 0)
	var/list/decoration_applied = list("flora" = 0, "fauna" = 0, "ore" = 0, "troll_rock" = 0)
	var/list/decoration_skipped = list("flora" = 0, "fauna" = 0, "ore" = 0, "troll_rock" = 0)
	var/list/decoration_failed = list("flora" = 0, "fauna" = 0, "ore" = 0, "troll_rock" = 0)
	var/decoration_skip_count = 0
	var/decoration_failure_count = 0
	var/list/decoration_skip_reasons = list()

/datum/df_cave_level
	var/z
	var/profile_id
	var/list/chunks = list()

SUBSYSTEM_DEF(cave_generation)
	name = "Deferred Cave Generation"
	init_order = INIT_ORDER_CAVE_GENERATION
	wait = 1
	priority = FIRE_PRIORITY_DEFAULT
	flags = SS_TICKER
	runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	var/committed = FALSE
	var/seed_hex
	var/list/levels = list()
	var/active_jobs = 0
	var/fallback_count = 0
	/// Starts at half a row, adapts upward, and never exceeds two rows.
	var/terrain_per_fire = 16
	var/terrain_batch_max = 64
	var/terrain_batches = 0
	var/terrain_batch_total = 0
	var/terrain_batch_peak = 0
	var/terrain_peak_tick_usage = 0
	var/terrain_total_ms = 0
	/// Starts near a small record cluster and is capped at one 32-cell core row.
	var/decoration_per_fire = 8
	var/decoration_batch_max = 32
	var/decoration_batches = 0
	var/decoration_batch_total = 0
	var/decoration_applied_total = 0
	var/decoration_batch_peak = 0
	var/decoration_peak_tick_usage = 0
	var/decoration_total_ms = 0
	var/last_proximity_scan = 0

/datum/controller/subsystem/cave_generation/Recover()
	committed = SScave_generation.committed
	seed_hex = SScave_generation.seed_hex
	levels = SScave_generation.levels
	active_jobs = SScave_generation.active_jobs
	fallback_count = SScave_generation.fallback_count
	terrain_per_fire = SScave_generation.terrain_per_fire
	terrain_batch_max = SScave_generation.terrain_batch_max
	terrain_batches = SScave_generation.terrain_batches
	terrain_batch_total = SScave_generation.terrain_batch_total
	terrain_batch_peak = SScave_generation.terrain_batch_peak
	terrain_peak_tick_usage = SScave_generation.terrain_peak_tick_usage
	terrain_total_ms = SScave_generation.terrain_total_ms
	decoration_per_fire = SScave_generation.decoration_per_fire
	decoration_batch_max = SScave_generation.decoration_batch_max
	decoration_batches = SScave_generation.decoration_batches
	decoration_batch_total = SScave_generation.decoration_batch_total
	decoration_applied_total = SScave_generation.decoration_applied_total
	decoration_batch_peak = SScave_generation.decoration_batch_peak
	decoration_peak_tick_usage = SScave_generation.decoration_peak_tick_usage
	decoration_total_ms = SScave_generation.decoration_total_ms
	last_proximity_scan = SScave_generation.last_proximity_scan
	return ..()

/datum/controller/subsystem/cave_generation/Initialize()
	// Mapping registers levels before this subsystem initializes (mapping 50,
	// this subsystem 29). Only submit here; terrain mutation waits for fire().
	if(committed)
		for(var/key in levels)
			var/datum/df_cave_level/level = levels[key]
			queue_center(level)
	return ..()

/datum/controller/subsystem/cave_generation/stat_entry(msg)
	var/requested = 0
	var/planning = 0
	var/applying = 0
	var/decorating = 0
	var/complete = 0
	var/failed = 0
	for(var/level_key in levels)
		var/datum/df_cave_level/level = levels[level_key]
		for(var/chunk_key in level.chunks)
			var/datum/df_cave_chunk/chunk = level.chunks[chunk_key]
			if(chunk.state >= DF_CAVE_QUEUED)
				requested++
			if(chunk.state == DF_CAVE_PLANNING)
				planning++
			if(chunk.state == DF_CAVE_APPLYING_TERRAIN)
				applying++
			if(chunk.state == DF_CAVE_DECORATING)
				decorating++
			if(chunk.state == DF_CAVE_COMPLETE)
				complete++
			if(chunk.state == DF_CAVE_FAILED)
				failed++
	msg = "L:[levels.len] Q:[requested] P:[planning] A:[applying] D:[decorating] C:[complete] F:[failed] FB:[fallback_count] TB:[terrain_batches]/[terrain_batch_peak] DB:[decoration_batches]/[decoration_batch_peak]"
	return ..()

/datum/controller/subsystem/cave_generation/proc/register_level(z, profile_id, seed)
	var/datum/df_cave_level/level = new
	level.z = z
	level.profile_id = profile_id
	levels["[z]"] = level
	seed_hex = seed
	return level

/proc/df_cave_floor_div(value, divisor)
	return (value - (value % divisor)) / divisor

/datum/controller/subsystem/cave_generation/proc/queue_center(datum/df_cave_level/level)
	var/max_cx = df_cave_floor_div(world.maxx - 1, DFCP_CORE_SIZE)
	var/max_cy = df_cave_floor_div(world.maxy - 1, DFCP_CORE_SIZE)
	var/center_x = max(0, min(max_cx, df_cave_floor_div(max_cx, 2)))
	var/center_y = max(0, min(max_cy, df_cave_floor_div(max_cy, 2)))
	for(var/cy in max(0, center_y - 1) to min(max_cy, center_y + 1))
		for(var/cx in max(0, center_x - 1) to min(max_cx, center_x + 1))
			request_chunk(level, cx, cy)

/datum/controller/subsystem/cave_generation/proc/request_chunk(datum/df_cave_level/level, cx, cy)
	if(!committed || !level || cx < 0 || cy < 0)
		return null
	cx = min(cx, df_cave_floor_div(world.maxx - 1, DFCP_CORE_SIZE))
	cy = min(cy, df_cave_floor_div(world.maxy - 1, DFCP_CORE_SIZE))
	var/key = "[cx],[cy]"
	var/datum/df_cave_chunk/chunk = level.chunks[key]
	if(!chunk)
		var/has_cave_cell = FALSE
		for(var/y in cy * DFCP_CORE_SIZE + 1 to min(world.maxy, (cy + 1) * DFCP_CORE_SIZE))
			for(var/x in cx * DFCP_CORE_SIZE + 1 to min(world.maxx, (cx + 1) * DFCP_CORE_SIZE))
				var/turf/T = locate(x, y, level.z)
				if(T?.loc.type == /area/cavesgen)
					has_cave_cell = TRUE
					break
			if(has_cave_cell)
				break
		if(!has_cave_cell)
			return null
		chunk = new
		chunk.level = level
		chunk.cx = cx
		chunk.cy = cy
		level.chunks[key] = chunk
	if(chunk.state == DF_CAVE_INERT && !chunk.quarantined && world.time >= chunk.retry_at)
		chunk.state = DF_CAVE_QUEUED
	else if(chunk.state == DF_CAVE_FAILED && !chunk.quarantined && world.time >= chunk.retry_at && chunk.retries < 3)
		chunk.state = DF_CAVE_QUEUED
	return chunk

/datum/controller/subsystem/cave_generation/proc/best_chunk(wanted_state)
	var/datum/df_cave_chunk/best
	for(var/level_key in levels)
		var/datum/df_cave_level/level = levels[level_key]
		for(var/chunk_key in level.chunks)
			var/datum/df_cave_chunk/chunk = level.chunks[chunk_key]
			if(chunk.state == wanted_state && (!best || chunk.priority > best.priority))
				best = chunk
	return best

/// Decoration has one selector so direct requests always outrank proximity and
/// center prewarm work without adding a second mutation executor.
/datum/controller/subsystem/cave_generation/proc/select_decoration_chunk()
	return best_chunk(DF_CAVE_DECORATING)

/datum/controller/subsystem/cave_generation/proc/request_proximity()
	if(world.time < last_proximity_scan + 10)
		return
	last_proximity_scan = world.time
	for(var/client/C in GLOB.clients)
		var/mob/living/L = C.mob
		if(!L)
			continue
		var/turf/T = get_turf(L)
		var/datum/df_cave_level/level = T ? levels["[T.z]"] : null
		if(!level)
			continue
		var/base_x = df_cave_floor_div(T.x - 1, DFCP_CORE_SIZE)
		var/base_y = df_cave_floor_div(T.y - 1, DFCP_CORE_SIZE)
		for(var/cy in max(0, base_y - 1) to base_y + 1)
			for(var/cx in max(0, base_x - 1) to base_x + 1)
				var/datum/df_cave_chunk/chunk = request_chunk(level, cx, cy)
				if(chunk)
					chunk.priority = max(chunk.priority, DF_CAVE_PRIORITY_PROXIMITY)

/datum/controller/subsystem/cave_generation/proc/chunk_for_turf(turf/T, request = TRUE)
	if(!committed || !T || T.loc.type != /area/cavesgen)
		return null
	var/datum/df_cave_level/level = levels["[T.z]"]
	if(!level)
		return null
	var/cx = df_cave_floor_div(T.x - 1, DFCP_CORE_SIZE)
	var/cy = df_cave_floor_div(T.y - 1, DFCP_CORE_SIZE)
	var/key = "[cx],[cy]"
	var/datum/df_cave_chunk/chunk = level.chunks[key]
	if((!chunk || chunk.state == DF_CAVE_INERT || (chunk.state == DF_CAVE_FAILED && !chunk.quarantined && chunk.retries < 3 && world.time >= chunk.retry_at)) && request)
		chunk = request_chunk(level, cx, cy)
	return chunk

/datum/controller/subsystem/cave_generation/proc/forget_job(datum/df_cave_chunk/chunk)
	if(chunk?.job_id)
		df_chunk_forget(chunk.job_id)
		chunk.job_id = null
		active_jobs = max(0, active_jobs - 1)

/datum/controller/subsystem/cave_generation/proc/fail_chunk(datum/df_cave_chunk/chunk, reason)
	if(!chunk || chunk.quarantined)
		return
	forget_job(chunk)
	chunk.retries++
	chunk.retry_at = world.time + chunk.retries * 10
	chunk.state = chunk.retries >= 3 ? DF_CAVE_FAILED : DF_CAVE_INERT
	log_runtime("Deferred cave chunk [chunk.level.z] [chunk.cx],[chunk.cy] failed: [reason]")

/// A runtime while mutating a record is terminal. Retrying a partially applied
/// record could duplicate a mob/plant or overwrite a later player mutation.
/datum/controller/subsystem/cave_generation/proc/quarantine_chunk(datum/df_cave_chunk/chunk, reason)
	if(!chunk)
		return
	forget_job(chunk)
	chunk.quarantined = TRUE
	chunk.retries = 3
	chunk.state = DF_CAVE_FAILED
	log_runtime("Deferred cave chunk [chunk.level.z] [chunk.cx],[chunk.cy] quarantined: [reason]")

/datum/controller/subsystem/cave_generation/proc/submit_chunk(datum/df_cave_chunk/chunk)
	if(active_jobs >= 2 || chunk.state != DF_CAVE_QUEUED)
		return
	var/list/errors = list()
	chunk.request = df_chunk_request_from_wire("1", "1", "1", seed_hex, "[chunk.level.profile_id]", "[chunk.cx]", "[chunk.cy]", "-[chunk.level.profile_id]", "3", errors)
	if(!chunk.request)
		fail_chunk(chunk, errors["error"])
		return
	var/result = df_chunk_submit(1, 1, 1, seed_hex, chunk.level.profile_id, chunk.request.chunk_x.text, chunk.request.chunk_y.text, chunk.request.chunk_z.text, DFCP_SECTION_BOTH)
	if(!_df_chunk_is_job_id(result))
		fail_chunk(chunk, result)
		return
	chunk.job_id = result
	chunk.started_at = REALTIMEOFDAY
	chunk.state = DF_CAVE_PLANNING
	active_jobs++

/datum/controller/subsystem/cave_generation/proc/poll_chunk(datum/df_cave_chunk/chunk)
	var/result = df_chunk_poll(chunk.job_id)
	if(result == DFCP_POLL_PENDING)
		return
	if(!_df_chunk_has_prefix(result, DFCP_POLL_READY_PREFIX))
		fail_chunk(chunk, result)
		return
	var/frame = copytext(result, length(DFCP_POLL_READY_PREFIX) + 1)
	var/decode_started = REALTIMEOFDAY
	var/datum/df_chunk_decode_result/decoded = df_chunk_decode_plan(frame, chunk.request)
	forget_job(chunk)
	if(!decoded.succeeded())
		fail_chunk(chunk, decoded.error)
		return
	chunk.plan = decoded.plan
	// A new plan has not mutated anything yet; reset only here, never on
	// recovery/shutdown, so an in-flight decoration cursor remains durable.
	chunk.apply_index = 1
	chunk.decoration_index = 1
	chunk.smoothing_index = 1
	chunk.lighting_index = 1
	chunk.genturf_remaining = 0
	chunk.applied_core_mask = list()
	chunk.applied_core_identity = list()
	chunk.state = DF_CAVE_APPLYING_TERRAIN
	log_world("Deferred cave [chunk.level.z] [chunk.cx],[chunk.cy] plan [((REALTIMEOFDAY - chunk.started_at) / 10)]s decode [((REALTIMEOFDAY - decode_started) / 10)]s")

/proc/df_cave_track_preserved_turf(datum/df_cave_chunk/chunk, turf/T)
	chunk.changed_core |= T
	chunk.smooth_targets |= T
	for(var/turf/neighbor in orange(1, T))
		chunk.smooth_targets |= neighbor

/proc/df_cave_track_changed_turf(datum/df_cave_chunk/chunk, turf/T)
	chunk.changed++
	chunk.changed_core += T
	chunk.smooth_targets |= T
	for(var/turf/neighbor in orange(1, T))
		chunk.smooth_targets |= neighbor

/// Decoration can alter a mineral overlay after terrain application. It shares
/// the final local smoothing set but never promotes a spawned atom to chunk state.
/proc/df_cave_track_decoration_turf(datum/df_cave_chunk/chunk, turf/T)
	if(!chunk || !T)
		return
	chunk.smooth_targets |= T
	for(var/turf/neighbor in orange(1, T))
		chunk.smooth_targets |= neighbor

/proc/df_cave_finalize_terrain_turf(turf/T, datum/df_chunk_cell/cell)
	var/turf/new_turf = T.ChangeTurf(cell.terrain_path, null, null, CHANGETURF_DEFER_CHANGE, cell.material_path)
	new_turf.set_hardness(cell.hardness_id)
	new_turf.AfterChange(CHANGETURF_DEFER_CHANGE, /turf/open/genturf)
	return new_turf

/proc/df_cave_mark_applied_core(datum/df_cave_chunk/chunk, core_index, datum/df_chunk_cell/cell)
	if(!chunk || !cell || !isnum(core_index) || core_index != round(core_index) || core_index < 1 || core_index > DFCP_CORE_SIZE * DFCP_CORE_SIZE)
		return FALSE
	if(!chunk.applied_core_mask)
		chunk.applied_core_mask = list()
	if(!chunk.applied_core_identity)
		chunk.applied_core_identity = list()
	if(chunk.applied_core_mask.len < core_index)
		chunk.applied_core_mask.len = core_index
	if(chunk.applied_core_identity.len < core_index)
		chunk.applied_core_identity.len = core_index
	var/datum/df_cave_core_identity/identity = new
	identity.terrain_path = cell.terrain_path
	identity.material_path = cell.material_path
	identity.hardness_id = cell.hardness_id
	chunk.applied_core_mask[core_index] = TRUE
	chunk.applied_core_identity[core_index] = identity
	return TRUE

/// Preserve non-genturf mutations while tracking them for the same local
/// smoothing/lighting lifecycle as replacements. Only a successful replacement
/// receives the integer-keyed identity required by decoration application.
/proc/df_cave_apply_core_turf(datum/df_cave_chunk/chunk, turf/T, datum/df_chunk_cell/cell, core_index = null)
	if(!T || !cell || T.loc.type != /area/cavesgen)
		return FALSE
	if(!istype(T, /turf/open/genturf))
		df_cave_track_preserved_turf(chunk, T)
		return FALSE
	var/turf/new_turf = df_cave_finalize_terrain_turf(T, cell)
	df_cave_track_changed_turf(chunk, new_turf)
	if(!isnull(core_index))
		df_cave_mark_applied_core(chunk, core_index, cell)
	return TRUE

/proc/df_cave_decoration_kind_key(kind)
	switch(kind)
		if(DFCP_RECORD_FLORA)
			return "flora"
		if(DFCP_RECORD_FAUNA)
			return "fauna"
		if(DFCP_RECORD_ORE)
			return "ore"
		if(DFCP_RECORD_TROLL_ROCK)
			return "troll_rock"
	return "unknown"

/proc/df_cave_note_decoration_count(list/counts, kind)
	if(!counts)
		return
	var/key = df_cave_decoration_kind_key(kind)
	counts[key] = (counts[key] || 0) + 1

/proc/df_cave_decoration_counts_text(list/counts)
	if(!counts)
		return "flora=0 fauna=0 ore=0 troll_rock=0"
	var/flora = counts["flora"] || 0
	var/fauna = counts["fauna"] || 0
	var/ore = counts["ore"] || 0
	var/troll_rock = counts["troll_rock"] || 0
	return "flora=[flora] fauna=[fauna] ore=[ore] troll_rock=[troll_rock]"

/proc/df_cave_note_decoration_seen(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record)
	if(chunk)
		df_cave_note_decoration_count(chunk.decoration_seen, record ? record.kind : null)

/proc/df_cave_skip_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record, reason)
	if(!chunk)
		return FALSE
	var/kind = record ? record.kind : null
	df_cave_note_decoration_count(chunk.decoration_skipped, kind)
	chunk.decoration_skip_count++
	chunk.decoration_skip_reasons[reason] = (chunk.decoration_skip_reasons[reason] || 0) + 1
	return FALSE

/// Expected mutation races are intentionally aggregated once per chunk rather
/// than logged for each record. The decoder and helpers use this finite set.
/proc/df_cave_decoration_skip_reasons_text(datum/df_cave_chunk/chunk)
	if(!chunk?.decoration_skip_reasons?.len)
		return "none"
	var/static/list/known_reasons = list("missing_plan_or_record", "local_coordinate", "unapplied_or_preserved_core", "missing_core_identity", "outside_world", "outside_exact_cavesgen", "core_identity_mismatch", "generated_terrain_mutated", "flora_semantic_path", "flora_requires_exact_dirt", "towercap_arguments", "crop_arguments", "flora_blocked", "flora_exists", "flora_initialize", "fauna_semantic_path", "fauna_arguments", "fauna_living_occupant", "fauna_blocked", "fauna_initialize", "ore_semantic_path", "ore_arguments", "ore_requires_mineral", "ore_exists", "troll_rock_semantic_path", "troll_rock_arguments", "troll_rock_requires_stone", "troll_rock_exists", "record_kind")
	var/list/parts = list()
	for(var/reason in known_reasons)
		var/count = chunk.decoration_skip_reasons[reason] || 0
		if(count)
			parts += "[reason]=[count]"
	return parts.len ? parts.Join(" ") : "other=[chunk.decoration_skip_count]"

/proc/df_cave_fail_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record)
	if(!chunk)
		return
	df_cave_note_decoration_count(chunk.decoration_failed, record ? record.kind : null)
	chunk.decoration_failure_count++

/// Revalidates every record against its own integer core key and immutable
/// terrain identity. No turf reference is trusted across ChangeTurf calls.
/proc/df_cave_decoration_target(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record)
	if(!chunk || !record || !chunk.plan || !chunk.level)
		df_cave_skip_decoration(chunk, record, "missing_plan_or_record")
		return null
	if(!isnum(record.local_x) || !isnum(record.local_y) || record.local_x != round(record.local_x) || record.local_y != round(record.local_y) || record.local_x < 0 || record.local_x >= DFCP_CORE_SIZE || record.local_y < 0 || record.local_y >= DFCP_CORE_SIZE)
		df_cave_skip_decoration(chunk, record, "local_coordinate")
		return null
	var/core_index = record.local_y * DFCP_CORE_SIZE + record.local_x + 1
	if(!chunk.applied_core_mask || core_index > chunk.applied_core_mask.len || !chunk.applied_core_mask[core_index])
		df_cave_skip_decoration(chunk, record, "unapplied_or_preserved_core")
		return null
	if(!chunk.applied_core_identity || core_index > chunk.applied_core_identity.len)
		df_cave_skip_decoration(chunk, record, "missing_core_identity")
		return null
	var/datum/df_cave_core_identity/identity = chunk.applied_core_identity[core_index]
	if(!identity)
		df_cave_skip_decoration(chunk, record, "missing_core_identity")
		return null
	var/x = chunk.cx * DFCP_CORE_SIZE + record.local_x + 1
	var/y = chunk.cy * DFCP_CORE_SIZE + record.local_y + 1
	if(x < 1 || y < 1 || x > world.maxx || y > world.maxy)
		df_cave_skip_decoration(chunk, record, "outside_world")
		return null
	var/turf/T = locate(x, y, chunk.level.z)
	if(!T || T.loc.type != /area/cavesgen)
		df_cave_skip_decoration(chunk, record, "outside_exact_cavesgen")
		return null
	var/datum/df_chunk_cell/cell = chunk.plan.cell_at(record.local_x, record.local_y)
	if(!cell || identity.terrain_path != cell.terrain_path || identity.material_path != cell.material_path || identity.hardness_id != cell.hardness_id)
		df_cave_skip_decoration(chunk, record, "core_identity_mismatch")
		return null
	if(T.type != identity.terrain_path || T.hardness != identity.hardness_id || T.materials != identity.material_path)
		df_cave_skip_decoration(chunk, record, "generated_terrain_mutated")
		return null
	return T

/proc/df_cave_apply_flora_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record, turf/T)
	var/plant_path = record.semantic_path
	var/is_towercap = plant_path == /obj/structure/plant/tree/towercap
	var/is_cave_crop = plant_path == /obj/structure/plant/garden/crop/plump_helmet || plant_path == /obj/structure/plant/garden/crop/pig_tail || plant_path == /obj/structure/plant/garden/crop/cave_wheat
	if(!is_towercap && !is_cave_crop)
		return df_cave_skip_decoration(chunk, record, "flora_semantic_path")
	if(T.type != /turf/open/floor/dirt)
		return df_cave_skip_decoration(chunk, record, "flora_requires_exact_dirt")
	if(is_towercap && (record.arg0 < 1 || record.arg0 > 7 || record.arg1 < -100 || record.arg1 > 600))
		return df_cave_skip_decoration(chunk, record, "towercap_arguments")
	if(is_cave_crop && (record.arg0 < 0 || record.arg0 > 5 || record.arg1 < -180 || record.arg1 > 540))
		return df_cave_skip_decoration(chunk, record, "crop_arguments")
	if(T.is_blocked_turf())
		return df_cave_skip_decoration(chunk, record, "flora_blocked")
	for(var/obj/structure/plant/existing_plant in T)
		return df_cave_skip_decoration(chunk, record, "flora_exists")
	var/obj/structure/plant/plant = new plant_path(T)
	if(!plant || QDELETED(plant) || plant.loc != T)
		return df_cave_skip_decoration(chunk, record, "flora_initialize")
	// Runtime New has already initialized; now reproduce the generated-state
	// lifecycle rather than relying on a later process tick to repair its icon.
	plant.lifespan = INFINITY
	plant.growthdelta += record.arg1
	plant.set_growthstage(record.arg0)
	if(plant.growthstage == plant.growthstages)
		plant.grown()
		if(is_cave_crop)
			// Crops have products, so parent grown() does not stop their runtime
			// processing. A generated mature crop is immediately ripe and inert.
			STOP_PROCESSING(SSplants, plant)
		plant.update_appearance(UPDATE_ICON)
	df_cave_track_decoration_turf(chunk, T)
	plant = null
	return TRUE

/proc/df_cave_apply_fauna_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record, turf/T)
	var/mob_path = record.semantic_path
	if(mob_path != /mob/living/simple_animal/hostile/giant_spider && mob_path != /mob/living/simple_animal/hostile/troll)
		return df_cave_skip_decoration(chunk, record, "fauna_semantic_path")
	if(record.arg0 != 0 || record.arg1 != 0)
		return df_cave_skip_decoration(chunk, record, "fauna_arguments")
	for(var/mob/living/living_occupant in T)
		return df_cave_skip_decoration(chunk, record, "fauna_living_occupant")
	if(!isopenturf(T) || T.is_blocked_turf())
		return df_cave_skip_decoration(chunk, record, "fauna_blocked")
	// This runs only from the subsystem fire on the main thread, so normal New
	// initialization owns AI/action setup exactly as ordinary runtime spawns do.
	var/mob/living/spawned_mob = new mob_path(T)
	if(!spawned_mob || QDELETED(spawned_mob) || spawned_mob.loc != T)
		return df_cave_skip_decoration(chunk, record, "fauna_initialize")
	df_cave_track_decoration_turf(chunk, T)
	spawned_mob = null
	return TRUE

/proc/df_cave_apply_ore_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record, turf/T)
	if(!ispath(record.semantic_path, /obj/item/stack/ore))
		return df_cave_skip_decoration(chunk, record, "ore_semantic_path")
	if(record.arg0 < 1 || record.arg0 > 5 || record.arg1 != 0)
		return df_cave_skip_decoration(chunk, record, "ore_arguments")
	if(!istype(T, /turf/closed/mineral))
		return df_cave_skip_decoration(chunk, record, "ore_requires_mineral")
	var/turf/closed/mineral/mineral_turf = T
	if(mineral_turf.mineralType)
		return df_cave_skip_decoration(chunk, record, "ore_exists")
	// Do not call the old random vein generator: table-v1's semantic path and
	// amount are the entire deterministic ore decision for this record.
	mineral_turf.mineralType = record.semantic_path
	mineral_turf.mineralAmt = record.arg0
	mineral_turf.update_appearance(UPDATE_OVERLAYS)
	df_cave_track_decoration_turf(chunk, mineral_turf)
	return TRUE

/proc/df_cave_apply_troll_rock_decoration(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record, turf/T)
	if(!isnull(record.semantic_path))
		return df_cave_skip_decoration(chunk, record, "troll_rock_semantic_path")
	if(record.arg0 != 0 || record.arg1 != 0)
		return df_cave_skip_decoration(chunk, record, "troll_rock_arguments")
	if(T.type != /turf/closed/mineral/stone)
		return df_cave_skip_decoration(chunk, record, "troll_rock_requires_stone")
	var/turf/closed/mineral/stone/stone_turf = T
	if(stone_turf.has_troll)
		return df_cave_skip_decoration(chunk, record, "troll_rock_exists")
	stone_turf.has_troll = TRUE
	df_cave_track_decoration_turf(chunk, stone_turf)
	return TRUE

/// All semantic resolution comes from the decoder-populated semantic_path. The
/// numeric type ID is intentionally not consulted after decode.
/proc/df_cave_apply_decoration_record(datum/df_cave_chunk/chunk, datum/df_chunk_decoration/record)
	var/turf/T = df_cave_decoration_target(chunk, record)
	if(!T)
		return FALSE
	switch(record.kind)
		if(DFCP_RECORD_FLORA)
			return df_cave_apply_flora_decoration(chunk, record, T)
		if(DFCP_RECORD_FAUNA)
			return df_cave_apply_fauna_decoration(chunk, record, T)
		if(DFCP_RECORD_ORE)
			return df_cave_apply_ore_decoration(chunk, record, T)
		if(DFCP_RECORD_TROLL_ROCK)
			return df_cave_apply_troll_rock_decoration(chunk, record, T)
	return df_cave_skip_decoration(chunk, record, "record_kind")

/datum/controller/subsystem/cave_generation/proc/apply_chunk(datum/df_cave_chunk/chunk)
	if(!chunk.plan)
		quarantine_chunk(chunk, "terrain_plan_missing")
		return
	var/batch_started = REALTIMEOFDAY
	var/batch_tick_started = world.tick_usage
	var/placed_this_batch = 0
	terrain_per_fire = clamp(terrain_per_fire, 8, terrain_batch_max)
	var/limit = min(terrain_per_fire, terrain_batch_max)
	while(chunk.apply_index <= DFCP_CORE_SIZE * DFCP_CORE_SIZE && limit-- > 0)
		var/core_index = chunk.apply_index++
		var/local_index = core_index - 1
		var/lx = local_index % DFCP_CORE_SIZE
		var/ly = df_cave_floor_div(local_index, DFCP_CORE_SIZE)
		var/x = chunk.cx * DFCP_CORE_SIZE + lx + 1
		var/y = chunk.cy * DFCP_CORE_SIZE + ly + 1
		if(x < 1 || y < 1 || x > world.maxx || y > world.maxy)
			continue
		var/turf/T = locate(x, y, chunk.level.z)
		if(!T || T.loc.type != /area/cavesgen)
			continue
		var/datum/df_chunk_cell/cell = chunk.plan.cell_at(lx, ly)
		if(!cell)
			quarantine_chunk(chunk, "terrain_cell_missing")
			return
		if(df_cave_apply_core_turf(chunk, T, cell, core_index))
			placed_this_batch++
		var/turf/current_turf = locate(x, y, chunk.level.z)
		if(current_turf?.loc.type == /area/cavesgen && istype(current_turf, /turf/open/genturf))
			chunk.genturf_remaining++
		if(MC_TICK_CHECK)
			break
	terrain_batches++
	terrain_batch_total += placed_this_batch
	terrain_batch_peak = max(terrain_batch_peak, placed_this_batch)
	var/batch_tick = max(0, world.tick_usage - batch_tick_started)
	var/batch_ms = max(0, (REALTIMEOFDAY - batch_started) * 100)
	terrain_peak_tick_usage = max(terrain_peak_tick_usage, batch_tick)
	terrain_total_ms += batch_ms
	if(placed_this_batch)
		if(batch_tick <= 10)
			terrain_per_fire = min(terrain_batch_max, terrain_per_fire + 8)
		else
			terrain_per_fire = max(8, terrain_per_fire - 4)
	log_world("Deferred cave batch [chunk.level.z] [chunk.cx],[chunk.cy]: [placed_this_batch] cells [batch_ms]ms [batch_tick]% tick")
	if(chunk.apply_index > DFCP_CORE_SIZE * DFCP_CORE_SIZE)
		// Regular ChangeTurf has queued local smoothing as needed, but final
		// queueing is deliberately delayed until every record has been handled.
		chunk.state = DF_CAVE_DECORATING
		log_world("Deferred cave [chunk.level.z] [chunk.cx],[chunk.cy] terrain [chunk.changed] cells genturf_remaining=[chunk.genturf_remaining]; decorating [chunk.plan.decorations.len] records")

/datum/controller/subsystem/cave_generation/proc/queue_final_smoothing(datum/df_cave_chunk/chunk)
	if(!chunk.smooth_targets)
		return TRUE
	while(chunk.smoothing_index <= chunk.smooth_targets.len)
		var/turf/T = chunk.smooth_targets[chunk.smoothing_index++]
		QUEUE_SMOOTH(T)
		QUEUE_SMOOTH_BORDERS(T)
		if(MC_TICK_CHECK)
			return FALSE
	return TRUE

/datum/controller/subsystem/cave_generation/proc/apply_decorations(datum/df_cave_chunk/chunk)
	if(!chunk.plan || !islist(chunk.plan.decorations))
		df_cave_fail_decoration(chunk, null)
		quarantine_chunk(chunk, "decoration_plan_missing")
		return
	var/batch_started = REALTIMEOFDAY
	var/batch_tick_started = world.tick_usage
	var/records_this_batch = 0
	var/applied_this_batch = 0
	decoration_per_fire = clamp(decoration_per_fire, 4, decoration_batch_max)
	var/limit = min(decoration_per_fire, decoration_batch_max)
	while(chunk.decoration_index <= chunk.plan.decorations.len && limit-- > 0)
		var/datum/df_chunk_decoration/record = chunk.plan.decorations[chunk.decoration_index++]
		records_this_batch++
		try
			df_cave_note_decoration_seen(chunk, record)
			if(df_cave_apply_decoration_record(chunk, record))
				df_cave_note_decoration_count(chunk.decoration_applied, record.kind)
				applied_this_batch++
		catch(var/exception/e)
			df_cave_fail_decoration(chunk, record)
			quarantine_chunk(chunk, "decoration [chunk.decoration_index - 1] runtime [e]")
			return
		if(MC_TICK_CHECK)
			break
	if(records_this_batch)
		decoration_batches++
		decoration_batch_total += records_this_batch
		decoration_applied_total += applied_this_batch
		decoration_batch_peak = max(decoration_batch_peak, records_this_batch)
		var/batch_tick = max(0, world.tick_usage - batch_tick_started)
		var/batch_ms = max(0, (REALTIMEOFDAY - batch_started) * 100)
		decoration_peak_tick_usage = max(decoration_peak_tick_usage, batch_tick)
		decoration_total_ms += batch_ms
		if(batch_tick <= 10)
			decoration_per_fire = min(decoration_batch_max, decoration_per_fire + 4)
		else
			decoration_per_fire = max(4, decoration_per_fire - 2)
		log_world("Deferred cave decoration batch [chunk.level.z] [chunk.cx],[chunk.cy]: [records_this_batch] records [applied_this_batch] applied [batch_ms]ms [batch_tick]% tick")
	if(chunk.decoration_index > chunk.plan.decorations.len && queue_final_smoothing(chunk))
		chunk.state = DF_CAVE_SMOOTHING
		log_world("Deferred cave [chunk.level.z] [chunk.cx],[chunk.cy] decorations complete seen=[df_cave_decoration_counts_text(chunk.decoration_seen)] applied=[df_cave_decoration_counts_text(chunk.decoration_applied)] skipped=[chunk.decoration_skip_count] skip_reasons=[df_cave_decoration_skip_reasons_text(chunk)] failed=[chunk.decoration_failure_count]")

/datum/controller/subsystem/cave_generation/proc/finish_smoothing(datum/df_cave_chunk/chunk)
	for(var/atom/A in chunk.smooth_targets)
		if(A.smoothing_flags & (SMOOTH_QUEUED | SMOOTH_B_QUEUED))
			return
	chunk.state = DF_CAVE_LIGHTING

/datum/controller/subsystem/cave_generation/proc/finish_lighting(datum/df_cave_chunk/chunk)
	if(!SSlighting.initialized)
		return
	var/limit = min(terrain_per_fire, terrain_batch_max)
	while(chunk.lighting_index <= chunk.changed_core.len && limit-- > 0)
		var/turf/T = chunk.changed_core[chunk.lighting_index++]
		if(T && T.loc.type == /area/cavesgen && !T.always_lit && !T.lighting_object)
			new/datum/lighting_object(T)
		if(MC_TICK_CHECK)
			return
	if(chunk.lighting_index <= chunk.changed_core.len)
		return
	// Wait only for objects created for this core, never global queues.
	for(var/turf/T in chunk.changed_core)
		if(T?.lighting_object?.needs_update)
			return
	// Keep the decoded plan and applied integer mask through decoration,
	// smoothing, and lighting; this is the first safe point to release them.
	chunk.plan = null
	chunk.request = null
	chunk.applied_core_mask = null
	chunk.applied_core_identity = null
	chunk.smooth_targets = null
	chunk.changed_core = null
	chunk.state = DF_CAVE_COMPLETE
	log_world("Deferred cave [chunk.level.z] [chunk.cx],[chunk.cy] complete [chunk.changed] terrain decorations seen=[df_cave_decoration_counts_text(chunk.decoration_seen)] applied=[df_cave_decoration_counts_text(chunk.decoration_applied)] skipped=[chunk.decoration_skip_count] skip_reasons=[df_cave_decoration_skip_reasons_text(chunk)] failed=[chunk.decoration_failure_count]")

/datum/controller/subsystem/cave_generation/fire()
	if(!committed || !Master.current_runlevel)
		return
	request_proximity()
	var/datum/df_cave_chunk/queued = best_chunk(DF_CAVE_QUEUED)
	if(queued)
		submit_chunk(queued)
	var/datum/df_cave_chunk/applying = best_chunk(DF_CAVE_APPLYING_TERRAIN)
	var/datum/df_cave_chunk/decorating = select_decoration_chunk()
	// One map-mutating batch per fire. A completed terrain core gets its
	// selected decoration work on equal priority too, preventing a prewarm
	// terrain backlog from starving the DECORATING state.
	if(decorating && (!applying || decorating.priority >= applying.priority))
		apply_decorations(decorating)
	else if(applying)
		apply_chunk(applying)
	for(var/level_key in levels)
		var/datum/df_cave_level/level = levels[level_key]
		for(var/chunk_key in level.chunks)
			var/datum/df_cave_chunk/chunk = level.chunks[chunk_key]
			if(chunk.state == DF_CAVE_INERT && !chunk.quarantined && chunk.retries && world.time >= chunk.retry_at)
				chunk.state = DF_CAVE_QUEUED
			switch(chunk.state)
				if(DF_CAVE_QUEUED)
					continue
				if(DF_CAVE_PLANNING)
					poll_chunk(chunk)
				if(DF_CAVE_APPLYING_TERRAIN, DF_CAVE_DECORATING)
					continue
				if(DF_CAVE_SMOOTHING)
					finish_smoothing(chunk)
				if(DF_CAVE_LIGHTING)
					finish_lighting(chunk)
			if(MC_TICK_CHECK)
				return

/datum/controller/subsystem/cave_generation/Shutdown()
	// Forget native jobs only. Plans, cursors, masks, and scalar decoration
	// counts stay attached to chunks for safe controller recovery.
	for(var/level_key in levels)
		var/datum/df_cave_level/level = levels[level_key]
		for(var/chunk_key in level.chunks)
			forget_job(level.chunks[chunk_key])
	return ..()

/// Master stores a one-based runlevel index, not the RUNLEVEL_* bit value.
/proc/deferred_cave_gate_runlevel()
	return Master?.current_runlevel == 1 || Master?.current_runlevel == 3

/// Central fail-closed access predicate. It is intentionally cheap while the
/// feature is disabled or before gameplay begins.
/proc/deferred_cave_access_allowed(atom/movable/mover, turf/target)
	if(!SScave_generation?.committed || !Master?.current_runlevel || !target || target.loc.type != /area/cavesgen)
		return TRUE
	if(!deferred_cave_gate_runlevel())
		return TRUE
	if(istype(mover, /mob/dead/observer))
		return TRUE
	var/datum/df_cave_chunk/chunk = SScave_generation.chunk_for_turf(target, TRUE)
	if(chunk)
		chunk.priority = DF_CAVE_PRIORITY_DIRECT
	return chunk?.state == DF_CAVE_COMPLETE
