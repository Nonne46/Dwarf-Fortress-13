// B2c applies only against temporary reservation turfs moved into an exact
// /area/cavesgen instance. These tests must never borrow production cave cells.

/obj/structure/df_cave_decoration_test_blocker
	anchored = TRUE
	density = TRUE

/proc/df_cave_decoration_test_copy(value)
	if(!islist(value))
		return value
	var/list/value_list = value
	return value_list.Copy()

/proc/df_cave_decoration_test_values_equal(first, second)
	if(islist(first) || islist(second))
		if(!islist(first) || !islist(second))
			return FALSE
		var/list/first_list = first
		var/list/second_list = second
		if(first_list.len != second_list.len)
			return FALSE
		for(var/index in 1 to first_list.len)
			if(!df_cave_decoration_test_values_equal(first_list[index], second_list[index]))
				return FALSE
		return TRUE
	return first == second

/datum/df_cave_decoration_test_snapshot
	var/x
	var/y
	var/z
	var/turf_type
	var/area/original_area
	var/baseturfs
	var/baseturf_materials
	var/materials
	var/init_materials
	var/hardness
	var/always_lit
	var/list/original_contents
	var/smoothing_flags
	var/normal_queued
	var/border_queued
	var/deferred_queued
	var/blueprint_queued
	var/datum/lighting_object/original_lighting_object
	var/lighting_present
	var/lighting_needs_update
	var/lighting_queued
	var/mutated = FALSE

/datum/df_cave_decoration_test_fixture
	var/area/cavesgen/cave_area
	/// Snapshots include a one-turf halo because regular ChangeTurf queues neighbors.
	var/list/snapshots = list()
	var/list/snapshot_keys = list()
	var/cleaned = FALSE

/datum/df_cave_decoration_test_fixture/New(datum/unit_test/test, move_all = TRUE)
	. = ..()
	for(var/turf/T in block(locate(max(1, test.run_loc_floor_bottom_left.x - 1), max(1, test.run_loc_floor_bottom_left.y - 1), test.run_loc_floor_bottom_left.z), locate(min(world.maxx, test.run_loc_floor_top_right.x + 1), min(world.maxy, test.run_loc_floor_top_right.y + 1), test.run_loc_floor_top_right.z)))
		capture(T)
	cave_area = new
	cave_area.static_lighting = FALSE
	if(move_all)
		for(var/turf/T in block(test.run_loc_floor_bottom_left, test.run_loc_floor_top_right))
			move_turf(T)

/datum/df_cave_decoration_test_fixture/proc/capture(turf/T)
	if(!T)
		return null
	var/key = "[T.x],[T.y],[T.z]"
	var/datum/df_cave_decoration_test_snapshot/snapshot = snapshots[key]
	if(snapshot)
		return snapshot
	snapshot = new
	snapshot.x = T.x
	snapshot.y = T.y
	snapshot.z = T.z
	snapshot.turf_type = T.type
	snapshot.original_area = T.loc
	snapshot.baseturfs = df_cave_decoration_test_copy(T.baseturfs)
	snapshot.baseturf_materials = df_cave_decoration_test_copy(T.baseturf_materials)
	snapshot.materials = df_cave_decoration_test_copy(T.materials)
	snapshot.init_materials = T.init_materials
	snapshot.hardness = T.hardness
	snapshot.always_lit = T.always_lit
	snapshot.original_contents = T.contents.Copy()
	snapshot.smoothing_flags = T.smoothing_flags
	snapshot.normal_queued = SSicon_smooth.smooth_queue.Find(T)
	snapshot.border_queued = SSicon_smooth.smooth_borders_queue.Find(T)
	snapshot.deferred_queued = SSicon_smooth.deferred.Find(T)
	snapshot.blueprint_queued = SSicon_smooth.blueprint_queue.Find(T)
	snapshot.original_lighting_object = T.lighting_object
	snapshot.lighting_present = !!T.lighting_object
	snapshot.lighting_needs_update = T.lighting_object?.needs_update
	snapshot.lighting_queued = T.lighting_object && SSlighting.objects_queue.Find(T.lighting_object)
	snapshots[key] = snapshot
	snapshot_keys += key
	return snapshot

/datum/df_cave_decoration_test_fixture/proc/move_turf(turf/T)
	if(!T || cleaned)
		return T
	var/datum/df_cave_decoration_test_snapshot/snapshot = capture(T)
	if(T.loc == cave_area)
		return T
	snapshot.mutated = TRUE
	var/area/original_area = T.loc
	cave_area.contents += T
	T.change_area(original_area, cave_area)
	return T

/datum/df_cave_decoration_test_fixture/proc/remove_created_contents(turf/T, datum/df_cave_decoration_test_snapshot/snapshot)
	if(!T || !snapshot)
		return
	for(var/atom/movable/content in T)
		if(snapshot.original_contents.Find(content))
			continue
		if(istype(content, /obj/structure/plant))
			STOP_PROCESSING(SSplants, content)
		qdel(content, TRUE)

/datum/df_cave_decoration_test_fixture/proc/restore_turf(datum/df_cave_decoration_test_snapshot/snapshot)
	var/turf/T = locate(snapshot.x, snapshot.y, snapshot.z)
	if(!T)
		return FALSE
	remove_created_contents(T, snapshot)
	if(snapshot.mutated)
		T = T.ChangeTurf(snapshot.turf_type, df_cave_decoration_test_copy(snapshot.baseturfs), df_cave_decoration_test_copy(snapshot.baseturf_materials), CHANGETURF_FORCEOP, df_cave_decoration_test_copy(snapshot.materials))
		T.baseturfs = df_cave_decoration_test_copy(snapshot.baseturfs)
		T.baseturf_materials = df_cave_decoration_test_copy(snapshot.baseturf_materials)
		T.assemble_baseturfs()
		T.materials = df_cave_decoration_test_copy(snapshot.materials)
		T.init_materials = snapshot.init_materials
		T.set_hardness(snapshot.hardness)
		T.always_lit = snapshot.always_lit
		if(T.always_lit)
			T.add_overlay(GLOB.fullbright_overlay)
		else
			T.cut_overlay(GLOB.fullbright_overlay)
		if(T.loc != snapshot.original_area)
			var/area/current_area = T.loc
			snapshot.original_area.contents += T
			T.change_area(current_area, snapshot.original_area)
	for(var/atom/movable/original_content in snapshot.original_contents)
		if(!QDELETED(original_content) && original_content.loc != T)
			original_content.forceMove(T)
	return TRUE

/datum/df_cave_decoration_test_fixture/proc/restore_queues_and_lighting(datum/df_cave_decoration_test_snapshot/snapshot)
	var/turf/T = locate(snapshot.x, snapshot.y, snapshot.z)
	if(!T)
		return FALSE
	SSicon_smooth.remove_from_queues(T)
	T.smoothing_flags = snapshot.smoothing_flags
	if(snapshot.normal_queued)
		SSicon_smooth.smooth_queue += T
	if(snapshot.border_queued)
		SSicon_smooth.smooth_borders_queue += T
	if(snapshot.deferred_queued)
		SSicon_smooth.deferred += T
	if(snapshot.blueprint_queued)
		SSicon_smooth.blueprint_queue += T
	var/datum/lighting_object/current_lighting = T.lighting_object
	if(snapshot.lighting_present && current_lighting == snapshot.original_lighting_object && !QDELETED(current_lighting))
		current_lighting.needs_update = snapshot.lighting_needs_update
		if(snapshot.lighting_queued)
			if(!SSlighting.objects_queue.Find(current_lighting))
				SSlighting.objects_queue += current_lighting
		else
			SSlighting.objects_queue -= current_lighting
	else
		if(current_lighting)
			qdel(current_lighting, TRUE)
		if(snapshot.lighting_present)
			current_lighting = new/datum/lighting_object(T)
			current_lighting.needs_update = snapshot.lighting_needs_update
			if(!snapshot.lighting_queued)
				SSlighting.objects_queue -= current_lighting
	return TRUE

/datum/df_cave_decoration_test_fixture/proc/cleanup()
	if(cleaned)
		return TRUE
	for(var/key in snapshot_keys)
		var/datum/df_cave_decoration_test_snapshot/snapshot = snapshots[key]
		var/turf/T = locate(snapshot.x, snapshot.y, snapshot.z)
		remove_created_contents(T, snapshot)
	for(var/key in snapshot_keys)
		var/datum/df_cave_decoration_test_snapshot/snapshot = snapshots[key]
		if(snapshot.mutated)
			restore_turf(snapshot)
	for(var/key in snapshot_keys)
		restore_queues_and_lighting(snapshots[key])
	if(cave_area)
		qdel(cave_area, TRUE)
		cave_area = null
	cleaned = TRUE
	return TRUE

/datum/df_cave_decoration_test_fixture/proc/is_restored()
	for(var/key in snapshot_keys)
		var/datum/df_cave_decoration_test_snapshot/snapshot = snapshots[key]
		var/turf/T = locate(snapshot.x, snapshot.y, snapshot.z)
		if(!T || T.type != snapshot.turf_type || T.loc != snapshot.original_area || T.hardness != snapshot.hardness || T.always_lit != snapshot.always_lit)
			return FALSE
		if(!df_cave_decoration_test_values_equal(T.baseturfs, snapshot.baseturfs) || !df_cave_decoration_test_values_equal(T.baseturf_materials, snapshot.baseturf_materials) || !df_cave_decoration_test_values_equal(T.materials, snapshot.materials))
			return FALSE
		if(T.smoothing_flags != snapshot.smoothing_flags || !!SSicon_smooth.smooth_queue.Find(T) != !!snapshot.normal_queued || !!SSicon_smooth.smooth_borders_queue.Find(T) != !!snapshot.border_queued || !!SSicon_smooth.deferred.Find(T) != !!snapshot.deferred_queued || !!SSicon_smooth.blueprint_queue.Find(T) != !!snapshot.blueprint_queued)
			return FALSE
		if(!!T.lighting_object != !!snapshot.lighting_present || (T.lighting_object && (!!T.lighting_object.needs_update != !!snapshot.lighting_needs_update || !!SSlighting.objects_queue.Find(T.lighting_object) != !!snapshot.lighting_queued)))
			return FALSE
		for(var/atom/movable/content in T)
			if(!snapshot.original_contents.Find(content))
				return FALSE
		for(var/atom/movable/original_content in snapshot.original_contents)
			if(QDELETED(original_content) || original_content.loc != T)
				return FALSE
	for(var/obj/structure/plant/plant in SSplants.processing)
		var/turf/plant_turf = get_turf(plant)
		if(!plant_turf)
			continue
		var/datum/df_cave_decoration_test_snapshot/snapshot = snapshots["[plant_turf.x],[plant_turf.y],[plant_turf.z]"]
		if(snapshot && !snapshot.original_contents.Find(plant))
			return FALSE
	return TRUE

/datum/df_cave_decoration_test_target
	var/turf/turf
	var/datum/df_cave_chunk/chunk
	var/datum/df_chunk_cell/cell
	var/local_x
	var/local_y
	var/core_index

/proc/df_cave_decoration_test_prepare(turf/T, terrain_path, material_path = null, hardness_id = 0, mark_applied = TRUE)
	var/datum/df_cave_decoration_test_target/result = new
	T = T.ChangeTurf(terrain_path, null, null, NONE, material_path)
	T.set_hardness(hardness_id)
	result.turf = T
	result.local_x = (T.x - 1) % DFCP_CORE_SIZE
	result.local_y = (T.y - 1) % DFCP_CORE_SIZE
	result.core_index = result.local_y * DFCP_CORE_SIZE + result.local_x + 1
	var/datum/df_cave_level/level = new
	level.z = T.z
	level.profile_id = max(1, hardness_id)
	var/datum/df_cave_chunk/chunk = new
	chunk.level = level
	chunk.cx = df_cave_floor_div(T.x - 1, DFCP_CORE_SIZE)
	chunk.cy = df_cave_floor_div(T.y - 1, DFCP_CORE_SIZE)
	chunk.smooth_targets = list()
	chunk.changed_core = list()
	var/datum/df_chunk_cell/cell = new
	cell.terrain_path = terrain_path
	cell.material_path = material_path
	cell.hardness_id = hardness_id
	var/datum/df_chunk_plan/plan = new
	plan.cells = list()
	var/cell_index = (result.local_y + DFCP_HALO_SIZE) * DFCP_EXTENDED_SIZE + result.local_x + DFCP_HALO_SIZE + 1
	plan.cells.len = cell_index
	plan.cells[cell_index] = cell
	plan.decorations = list()
	chunk.plan = plan
	if(mark_applied)
		df_cave_mark_applied_core(chunk, result.core_index, cell)
	result.chunk = chunk
	result.cell = cell
	return result

/proc/df_cave_decoration_test_record(kind, datum/df_cave_decoration_test_target/target, semantic_path, arg0 = 0, arg1 = 0)
	var/datum/df_chunk_decoration/record = new
	record.kind = kind
	record.local_x = target.local_x
	record.local_y = target.local_y
	record.semantic_path = semantic_path
	record.arg0 = arg0
	record.arg1 = arg1
	return record

/proc/df_cave_decoration_test_plant(turf/T)
	for(var/obj/structure/plant/plant in T)
		return plant
	return null

/proc/df_cave_decoration_test_mob(turf/T)
	for(var/mob/living/mob in T)
		return mob
	return null

/datum/unit_test/deferred_cave_decorations
	var/datum/df_cave_decoration_test_fixture/fixture
	var/old_decoration_per_fire
	var/old_decoration_batch_max

/datum/unit_test/deferred_cave_decorations/Destroy()
	if(!isnull(old_decoration_per_fire))
		SScave_generation.decoration_per_fire = old_decoration_per_fire
		SScave_generation.decoration_batch_max = old_decoration_batch_max
	if(fixture)
		fixture.cleanup()
		fixture = null
	return ..()

/datum/unit_test/deferred_cave_decorations/Run()
	var/list/bad_initialize_before = SSatoms.BadInitializeCalls.Copy()
	fixture = new(src)
	TEST_ASSERT(fixture.cave_area && fixture.cave_area.type == /area/cavesgen, "temporary fixture is an exact cavesgen area")
	TEST_ASSERT_EQUAL(run_loc_floor_bottom_left.loc, fixture.cave_area, "reservation fixture, not a production cave cell, is moved into cavesgen")

	// All flora semantic paths, both argument endpoints, immediate lifecycle,
	// mature processing behavior, tree density, and valid icon state.
	var/list/flora_specs = list(
		list(/obj/structure/plant/tree/towercap, 1, -100, 800),
		list(/obj/structure/plant/tree/towercap, 7, 600, 800),
		list(/obj/structure/plant/garden/crop/plump_helmet, 0, -180, 900),
		list(/obj/structure/plant/garden/crop/plump_helmet, 5, 540, 900),
		list(/obj/structure/plant/garden/crop/pig_tail, 0, -180, 900),
		list(/obj/structure/plant/garden/crop/pig_tail, 5, 540, 900),
		list(/obj/structure/plant/garden/crop/cave_wheat, 0, -180, 900),
		list(/obj/structure/plant/garden/crop/cave_wheat, 5, 540, 900)
	)
	var/spec_index = 0
	for(var/list/spec in flora_specs)
		spec_index++
		var/turf/T = locate(run_loc_floor_bottom_left.x + ((spec_index - 1) % 5), run_loc_floor_bottom_left.y + df_cave_floor_div(spec_index - 1, 5), run_loc_floor_bottom_left.z)
		var/datum/df_cave_decoration_test_target/target = df_cave_decoration_test_prepare(T, /turf/open/floor/dirt)
		var/plant_path = spec[1]
		var/stage = spec[2]
		var/growth_adjustment = spec[3]
		var/base_growthdelta = spec[4]
		var/datum/df_chunk_decoration/record = df_cave_decoration_test_record(DFCP_RECORD_FLORA, target, plant_path, stage, growth_adjustment)
		TEST_ASSERT(df_cave_apply_decoration_record(target.chunk, record), "flora semantic path [plant_path] applies")
		var/obj/structure/plant/plant = df_cave_decoration_test_plant(target.turf)
		TEST_ASSERT(plant && plant.type == plant_path, "flora instance uses decoded semantic path")
		TEST_ASSERT_EQUAL(plant.lifespan, INFINITY, "generated flora lifespan is infinite")
		TEST_ASSERT_EQUAL(plant.growthstage, stage, "flora stage endpoint")
		TEST_ASSERT_EQUAL(plant.growthdelta, base_growthdelta + growth_adjustment, "flora growthdelta endpoint")
		if(plant_path == /obj/structure/plant/tree/towercap)
			var/obj/structure/plant/tree/towercap = plant
			TEST_ASSERT_EQUAL(towercap.density, stage > 3, "towercap density follows runtime stage")
			if(stage == 7)
				TEST_ASSERT_EQUAL(towercap.icon_state, "towercap-7", "mature towercap icon is valid")
				TEST_ASSERT(!(towercap.datum_flags & DF_ISPROCESSING), "mature towercap is not left processing")
		else if(stage == 5)
			TEST_ASSERT(plant.harvestable, "mature cave crop is immediately harvestable")
			TEST_ASSERT(!(plant.datum_flags & DF_ISPROCESSING), "mature cave crop is not left processing")
		qdel(plant, TRUE)
		TEST_ASSERT(!SSplants.processing.Find(plant), "flora qdel releases plant processing")

	// A dense setup mutation and a preserved non-genturf both deterministically
	// skip records instead of creating a duplicate or reconstructing terrain.
	var/turf/blocked_turf = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/blocked_target = df_cave_decoration_test_prepare(blocked_turf, /turf/open/floor/dirt)
	var/obj/structure/df_cave_decoration_test_blocker/blocker = new(blocked_target.turf)
	var/datum/df_chunk_decoration/blocked_flora = df_cave_decoration_test_record(DFCP_RECORD_FLORA, blocked_target, /obj/structure/plant/tree/towercap, 1, 0)
	TEST_ASSERT(!df_cave_apply_decoration_record(blocked_target.chunk, blocked_flora), "blocked dirt does not gain a duplicate plant")
	TEST_ASSERT(!df_cave_decoration_test_plant(blocked_target.turf), "blocked target remains plant-free")
	qdel(blocker, TRUE)

	var/turf/preserved_turf = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/preserved_target = df_cave_decoration_test_prepare(preserved_turf, /turf/open/floor/dirt, null, 0, FALSE)
	TEST_ASSERT(!df_cave_apply_core_turf(preserved_target.chunk, preserved_target.turf, preserved_target.cell, preserved_target.core_index), "non-genturf fixture is preserved")
	var/datum/df_chunk_decoration/preserved_flora = df_cave_decoration_test_record(DFCP_RECORD_FLORA, preserved_target, /obj/structure/plant/garden/crop/plump_helmet, 0, 0)
	TEST_ASSERT(!df_cave_apply_decoration_record(preserved_target.chunk, preserved_flora), "preserved core never receives a decoration")
	TEST_ASSERT(!df_cave_decoration_test_plant(preserved_target.turf), "preserved target has no duplicate plant")

	// Both fauna paths initialize normally on the main thread and clean up.
	var/turf/spider_turf = locate(run_loc_floor_bottom_left.x, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/spider_target = df_cave_decoration_test_prepare(spider_turf, /turf/open/floor/dirt)
	var/datum/df_chunk_decoration/spider_record = df_cave_decoration_test_record(DFCP_RECORD_FAUNA, spider_target, /mob/living/simple_animal/hostile/giant_spider)
	TEST_ASSERT(df_cave_apply_decoration_record(spider_target.chunk, spider_record), "giant spider applies on open generated turf")
	var/mob/living/spider = df_cave_decoration_test_mob(spider_target.turf)
	TEST_ASSERT(istype(spider, /mob/living/simple_animal/hostile/giant_spider), "giant spider initialized")
	qdel(spider, TRUE)
	TEST_ASSERT(QDELETED(spider), "giant spider cleanup")

	var/turf/troll_turf = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/troll_target = df_cave_decoration_test_prepare(troll_turf, /turf/open/floor/dirt)
	var/datum/df_chunk_decoration/troll_record = df_cave_decoration_test_record(DFCP_RECORD_FAUNA, troll_target, /mob/living/simple_animal/hostile/troll)
	TEST_ASSERT(df_cave_apply_decoration_record(troll_target.chunk, troll_record), "troll applies on open generated turf")
	var/mob/living/troll = df_cave_decoration_test_mob(troll_target.turf)
	TEST_ASSERT(istype(troll, /mob/living/simple_animal/hostile/troll), "troll initialized")
	qdel(troll, TRUE)
	TEST_ASSERT(QDELETED(troll), "troll cleanup")

	var/turf/mutated_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/mutated_target = df_cave_decoration_test_prepare(mutated_turf, /turf/open/floor/dirt)
	mutated_target.turf = mutated_target.turf.ChangeTurf(/turf/open/floor/rock)
	var/datum/df_chunk_decoration/mutated_fauna = df_cave_decoration_test_record(DFCP_RECORD_FAUNA, mutated_target, /mob/living/simple_animal/hostile/troll)
	TEST_ASSERT(!df_cave_apply_decoration_record(mutated_target.chunk, mutated_fauna), "mutated generated terrain skips fauna")
	TEST_ASSERT(!df_cave_decoration_test_mob(mutated_target.turf), "mutated target has no fauna")

	// Every table-v1 ore semantic path uses direct mineral fields, including both
	// amount endpoints. Troll-rock then coexists with an ore on the same wall.
	var/list/ore_paths = list(
		/obj/item/stack/ore/smeltable/gold,
		/obj/item/stack/ore/smeltable/iron,
		/obj/item/stack/ore/gem/diamond,
		/obj/item/stack/ore/gem/ruby,
		/obj/item/stack/ore/gem/sapphire,
		/obj/item/stack/ore/coal,
		/obj/item/stack/ore/smeltable/copper,
		/obj/item/stack/ore/smeltable/cassiterite,
		/obj/item/stack/ore/smeltable/aluminum,
		/obj/item/stack/ore/smeltable/galena,
		/obj/item/stack/ore/smeltable/silver,
		/obj/item/stack/ore/smeltable/platinum,
		/obj/item/stack/ore/smeltable/adamantine
	)
	var/ore_index = 0
	for(var/ore_path in ore_paths)
		ore_index++
		var/turf/ore_turf = locate(run_loc_floor_bottom_left.x + (ore_index % 5), run_loc_floor_bottom_left.y + 4, run_loc_floor_bottom_left.z)
		var/datum/df_cave_decoration_test_target/ore_target = df_cave_decoration_test_prepare(ore_turf, /turf/closed/mineral/stone, /datum/material/stone, 1)
		var/ore_amount = ore_index % 2 ? 1 : 5
		var/datum/df_chunk_decoration/ore_record = df_cave_decoration_test_record(DFCP_RECORD_ORE, ore_target, ore_path, ore_amount)
		TEST_ASSERT(df_cave_apply_decoration_record(ore_target.chunk, ore_record), "ore semantic path [ore_path] applies directly")
		var/turf/closed/mineral/mineral_turf = ore_target.turf
		TEST_ASSERT_EQUAL(mineral_turf.mineralType, ore_path, "ore path survives application")
		TEST_ASSERT_EQUAL(mineral_turf.mineralAmt, ore_amount, "ore amount endpoint survives application")
		TEST_ASSERT(ore_target.chunk.smooth_targets.Find(mineral_turf), "ore refresh is included in final smoothing")

	var/turf/coexist_turf = locate(run_loc_floor_bottom_left.x + 4, run_loc_floor_bottom_left.y + 4, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/coexist_target = df_cave_decoration_test_prepare(coexist_turf, /turf/closed/mineral/stone, /datum/material/stone, 1)
	var/datum/df_chunk_decoration/coexist_ore = df_cave_decoration_test_record(DFCP_RECORD_ORE, coexist_target, /obj/item/stack/ore/smeltable/gold, 5)
	var/datum/df_chunk_decoration/coexist_troll = df_cave_decoration_test_record(DFCP_RECORD_TROLL_ROCK, coexist_target, null)
	TEST_ASSERT(df_cave_apply_decoration_record(coexist_target.chunk, coexist_ore), "ore applies before troll-rock")
	TEST_ASSERT(df_cave_apply_decoration_record(coexist_target.chunk, coexist_troll), "troll-rock coexists with ore")
	var/turf/closed/mineral/stone/coexist_wall = coexist_target.turf
	TEST_ASSERT_EQUAL(coexist_wall.mineralType, /obj/item/stack/ore/smeltable/gold, "coexisting ore is retained")
	TEST_ASSERT(coexist_wall.has_troll, "coexisting troll-rock flag is retained")

	// Exact-area and physical-edge guards happen before any record mutation.
	var/turf/area_guard_turf = locate(run_loc_floor_bottom_left.x + 3, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/area_guard_target = df_cave_decoration_test_prepare(area_guard_turf, /turf/open/floor/dirt)
	var/area/fortress/temporary_fortress = new
	temporary_fortress.contents += area_guard_target.turf
	area_guard_target.turf.change_area(fixture.cave_area, temporary_fortress)
	var/datum/df_chunk_decoration/area_guard_record = df_cave_decoration_test_record(DFCP_RECORD_FLORA, area_guard_target, /obj/structure/plant/tree/towercap, 1, 0)
	TEST_ASSERT(!df_cave_apply_decoration_record(area_guard_target.chunk, area_guard_record), "fortress-area target is never decorated")
	fixture.cave_area.contents += area_guard_target.turf
	area_guard_target.turf.change_area(temporary_fortress, fixture.cave_area)
	qdel(temporary_fortress)

	var/datum/df_cave_level/edge_level = new
	edge_level.z = run_loc_floor_bottom_left.z
	edge_level.profile_id = 1
	var/datum/df_cave_chunk/edge_chunk = new
	edge_chunk.level = edge_level
	edge_chunk.cx = df_cave_floor_div(world.maxx - 1, DFCP_CORE_SIZE) + 1
	edge_chunk.cy = 0
	var/datum/df_chunk_cell/edge_cell = new
	edge_cell.terrain_path = /turf/open/floor/dirt
	edge_cell.hardness_id = 0
	var/datum/df_chunk_plan/edge_plan = new
	edge_plan.cells = list()
	var/edge_cell_index = (DFCP_HALO_SIZE * DFCP_EXTENDED_SIZE) + DFCP_HALO_SIZE + 1
	edge_plan.cells.len = edge_cell_index
	edge_plan.cells[edge_cell_index] = edge_cell
	edge_plan.decorations = list()
	edge_chunk.plan = edge_plan
	df_cave_mark_applied_core(edge_chunk, 1, edge_cell)
	var/datum/df_chunk_decoration/edge_record = new
	edge_record.kind = DFCP_RECORD_FLORA
	edge_record.local_x = 0
	edge_record.local_y = 0
	edge_record.semantic_path = /obj/structure/plant/tree/towercap
	edge_record.arg0 = 1
	TEST_ASSERT(!df_cave_apply_decoration_record(edge_chunk, edge_record), "partial/out-of-world core target is skipped")

	// Terrain cannot enter smoothing early. Empty decoration records then queue
	// final smoothing, while a nine-record plan demonstrates cursor batches.
	var/turf/barrier_turf = locate(run_loc_floor_bottom_left.x + 3, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/barrier_target = df_cave_decoration_test_prepare(barrier_turf, /turf/closed/mineral/stone, /datum/material/stone, 1)
	barrier_target.chunk.apply_index = DFCP_CORE_SIZE * DFCP_CORE_SIZE + 1
	barrier_target.chunk.state = DF_CAVE_APPLYING_TERRAIN
	SSicon_smooth.remove_from_queues(barrier_target.turf)
	SScave_generation.apply_chunk(barrier_target.chunk)
	TEST_ASSERT_EQUAL(barrier_target.chunk.state, DF_CAVE_DECORATING, "terrain completion enters DECORATING before final smoothing")
	TEST_ASSERT(!(barrier_target.turf.smoothing_flags & (SMOOTH_QUEUED | SMOOTH_B_QUEUED)), "terrain completion does not explicitly queue final smoothing")
	for(var/barrier_attempt in 1 to 10)
		if(barrier_target.chunk.state != DF_CAVE_DECORATING)
			break
		SScave_generation.apply_decorations(barrier_target.chunk)
	TEST_ASSERT_EQUAL(barrier_target.chunk.state, DF_CAVE_SMOOTHING, "empty decoration completion enters smoothing")
	SSicon_smooth.remove_from_queues(barrier_target.turf)

	var/turf/cursor_turf = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/datum/df_cave_decoration_test_target/cursor_target = df_cave_decoration_test_prepare(cursor_turf, /turf/open/floor/dirt)
	for(var/record_number in 1 to 9)
		cursor_target.chunk.plan.decorations += df_cave_decoration_test_record(DFCP_RECORD_FLORA, cursor_target, /obj/structure/plant/tree/towercap, 1, 0)
	cursor_target.chunk.state = DF_CAVE_DECORATING
	old_decoration_per_fire = SScave_generation.decoration_per_fire
	old_decoration_batch_max = SScave_generation.decoration_batch_max
	SScave_generation.decoration_per_fire = 8
	SScave_generation.decoration_batch_max = 32
	SScave_generation.apply_decorations(cursor_target.chunk)
	TEST_ASSERT(cursor_target.chunk.decoration_index > 1, "decoration cursor advances incrementally")
	TEST_ASSERT(cursor_target.chunk.decoration_index <= cursor_target.chunk.plan.decorations.len + 1, "decoration cursor never exceeds plan bounds")
	for(var/attempt in 1 to 64)
		if(cursor_target.chunk.state != DF_CAVE_DECORATING)
			break
		SScave_generation.apply_decorations(cursor_target.chunk)
	TEST_ASSERT_EQUAL(cursor_target.chunk.state, DF_CAVE_SMOOTHING, "all decoration batches finish before smoothing")
	var/obj/structure/plant/cursor_plant = df_cave_decoration_test_plant(cursor_target.turf)
	qdel(cursor_plant, TRUE)
	SSicon_smooth.remove_from_queues(cursor_target.turf)

	for(var/bad_type in SSatoms.BadInitializeCalls)
		TEST_ASSERT_EQUAL(SSatoms.BadInitializeCalls[bad_type], bad_initialize_before[bad_type], "decoration fixtures add no BadInitializeCalls ([bad_type])")
	TEST_ASSERT(fixture.cleanup(), "decoration fixture cleanup completed")
	TEST_ASSERT(fixture.is_restored(), "decoration fixture restored turfs, contents, queues, and lighting")
	fixture = null

// Finds a native record which lands in the ordinary isolated five-by-five
// unit-test reservation, then applies that real BOTH-frame record in place.
/datum/unit_test/deferred_cave_native_decoration_smoke
	var/datum/df_cave_decoration_test_fixture/fixture
	var/turf/native_turf

/datum/unit_test/deferred_cave_native_decoration_smoke/Destroy()
	if(fixture)
		fixture.cleanup()
		fixture = null
	return ..()

/datum/unit_test/deferred_cave_native_decoration_smoke/Run()
	var/capabilities = df_chunk_capabilities()
	if(capabilities == _df_chunk_error(503, "dflib_unavailable"))
		log_test("B2c native BOTH application smoke skipped: [capabilities]")
		return
	TEST_ASSERT_EQUAL(capabilities, DFCP_CAPABILITIES, "native BOTH application requires the compatible DFLib")
	fixture = new(src, FALSE)
	var/bottom_x = run_loc_floor_bottom_left.x
	var/bottom_y = run_loc_floor_bottom_left.y
	var/top_x = run_loc_floor_top_right.x
	var/top_y = run_loc_floor_top_right.y
	var/chunk_x = df_cave_floor_div(bottom_x - 1, DFCP_CORE_SIZE)
	var/chunk_y = df_cave_floor_div(bottom_y - 1, DFCP_CORE_SIZE)
	var/list/seeds = list("0123456789abcdef", "fedcba9876543210", "0011223344556677", "8899aabbccddeeff", "13579bdf2468ace0", "0eca8642fdb97531", "deadbeefcafebabe", "facefeed12345678")
	var/datum/df_chunk_decode_result/decoded
	var/datum/df_chunk_decoration/record
	for(var/seed in seeds)
		var/list/errors = list()
		var/datum/df_chunk_request/request = df_chunk_request_from_wire("1", "1", "1", seed, "1", "[chunk_x]", "[chunk_y]", "-1", "3", errors)
		if(!request)
			continue
		var/native_frame = df_chunk_plan(1, 1, 1, seed, 1, "[chunk_x]", "[chunk_y]", "-1", 3)
		if(!_df_chunk_has_prefix(native_frame, DFCP_PLAN_PREFIX))
			continue
		decoded = df_chunk_decode_plan(native_frame, request)
		if(!decoded?.succeeded())
			continue
		for(var/datum/df_chunk_decoration/candidate in decoded.plan.decorations)
			var/target_x = chunk_x * DFCP_CORE_SIZE + candidate.local_x + 1
			var/target_y = chunk_y * DFCP_CORE_SIZE + candidate.local_y + 1
			if(target_x >= bottom_x && target_x <= top_x && target_y >= bottom_y && target_y <= top_y)
				record = candidate
				break
		if(record)
			break
	TEST_ASSERT(decoded?.succeeded(), "native BOTH smoke decoded a canonical frame")
	TEST_ASSERT_EQUAL(decoded.plan.sections, DFCP_SECTION_BOTH, "native smoke preserves BOTH sections")
	TEST_ASSERT(record, "one deterministic native record lands in the isolated test area")
	var/target_x = chunk_x * DFCP_CORE_SIZE + record.local_x + 1
	var/target_y = chunk_y * DFCP_CORE_SIZE + record.local_y + 1
	native_turf = locate(target_x, target_y, run_loc_floor_bottom_left.z)
	TEST_ASSERT(native_turf, "native record target stays inside the test reservation")
	native_turf = fixture.move_turf(native_turf)
	TEST_ASSERT_EQUAL(native_turf.loc, fixture.cave_area, "native record target is moved only into the temporary cavesgen fixture")
	var/datum/df_chunk_cell/cell = decoded.plan.cell_at(record.local_x, record.local_y)
	TEST_ASSERT(cell, "native record has a matching core cell")
	native_turf = native_turf.ChangeTurf(cell.terrain_path, null, null, NONE, cell.material_path)
	native_turf.set_hardness(cell.hardness_id)
	var/datum/df_cave_level/level = new
	level.z = native_turf.z
	level.profile_id = 1
	var/datum/df_cave_chunk/chunk = new
	chunk.level = level
	chunk.cx = chunk_x
	chunk.cy = chunk_y
	chunk.plan = decoded.plan
	chunk.smooth_targets = list()
	chunk.changed_core = list()
	var/core_index = record.local_y * DFCP_CORE_SIZE + record.local_x + 1
	df_cave_mark_applied_core(chunk, core_index, cell)
	TEST_ASSERT(df_cave_apply_decoration_record(chunk, record), "actual native BOTH record applies through semantic-path helper")
	switch(record.kind)
		if(DFCP_RECORD_FLORA)
			var/obj/structure/plant/plant = df_cave_decoration_test_plant(native_turf)
			TEST_ASSERT(plant && plant.type == record.semantic_path, "native flora record spawned its semantic path")
			qdel(plant, TRUE)
		if(DFCP_RECORD_FAUNA)
			var/mob/living/mob = df_cave_decoration_test_mob(native_turf)
			TEST_ASSERT(mob && mob.type == record.semantic_path, "native fauna record spawned its semantic path")
			qdel(mob, TRUE)
		if(DFCP_RECORD_ORE)
			var/turf/closed/mineral/mineral_turf = native_turf
			TEST_ASSERT_EQUAL(mineral_turf.mineralType, record.semantic_path, "native ore record used its semantic path")
			TEST_ASSERT_EQUAL(mineral_turf.mineralAmt, record.arg0, "native ore record used its exact amount")
		if(DFCP_RECORD_TROLL_ROCK)
			var/turf/closed/mineral/stone/stone_turf = native_turf
			TEST_ASSERT(stone_turf.has_troll, "native troll-rock record set its wall flag")
	TEST_ASSERT(fixture.cleanup(), "native decoration fixture cleanup completed")
	TEST_ASSERT(fixture.is_restored(), "native decoration fixture restored turfs, contents, queues, and lighting")
	fixture = null
