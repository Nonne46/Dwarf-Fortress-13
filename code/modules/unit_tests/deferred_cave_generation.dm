/turf/open/floor/df_cave_afterchange_test
	var/afterchange_calls = 0
	var/afterchange_hardness
	var/afterchange_material

/turf/open/floor/df_cave_afterchange_test/AfterChange(flags, oldType)
	afterchange_calls++
	afterchange_hardness = hardness
	afterchange_material = materials
	return ..()

/obj/effect/df_cave_afterchange_probe
	var/handle_calls = 0
	var/turf/last_turf
	var/observed_hardness
	var/observed_material
	var/observed_afterchange_calls

/obj/effect/df_cave_afterchange_probe/HandleTurfChange(turf/T)
	handle_calls++
	last_turf = T
	observed_hardness = T.hardness
	observed_material = T.materials
	if(istype(T, /turf/open/floor/df_cave_afterchange_test))
		var/turf/open/floor/df_cave_afterchange_test/test_turf = T
		observed_afterchange_calls = test_turf.afterchange_calls
	return ..()

/datum/unit_test/deferred_cave_generation/Run()
	var/datum/map_generator/caves/upper/upper = new(2)
	var/datum/map_generator/caves/middle_upper/middle_upper = new(2)
	var/datum/map_generator/caves/middle/middle = new(2)
	var/datum/map_generator/caves/middle_bottom/middle_bottom = new(2)
	var/datum/map_generator/caves/bottom/bottom = new(2)
	TEST_ASSERT_EQUAL(SSmapping.deferred_cave_profile(upper), 1, "upper profile")
	TEST_ASSERT_EQUAL(SSmapping.deferred_cave_profile(middle_upper), 2, "middle upper profile")
	TEST_ASSERT_EQUAL(SSmapping.deferred_cave_profile(middle), 3, "middle profile")
	TEST_ASSERT_EQUAL(SSmapping.deferred_cave_profile(middle_bottom), 4, "middle bottom profile")
	TEST_ASSERT_EQUAL(SSmapping.deferred_cave_profile(bottom), 5, "bottom profile")
	var/datum/df_cave_level/level = new
	level.z = 2
	level.profile_id = 3
	var/datum/df_cave_chunk/chunk = new
	chunk.level = level
	chunk.cx = 1
	chunk.cy = 1
	var/list/errors = list()
	chunk.request = df_chunk_request_from_wire("1", "1", "1", "0123456789abcdef", "3", "1", "1", "-3", "3", errors)
	TEST_ASSERT(chunk.request, "logical BOTH request")
	TEST_ASSERT_EQUAL(chunk.request.sections, DFCP_SECTION_BOTH, "deferred request stores canonical BOTH sections")
	TEST_ASSERT_EQUAL(chunk.request.chunk_z.text, "-3", "logical z is profile, never physical z")
	TEST_ASSERT_EQUAL(chunk.cx * 32 + 0 + 1, 33, "zero-based logical x physical core")
	TEST_ASSERT_EQUAL(chunk.cy * 32 + 31 + 1, 64, "physical core edge")
	TEST_ASSERT_EQUAL(df_cave_floor_div(1 - 1, 32), 0, "x1 chunk")
	TEST_ASSERT_EQUAL(df_cave_floor_div(32 - 1, 32), 0, "x32 chunk")
	TEST_ASSERT_EQUAL(df_cave_floor_div(33 - 1, 32), 1, "x33 chunk")
	TEST_ASSERT_EQUAL(df_cave_floor_div(40 - 1, 32), 1, "x40 chunk")
	TEST_ASSERT_EQUAL(df_cave_floor_div(300 - 1, 32), 9, "x300 chunk")
	TEST_ASSERT_EQUAL(df_cave_floor_div(1023, 32), 31, "last core row")

	// Integration regression for B2a's deferred regular ChangeTurf lifecycle.
	var/turf/T = run_loc_floor_bottom_left
	T = T.ChangeTurf(/turf/open/genturf)
	var/obj/effect/df_cave_afterchange_probe/probe = new(T)
	var/datum/df_chunk_cell/cell = new
	cell.terrain_path = /turf/open/floor/df_cave_afterchange_test
	cell.material_path = /datum/material/stone
	cell.hardness_id = 3
	var/turf/new_turf = df_cave_finalize_terrain_turf(T, cell)
	TEST_ASSERT(istype(new_turf, /turf/open/floor/df_cave_afterchange_test), "reference terrain replacement type")
	var/turf/open/floor/df_cave_afterchange_test/test_turf = new_turf
	TEST_ASSERT_EQUAL(test_turf.afterchange_calls, 1, "virtual AfterChange exactly once")
	TEST_ASSERT_EQUAL(test_turf.afterchange_hardness, 3, "hardness final inside AfterChange")
	TEST_ASSERT(test_turf.afterchange_material, "material final inside AfterChange")
	TEST_ASSERT_EQUAL(probe.handle_calls, 1, "HandleTurfChange dispatched exactly once")
	TEST_ASSERT_EQUAL(probe.last_turf, new_turf, "probe observed replacement turf")
	TEST_ASSERT_EQUAL(probe.observed_hardness, 3, "probe sees final hardness")
	TEST_ASSERT(probe.observed_material, "probe sees final material")
	TEST_ASSERT_EQUAL(probe.observed_afterchange_calls, 1, "probe sees AfterChange dispatch")
	TEST_ASSERT(new_turf.flags_1 & INITIALIZED_1, "replacement remains initialized")

	// Isolate the preserved lifecycle fixture in the unit-test reservation;
	// never borrow or mutate a production cave area/turf.
	var/turf/cave_turf = run_loc_floor_top_right
	var/area/original_area = cave_turf.loc
	var/original_type = cave_turf.type
	var/original_baseturfs = cave_turf.baseturfs
	var/original_baseturf_materials = cave_turf.baseturf_materials
	var/original_materials = cave_turf.materials
	var/old_always_lit = cave_turf.always_lit
	var/area/cavesgen/test_cave_area = new
	test_cave_area.static_lighting = FALSE
	test_cave_area.contents += cave_turf
	cave_turf.change_area(original_area, test_cave_area)
	TEST_ASSERT_EQUAL(cave_turf.loc, test_cave_area, "fixture moved into isolated exact cavesgen area")
	TEST_ASSERT(!original_area.contents.Find(cave_turf), "fixture left original area")
	TEST_ASSERT(test_cave_area.contents.Find(cave_turf), "fixture entered temporary cave area")
	cave_turf.always_lit = FALSE
	cave_turf = cave_turf.ChangeTurf(/turf/open/floor/rock)
	var/datum/df_cave_chunk/preserved_chunk = new
	preserved_chunk.level = level
	preserved_chunk.changed_core = list()
	preserved_chunk.smooth_targets = list()
	preserved_chunk.state = DF_CAVE_SMOOTHING
	TEST_ASSERT(!df_cave_apply_core_turf(preserved_chunk, cave_turf, cell), "production classifier preserves mutation")
	TEST_ASSERT_EQUAL(cave_turf.type, /turf/open/floor/rock, "preserved core turf is never replaced")
	TEST_ASSERT(preserved_chunk.changed_core.Find(cave_turf), "preserved core participates in lighting")
	TEST_ASSERT(preserved_chunk.smooth_targets.Find(cave_turf), "preserved core participates in smoothing")
	var/list/old_smoothing_flags = list()
	for(var/atom/smooth_target in preserved_chunk.smooth_targets)
		old_smoothing_flags[smooth_target] = smooth_target.smoothing_flags
		smooth_target.smoothing_flags &= ~(SMOOTH_QUEUED | SMOOTH_B_QUEUED)
	cave_turf.smoothing_flags |= SMOOTH_QUEUED
	SScave_generation.finish_smoothing(preserved_chunk)
	TEST_ASSERT_EQUAL(preserved_chunk.state, DF_CAVE_SMOOTHING, "pending local smoothing blocks lighting")
	cave_turf.smoothing_flags &= ~SMOOTH_QUEUED
	SScave_generation.finish_smoothing(preserved_chunk)
	TEST_ASSERT_EQUAL(preserved_chunk.state, DF_CAVE_LIGHTING, "drained local smoothing enters lighting")
	if(cave_turf.lighting_object)
		qdel(cave_turf.lighting_object, TRUE)
	TEST_ASSERT(SSlighting.initialized, "lighting subsystem available for local lifecycle")
	SScave_generation.finish_lighting(preserved_chunk)
	TEST_ASSERT(cave_turf.lighting_object?.needs_update, "local lighting object awaits update")
	TEST_ASSERT_EQUAL(preserved_chunk.state, DF_CAVE_LIGHTING, "pending local lighting blocks COMPLETE")
	cave_turf.lighting_object.needs_update = FALSE
	SScave_generation.finish_lighting(preserved_chunk)
	TEST_ASSERT_EQUAL(preserved_chunk.state, DF_CAVE_COMPLETE, "drained local lighting completes chunk")
	qdel(cave_turf.lighting_object, TRUE)
	for(var/atom/smooth_target in old_smoothing_flags)
		smooth_target.smoothing_flags = old_smoothing_flags[smooth_target]
	cave_turf.ChangeTurf(original_type, original_baseturfs, original_baseturf_materials, NONE, original_materials)
	cave_turf.always_lit = old_always_lit
	original_area.contents += cave_turf
	cave_turf.change_area(test_cave_area, original_area)
	TEST_ASSERT_EQUAL(cave_turf.loc, original_area, "fixture restored to original area")
	TEST_ASSERT(!test_cave_area.contents.Find(cave_turf), "fixture removed from temporary area")
	TEST_ASSERT(original_area.contents.Find(cave_turf), "fixture restored to original area contents")
	qdel(test_cave_area)
	qdel(probe)
	qdel(upper)
	qdel(middle_upper)
	qdel(middle)
	qdel(middle_bottom)
	qdel(bottom)
