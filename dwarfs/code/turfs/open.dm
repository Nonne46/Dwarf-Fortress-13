/turf/open/genturf
	name = "ungenerated turf"
	desc = "If you see this, and you're not a ghost, yell at coders"
	icon = 'icons/turf/debug.dmi'
	icon_state = "genturf"
	flags_cavein = CAVEIN_IGNORE

/turf/open/genturf/New(loc, ...)
	if(SSatoms.initialized == INITIALIZATION_INSSATOMS)
		SHOULD_CALL_PARENT(FALSE)
		return
	return ..()

/turf/open/genturf/Initialize(mapload)
	if(!mapload || !isnull(Master.current_runlevel) || length(contents))
		return ..()
	SHOULD_CALL_PARENT(FALSE)
	if(flags_1 & INITIALIZED_1)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	flags_1 |= INITIALIZED_1
	return INITIALIZE_HINT_NORMAL

/turf/open/floor/tiles
	name = "tiled floor"
	desc = "Classic."
	icon_state = "tiles"
	footstep = FOOTSTEP_SAND
	barefootstep = FOOTSTEP_SAND
	clawfootstep = FOOTSTEP_SAND
	heavyfootstep = FOOTSTEP_GENERIC_HEAVY
	materials = /datum/material/stone
	digging_tools = list(TOOL_PICKAXE=5 SECONDS)
	debris_type = /obj/structure/debris/brick
	var/busy = FALSE

/turf/open/floor/tiles/build_material_icon(_file, state)
	return apply_palettes(..(), materials)

/turf/open/floor/rock
	name = "rock"
	desc = "Terrible."
	icon_state = "stone"
	slowdown = 0.7
	materials = /datum/material/stone
	digging_tools = list(TOOL_PICKAXE)
	debris_type = /obj/structure/debris/rock
	var/digged_up = FALSE

/turf/open/floor/rock/build_material_icon(_file, state)
	return apply_palettes(..(), materials)

/turf/open/floor/rock/crowbar_act(mob/living/user, obj/item/I)
	return FALSE

/turf/open/floor/rock/attackby(obj/item/I, mob/user, params)
	if(I.tool_behaviour == TOOL_CHISEL)
		if(digged_up)
			to_chat(user, span_warning("Nice try mongoid."))
			return
		var/obj/item/chisel/C = I
		var/floor_type = C.chisel_bigtiles ? /turf/open/floor/bigtiles : /turf/open/floor/tiles
		to_chat(user, span_notice("You start carving stone floor..."))
		if(I.use_tool(src, user, 5 SECONDS, volume=50, used_skill=/datum/skill/masonry))
			to_chat(user, span_notice("You finish carving stone floor."))
			user.adjust_experience(/datum/skill/masonry, rand(3,6))
			var/new_materials = materials
			var/turf/floor = ChangeTurf(floor_type, baseturfs, baseturf_materials)
			floor.apply_material(new_materials)
	else
		. = ..()

/turf/open/floor/rock/try_digdown(obj/item/I, mob/user)
	var/obj/item/pickaxe/pick = I
	var/hardness_mod = hardness / pick.hardness
	if(hardness_mod >= MAX_HARDNESS_QUOTIENT)
		playsound(src, pick('sound/effects/pickaxe_bounce1.ogg', 'sound/effects/pickaxe_bounce2.ogg'), 40, TRUE)
		to_chat(user, span_warning("\The [pick] is too soft to mine [src]."))
		return
	var/time = 3 SECONDS * hardness_mod
	to_chat(user, span_notice("You start digging [src]..."))
	if(I.use_tool(src, user, time, volume=50, used_skill=/datum/skill/mining))
		if(QDELETED(src))
			return
		if(digged_up)
			digdown(user)
		else
			for(var/i in 1 to rand(2, 5))
				var/obj/item/S = new /obj/item/stack/ore/stone(src)
				S.apply_material(materials)
				S.pixel_x = rand(-8, 8)
				S.pixel_y = rand(-8, 8)
			digged_up = TRUE
			icon_state = "stone_dug"
			user.visible_message(span_notice("<b>[user]</b> digs up some stones.") ,span_notice("You dig up some stones."))

/turf/open/floor/sand
	name = "sand"
	desc = "You feel warm looking at it."
	icon_state = "sand"
	slowdown = 0.4
	digging_tools = list(TOOL_PICKAXE, TOOL_SHOVEL)
	materials = /datum/material/sandstone
	debris_type = /obj/structure/debris/rock
	var/digged_up = FALSE

/turf/open/floor/sand/try_digdown(obj/item/I, mob/user)
	to_chat(user, span_notice("You start digging [src]..."))
	var/hardness_mod = 1
	var/obj/item/pickaxe/pick = I
	hardness_mod = hardness / pick.hardness
	var/dig_time = I.tool_behaviour == TOOL_SHOVEL ? 3 SECONDS : 10 SECONDS
	if(I.use_tool(src, user, dig_time * hardness_mod, volume=50, used_skill=/datum/skill/mining))
		if(QDELETED(src))
			return
		if(digged_up)
			digdown(user)
		else
			new/obj/item/stack/ore/smeltable/sand(src, rand(3,6))
			digged_up = TRUE
			icon_state = "sand_dug"
			user.visible_message(span_notice("<b>[user]</b> digs up some stones.") , \
				span_notice("You dig up some stones."))

/turf/open/floor/sand/attackby(obj/item/I, mob/user, params)
	if(istype(I, /obj/item/stack/ore/smeltable/sand) && digged_up)
		var/obj/item/stack/O = I
		if(O.amount < 5)
			to_chat(user, span_warning("You don't have enough [O]!"))
			return FALSE
		to_chat(user, span_notice("You start patching a hole in [src]..."))
		if(do_after(user, 1 SECONDS, src))
			O.use(5)
			digged_up = FALSE
			icon_state = "sand"
			user.visible_message(span_notice("<b>[user]</b> patches the hole in [src].") , \
				span_notice("You patch a hole in [src]."))
	else
		return ..()

/turf/open/floor/dirt
	name = "dirt"
	desc = "Found near bodies of water. Can be farmed on."
	icon_state = "soil"
	slowdown = 1
	digging_tools = list(TOOL_PICKAXE, TOOL_SHOVEL)
	debris_type = /obj/structure/debris/dirt
	liquid_border_material = /datum/material/dirt
	var/digged_up = FALSE

/turf/open/floor/dirt/try_digdown(obj/item/I, mob/user)
	to_chat(user, span_notice("You start digging [src]..."))
	var/dig_time = I.tool_behaviour == TOOL_SHOVEL ? 5 SECONDS : 10 SECONDS
	if(I.use_tool(src, user, dig_time, volume=50))
		if(digged_up)
			digdown(user)
		else
			new/obj/item/stack/dirt(src, rand(2,5))
			user.visible_message(span_notice("<b>[user]</b> digs up some dirt.") , \
				span_notice("You dig up some dirt."))
			if(istype(src, /turf/open/floor/dirt/grass))
				var/turf/open/floor/dirt/T = ChangeTurf(/turf/open/floor/dirt)
				T.digged_up = TRUE
				T.icon_state = "soil_dug"
			else
				digged_up = TRUE
				icon_state = "soil_dug"

/turf/open/floor/dirt/attackby(obj/item/I, mob/user, params)
	if(I.tool_behaviour == TOOL_HOE)
		if(digged_up)
			to_chat(user, span_warning("There is no more dirt to be tilled!"))
			return
		to_chat(user, span_notice("You start tilling [src]..."))
		var/channel = playsound(src, 'dwarfs/sounds/tools/hoe/hoe_dig_long.ogg', 50, TRUE)
		if(I.use_tool(src, user, 10 SECONDS, volume=50))
			stop_sound_channel_nearby(src, channel)
			var/turf/open/floor/tilled/T = ChangeTurf(/turf/open/floor/tilled)
			if((locate(/turf/open/water) in range(1, T)))
				T.waterlevel = T.watermax
				T.update_appearance()
			user.adjust_experience(/datum/skill/farming, 7)
		else
			stop_sound_channel_nearby(src, channel)
	else if(istype(I, /obj/item/stack/dirt) && digged_up)
		var/obj/item/stack/O = I
		if(O.amount < 5)
			to_chat(user, span_warning("You don't have enough [O]!"))
			return FALSE
		to_chat(user, span_notice("You start patching a hole in [src]..."))
		if(do_after(user, 2 SECONDS, src))
			O.use(5)
			digged_up = FALSE
			icon_state = "soil"
			user.visible_message(span_notice("<b>[user]</b> patches the hole in [src].") , \
				span_notice("You patch a hole in [src]."))
	else
		return ..()
/turf/open/floor/tilled
	name = "tilled dirt"
	desc = "Ready for plants."
	icon_state = "soil_tilled"
	slowdown = 1
	digging_tools = list(TOOL_SHOVEL)
	debris_type = /obj/structure/debris/dirt
	liquid_border_material = /datum/material/dirt
	var/waterlevel = 0
	var/watermax = 100
	var/fertlevel = 0
	var/fertmax = 100
	///The currently planted plant
	var/obj/structure/plant/myplant = null

/turf/open/floor/tilled/examine(mob/user)
	. = ..()
	.+="<hr>"
	if(myplant)
		.+="There is \a [myplant] growing here."
	else
		.+="It's empty."
	var/fert_text = "<br>"
	switch(fertlevel)
		if(60 to 100)
			fert_text+="There is plenty of fertilizer in it."
		if(30 to 59)
			fert_text+="There is some fertilizer in it."
		if(1 to 29)
			fert_text+="There is almost no fertilizer in it."
		else
			fert_text+="There is no fertilizer in it."
	.+=fert_text
	var/water_text = "<br>"
	switch(waterlevel)
		if(60 to 100)
			water_text+="Looks very moist."
		if(30 to 59)
			water_text+="Looks normal."
		if(1 to 29)
			water_text+="Looks a bit dry."
		else
			water_text+="Looks extremely dry."
	.+=water_text

/turf/open/floor/tilled/Destroy()
	if(myplant)
		QDEL_NULL(myplant)
	return ..()

/turf/open/floor/tilled/attackby(obj/item/O, mob/user, params)
	if(istype(O, /obj/item/growable/seeds))
		if(!myplant)
			if(istype(O, /obj/item/growable/seeds/tree))
				to_chat(user, span_warning("Cannot plant this here!"))
				return
			var/obj/item/growable/seeds/S = O
			var/obj/structure/plant/plant = S.plant
			var/is_above_ground = SSmapping.level_trait(z, ZTRAIT_ABOVE_GROUND)
			var/is_surface_plant = initial(plant.surface)
			if((!is_surface_plant && is_above_ground) || (is_surface_plant && !is_above_ground))
				to_chat(user, span_warning("This will not grow here!"))
				return
			to_chat(user, span_notice("You plant [S]."))
			var/obj/structure/plant/P = new S.plant(src)
			qdel(S)
			myplant = P
			P.plot = src
			myplant.update_appearance()
			RegisterSignal(P, COMSIG_PLANT_DAMAGE_TICK, PROC_REF(on_damage))
			RegisterSignal(P, COMSIG_PLANT_EAT_TICK, PROC_REF(on_eat))
			return
		else
			to_chat(user, span_warning("[capitalize(src.name)] already has seeds in it!"))
			return
	else if(istype(O, /obj/item/stack/fertilizer))
		user.visible_message(span_notice("[user] adds [O] to \the [src]."), span_notice("You add [O] to \the [src]."))
		var/obj/item/stack/fertilizer/F = O
		fertlevel = clamp(fertlevel+F.fertilizer, 0, fertmax)
		F.use(1)
		update_appearance(UPDATE_OVERLAYS)
	else if(O.is_refillable())
		var/datum/reagent/W = O.reagents.has_reagent(/datum/reagent/water)
		if(!W)
			to_chat(user, span_warning("[O] doesn't have water!"))
			return
		var/needed = watermax-waterlevel
		if(needed < 10)
			to_chat(user, span_warning("[src] has enough water already."))
			return
		var/to_remove = W.volume <= needed ? W.volume : needed
		O.reagents.remove_reagent(/datum/reagent/water, to_remove)
		to_chat(user, span_notice("You water [src]."))
		waterlevel = clamp(waterlevel+to_remove, 0, watermax)
		user.adjust_experience(/datum/skill/farming, rand(1,5))
		playsound(src, 'sound/effects/slosh.ogg', 25, TRUE)
		update_appearance()
	else
		return ..()

/turf/open/floor/tilled/try_digdown(obj/item/I, mob/user)
	if(I.tool_behaviour == TOOL_SHOVEL && user.a_intent != INTENT_HARM)
		user.visible_message(span_notice("[user] starts digging out [src]'s plants...") ,
			span_notice("You start digging out [src]'s plants..."))
		if(I.use_tool(src, user, 50, volume=50) || !myplant)
			user.visible_message(span_notice("[user] digs out the plants in [src]!") , span_notice("You dig out all of [src]'s plants!"))
			if(myplant) //Could be that they're just using it as a de-weeder
				QDEL_NULL(myplant)
				name = initial(name)
				desc = initial(desc)
			update_appearance()
	else if(I.tool_behaviour == TOOL_SHOVEL && (user.a_intent == INTENT_HARM))
		to_chat(user, span_notice("You start digging [src]..."))
		if(I.use_tool(src, user, 5 SECONDS, volume=50))
			new/obj/item/stack/dirt(src, rand(2,5))
			user.visible_message(span_notice("<b>[user]</b> digs up some dirt.") , \
				span_notice("You dig up some dirt."))
			var/turf/open/floor/dirt/T = ChangeTurf(/turf/open/floor/dirt)
			T.digged_up = TRUE
			T.icon_state = "soil_dug"

/turf/open/floor/tilled/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	if(myplant)
		if(myplant.dead)
			to_chat(user, span_notice("You remove the dead plant from [src]."))
			QDEL_NULL(myplant)
			update_appearance()
	else
		if(user)
			user.examinate(src)

/turf/open/floor/tilled/proc/on_damage(obj/structure/plant/source, delta_time)
	SIGNAL_HANDLER
	if(!waterlevel)
		source.adjust_damage(-rand(1,3) * delta_time)
	var/is_above_ground = SSmapping.level_trait(z, ZTRAIT_ABOVE_GROUND)
	if((source.surface && !is_above_ground) || (!source.surface && is_above_ground))
		source.adjust_damage(-rand(1,3) * delta_time)

/turf/open/floor/tilled/proc/on_eat(obj/structure/plant/source, delta_time)
	SIGNAL_HANDLER
	if((locate(/turf/open/water) in range(1, src)))
		waterlevel = watermax

	var/needs_update = FALSE
	var/water_old = waterlevel
	var/fert_old = fertlevel

	waterlevel = clamp(waterlevel - source.water_rate * delta_time, 0, watermax)
	fertlevel = clamp(fertlevel - source.fertilizer_rate * delta_time, 0, fertmax)

	if((waterlevel == 0 && water_old > 0) || (fertlevel == 0 && fert_old > 0))
		needs_update = TRUE

	if(!source.growth_modifiers)
		source.growth_modifiers = list()
	source.growth_modifiers["fertilizer"] = fertlevel ? 0.8 : 1

	if(needs_update)
		update_appearance(UPDATE_ICON)

/turf/open/floor/tilled/update_overlays()
	. = ..()
	if(fertlevel)
		. += mutable_appearance(src::icon, "soil_tilled_fertilizer")

/turf/open/floor/tilled/update_icon_state()
	. = ..()
	if((waterlevel/watermax) < 0.3)
		icon_state = "soil_tilled"
	else
		icon_state = "soil_tilled_wet"

/turf/open/water
	name = "water"
	desc = "Stay hydrated."
	icon = 'dwarfs/icons/turf/water.dmi'
	icon_state = "water-255"
	base_icon_state = "water"
	smoothing_flags = SMOOTH_BITMASK
	smoothing_groups = list(SMOOTH_GROUP_TURF_OPEN, SMOOTH_GROUP_FLOOR_WATER)
	canSmoothWith = list(SMOOTH_GROUP_FLOOR_WATER)
	slowdown = 2
	liquid_border_material = /datum/material/stone

/turf/open/water/Initialize(mapload)
	. = ..()
	create_reagents(100, DRAINABLE)
	reagents.add_reagent(/datum/reagent/water, 100)

/turf/open/water/hitby(atom/movable/AM, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum)
	. = ..()
	to_chat(world, "water hit")

/turf/open/water/set_smoothed_icon_state(new_junction)
	. = ..()
	update_appearance(UPDATE_OVERLAYS)

/turf/open/water/update_overlays()
	. = ..()
	var/list/materials = list()
	for(var/cardinal in GLOB.alldirs)
		var/turf/T = get_step(src, cardinal)
		var/used_material = /datum/material/stone
		if(T)
			used_material = T.liquid_border_material || T.materials || /datum/material/stone
		materials += used_material
	var/image/border = image(create_material_icon(null, 'dwarfs/icons/turf/water_borders.dmi', null, materials), null, icon_state)
	. += border

/turf/open/water/attackby(obj/item/C, mob/user, params)
	if(C.is_refillable())
		var/obj/item/reagent_containers/CC = C
		if(CC.reagents.total_volume == CC.volume)
			to_chat(user, span_warning("[CC] is full!"))
			return
		to_chat(user, span_notice("You fill [CC] with water."))
		CC.reagents.add_reagent(/datum/reagent/water, CC.volume - CC.reagents.total_volume)
	else
		reagents.expose(C)
		for(var/atom/A in C)
			reagents.expose(A)

/turf/open/water/attack_hand(mob/user)
	if(ishuman(user))
		to_chat(user, span_notice("You start drinking from [src]..."))
		if(do_after(user, 5 SECONDS, src))
			playsound(user,'sound/items/drink.ogg', rand(10,50), TRUE)
			user.adjust_hydration(rand(50,90), /datum/reagent/water)
			to_chat(user, span_notice("You drink from [src]."))

/turf/open/water/Entered(atom/movable/arrived, atom/old_loc, list/atom/old_locs)
	. = ..()
	if(reagents)
		reagents.expose(arrived)
		for(var/atom/A in arrived)
			reagents.expose(A)

/turf/open/floor/dirt/grass
	name = "grass"
	desc = "Touch it."
	icon = 'dwarfs/icons/turf/grass.dmi'
	icon_state = "grass-0"
	slowdown = 0.5
	base_icon_state = "grass"
	smoothing_flags = SMOOTH_BITMASK
	smoothing_groups = list(SMOOTH_GROUP_FLOOR_GRASS)
	canSmoothWith = list(SMOOTH_GROUP_FLOOR_GRASS)

/turf/open/floor/dirt/grass/Initialize(mapload)
	. = ..()
	if(prob(5))
		var/mutable_appearance/rock = mutable_appearance('dwarfs/icons/turf/decals.dmi', "rock[rand(1, 6)]")
		rock.pixel_x += rand(-12, 12)
		rock.pixel_y += rand(0, 12)
		add_overlay(rock)
	if(prob(1) && !is_blocked_turf())
		new /obj/structure/plant/decor/flower(src)

/turf/open/floor/dirt/grass/Destroy(force)
	for(var/obj/structure/plant/decor/flower/flower in src)
		qdel(flower)
	. = ..()

/turf/open/floor/wooden
	name = "wooden floor"
	desc = "Cozy."
	icon = 'dwarfs/icons/turf/floors.dmi'
	icon_state = "wooden"
	slowdown = -0.2
	materials = list(PART_PLANKS=/datum/material/wood/pine/treated)
	digging_tools = list(TOOL_AXE=5 SECONDS)
	debris_type = /obj/structure/debris/wood
	liquid_border_material = /datum/material/dirt

/turf/open/floor/wooden/build_material_icon(_file, state)
	return apply_palettes(..(), materials)

/turf/open/floor/bigtiles
	name = "large tile floor"
	desc = "Grainy."
	icon_state = "big_tiles"
	slowdown = -0.1
	materials = /datum/material/sandstone
	debris_type = /obj/structure/debris/brick
	digging_tools = list(TOOL_PICKAXE=5 SECONDS)

/turf/open/floor/bigtiles/build_material_icon(_file, state)
	return apply_palettes(..(), materials)

/turf/open/floor/placeholder
	name = "floor"
	desc = "Different floor depending on materials."
	icon_state = "placeholder"

/turf/closed/wall/placeholder
	name = "wall"
	desc = "Different wall Depending on materials."
	icon = 'dwarfs/icons/technical.dmi'
	icon_state = "placeholder_wall"
