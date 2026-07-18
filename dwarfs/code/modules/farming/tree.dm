/obj/structure/plant/tree
	name = "tree"
	desc = "Big green?"
	icon = 'dwarfs/icons/farming/growing_tree_96x96.dmi'
	density = TRUE
	lifespan = INFINITY
	base_pixel_x = -32
	spread_x = 4
	spread_y = 3
	growthstages = 7
	impact_damage = 6
	max_integrity = 200
	var/small_log_type = /obj/item/log
	var/large_log_type = /obj/item/log/large
	/// a list of small logs with amount corresponding to the growthstage
	var/list/small_log_amount = list(0,1,1,2,0,2,0)
	/// a list of large logs with amount corresponding to the growthstage
	var/list/large_log_amount = list(0,0,0,0,1,1,2)
	/// Required amount of chops for each growthstage
	var/list/required_chops = list(1,1,1,3,3,4,4)
	/// Amount of chops already made to the tree
	var/chops = 0
	/// `pixel_y` offset for the chop mask for each growthstage
	var/list/chop_offsets = list(0, 0, 0, 0, 0, 0, 0)
	/// Time between each chop
	var/cutting_time = 4 SECONDS

/obj/structure/plant/tree/Initialize()
	. = ..()
	if(growthstage > 3)
		density = TRUE
	else
		density = FALSE
	if(small_log_amount)
		small_log_amount = string_list(small_log_amount)
	if(large_log_amount)
		large_log_amount = string_list(large_log_amount)
	if(required_chops)
		required_chops = string_list(required_chops)
	if(chop_offsets)
		chop_offsets = string_list(chop_offsets)

/obj/structure/plant/tree/spawn_debris()
	chop_tree(get_turf(src))
	qdel(src)

/obj/structure/plant/tree/examine(mob/user)
	. = ..()
	if(chops)
		. += "<br>It has chop cut[chops > 1 ? "s" : ""] visible."

/obj/structure/plant/tree/growthcycle()
	. = ..()
	impact_damage = src::impact_damage * growthstage
	if(growthstage > 3)
		density = TRUE
	else
		density = FALSE

/obj/structure/plant/tree/set_growthstage(new_growthstage)
	. = ..()
	if(growthstage > 3)
		density = TRUE
	else
		density = FALSE

/obj/structure/plant/tree/update_overlays()
	. = ..()
	if(chops)
		var/icon/cut = create_material_icon(type, src::icon, "cut[chops]", materials)
		var/mutable_appearance/MA = mutable_appearance(cut)
		MA.pixel_z = chop_offsets[growthstage]
		MA.blend_mode = BLEND_INSET_OVERLAY
		. += MA

/obj/structure/plant/tree/proc/try_chop(obj/item/tool, mob/living/user)
	to_chat(user, span_notice("You start chopping down [src]..."))
	var/channel = playsound(src.loc, 'dwarfs/sounds/tools/axe/axe_chop_long.ogg', 50, TRUE)
	if(tool.use_tool(src, user, cutting_time, used_skill=/datum/skill/logging))
		stop_sound_channel_nearby(src, channel)

		user.adjust_experience(/datum/skill/logging, 3.6)
		if(chops >= required_chops[growthstage])
			to_chat(user, span_notice("You chop down [src]."))
			chop_tree(get_turf(src), TRUE)
			qdel(src)
		else
			to_chat(user, span_notice("You cut a fine notch into [src]."))
			chops++
			update_appearance(UPDATE_ICON)
	else
		stop_sound_channel_nearby(src, channel)

/obj/structure/plant/tree/proc/chop_tree(turf/my_turf, spawn_seeds=FALSE)
	if(spawn_seeds && seed_type)
		for(var/i in 1 to rand(1, 2))
			new seed_type(my_turf)
	if(small_log_type)
		for(var/i in 1 to small_log_amount[growthstage])
			var/obj/L = new small_log_type(my_turf)
			L.apply_material(materials)
	if(large_log_type)
		for(var/i in 1 to large_log_amount[growthstage])
			var/obj/L = new large_log_type(my_turf)
			L.apply_material(materials)
			L.setDir(pick(SOUTH, EAST))

/obj/structure/plant/tree/attack_hand(mob/user)
	if(user.a_intent == INTENT_HARM && (locate(/mob/living) in get_step(src, NORTH)) && user.CanReach(get_step(src, NORTH)))
		var/list/possible_targets = list()
		for(var/mob/living/L in get_step(src, NORTH))
			possible_targets += L
		var/mob/selected_target = pick(possible_targets)
		//UnarmedAttack doesn't check for next_move
		if(user.next_move > world.time)
			return
		user.changeNext_move(CLICK_CD_MELEE)
		return user.UnarmedAttack(selected_target)
	. = ..()

/obj/structure/plant/tree/attackby(obj/item/I, mob/user, params)
	if(user.a_intent == INTENT_HARM && (locate(/mob/living) in get_step(src, NORTH)) && user.CanReach(get_step(src, NORTH), I))
		var/list/possible_targets = list()
		for(var/mob/living/L in get_step(src, NORTH))
			possible_targets += L
		var/mob/selected_target = pick(possible_targets)
		return I.melee_attack_chain(user, selected_target, params)
	else if(I.tool_behaviour == TOOL_AXE)
		try_chop(I, user)
	else
		. = ..()

/obj/structure/plant/tree/towercap
	name = "towercap"
	desc = "A mushroom-like subterranean tree. Bears tower cap logs once chopped down."
	species = "towercap"
	icon_ripe = "towercap-7"
	seed_type = /obj/item/growable/seeds/tree/towercap
	health = 100
	growthdelta = 80 SECONDS
	produce_delta = 120 SECONDS
	materials = /datum/material/wood/towercap
	chop_offsets = list(-15, -15, -10, -5, -2, -3, -3)

/obj/structure/plant/tree/apple
	name = "apple tree"
	desc = "A fruit-bearing tree. Good source of apples for your food."
	species = "apple"
	seed_type = /obj/item/growable/seeds/tree/apple
	produced = list(/obj/item/growable/apple=4)
	growthdelta = 1.5 MINUTES
	produce_delta = 5 MINUTES
	materials = /datum/material/wood/apple
	chop_offsets = list(-15, -15, -15, -5, -5, 0, 0)

/obj/structure/plant/tree/pine
	name = "pine tree"
	desc = "Common tree found in a forest. Mostly used as lumber."
	species = "pine"
	seed_type = /obj/item/growable/seeds/tree/pine
	growthdelta = 2 MINUTES
	produce_delta = 1 MINUTES
	materials = /datum/material/wood/pine
	chop_offsets = list(-15, -15, -15, -10, -10, -10, -10)
