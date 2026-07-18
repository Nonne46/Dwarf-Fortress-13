/obj/structure/plant
	name = "plant"
	desc = "Green?"
	icon = 'dwarfs/icons/farming/growing.dmi'
	icon_state = "0"
	anchored = TRUE
	layer = OBJ_LAYER
	impact_damage = 5
	max_integrity = 30
	/// Used for icons and to whitelist plants in plots
	var/species = "plant"
	/// What seeds does the plant have
	var/seed_type
	/// Amount of health of the plant
	var/health = 40
	/// Max health
	var/maxhealth = 40
	/// How often plant takes damage when it has to
	var/health_delta = 5 SECONDS
	/// Last time it took damage
	var/lastcycle_health
	/// Path type list of items and their max quantity that can be produced at the last growth stage
	var/list/produced = null
	/// Last time it tried to grow something
	var/lastcycle_produce
	/// Amount of time between each try to grow new stuff
	var/produce_delta = 10 SECONDS
	/// Whether a plant is ready for harvest
	var/harvestable = FALSE
	/// Icon state for max growth stage and has harvestables on it
	var/icon_ripe
	/// Icon state when plant is dead
	var/icon_dead
	/// How many growth stages it has
	var/growthstages = 5
	/// How long between two growth stages
	var/growthdelta = 5 SECONDS
	/// Growth modifiers that affect our plant e.g. fertilizer, soil quality, etc. This is a dictianory list for easy overwrites
	var/list/growth_modifiers = null
	/// Last time the plant did an 'eat' tick
	var/lastcycle_eat
	/// How long between eat ticks
	var/eat_delta = 5 SECONDS
	/// Current growth stage of the plant
	var/growthstage = 0
	/// To prevent spam in plantdies()
	var/dead = FALSE
	/// Last time it advanced in growth
	var/lastcycle_growth
	/// Plant's max age in cycles
	var/lifespan = 4
	/// Plant's age in cycles; cycle's length is growthdelta
	var/age = 1
	/// If planted via seeds will have a plot assigned to it
	var/turf/open/floor/tilled/plot
	/// Whether we process this plant at all. Used for decoration dummy plants
	var/dummy = FALSE
	/// Random pixel_x spread when spawned
	var/spread_x = 8
	/// Random pixel_y spread when spawned
	var/spread_y = 12
	/// Whether this plant is a surface plant
	var/surface = TRUE
	/// How much water it's consuming per second
	var/water_rate = 1
	/// How much fertilizer it's consuming per second
	var/fertilizer_rate = 1
	/// Whether the plant requires fertilizer to survive
	var/is_fertilizer_needed = FALSE

/obj/structure/plant/spawn_debris()
	qdel(src)

/obj/structure/plant/zMove(dir, turf/target, z_move_flags)
	. = ..()
	addtimer(CALLBACK(src, PROC_REF(obj_destruction)), 0.5 SECONDS)

/obj/structure/plant/examine(mob/user)
	. = ..()
	var/healthtext = "<br>"
	if(health >= maxhealth/1.5)
		healthtext += "\The [src] looks <font color=green>healthy</font>."
	else if(health >= maxhealth*0.2)
		healthtext += "\The [src] is <font color=orange>withering away</font>."
	else if(health > 0)
		healthtext += "\The [src] is <font color=red>about to die</font>."
	else
		healthtext += "\The [src] is <font color=red>dead</font>!"
	. += healthtext

/obj/structure/plant/examine_more(mob/user)
	. = ..()
	var/farming_level = user.get_skill_level(/datum/skill/farming)
	if(farming_level >= 3)
		. += "It [is_fertilizer_needed ? "requires" : "doesn't require"] fertilizer to grow."
	if(farming_level >= 5)
		. += "<br>It has [rate2adjective(fertilizer_rate)] fertilizer consumption."
		. += "<br>It has [rate2adjective(water_rate)] water consumption."
	if(farming_level >= 8)
		var/growthtime = growthdelta * (growthstages-growthstage)
		if(growthtime > 0)
			. += "<br>It will take another [growthtime / 10] seconds to mature."
		else
			. += "<br>It has fully matured."
		if(produced && !istype(src, /obj/structure/plant/garden/crop))
			. += "<br>It will take another [(growthtime + produce_delta) / 10] seconds until ready to harvest"

/obj/structure/plant/Initialize()
	. = ..()
	pixel_w = base_pixel_x + rand(-spread_x, spread_x)
	pixel_z = base_pixel_y + rand(0, spread_y)
	if(!dummy && ((growthstage < growthstages) || produced))
		START_PROCESSING(SSplants, src)
	if(!icon_ripe)
		icon_ripe = "[species]-ripe"
	if(!icon_dead)
		icon_dead = "[species]-dead"
	if(health != maxhealth)
		maxhealth = health
	if(produced)
		produced = string_list(produced)
	lastcycle_growth = world.time
	lastcycle_produce = world.time
	lastcycle_health = world.time
	lastcycle_eat = world.time
	update_appearance(UPDATE_ICON)

/obj/structure/plant/Destroy()
	. = ..()
	STOP_PROCESSING(SSplants, src)
	if(plot)
		plot.myplant = null
		plot.name = initial(plot.name)

/obj/structure/plant/process(delta_time)
	var/needs_update = 0 // Checks if the icon needs updating so we don't redraw empty trays every time
	var/temp_growthdelta = growthdelta

	if(growth_modifiers)
		for(var/modifier in growth_modifiers)
			temp_growthdelta *= growth_modifiers[modifier]

	var/time_until_growth = lastcycle_growth+temp_growthdelta // time to advance age
	if(world.time >= time_until_growth)
		lastcycle_growth = world.time
		growthcycle()
		needs_update = 1

	if(world.time >= lastcycle_produce+produce_delta)
		lastcycle_produce = world.time
		producecycle()
		if(harvestable)
			needs_update = 1

	if(world.time >= lastcycle_health+health_delta)
		lastcycle_health = world.time
		damagecycle(delta_time)

	if(world.time > lastcycle_eat+eat_delta)
		lastcycle_eat = world.time
		eatcycle(delta_time)

	if(needs_update)
		update_appearance(UPDATE_ICON)

/obj/structure/plant/proc/plantdies()
	if(dead)
		return
	dead = TRUE
	SEND_SIGNAL(src, COMSIG_PLANT_DIES)
	STOP_PROCESSING(SSplants, src)
	visible_message(span_warning("[src] withers away!"))
	if(plot)
		return
	qdel(src)

/obj/structure/plant/proc/eatcycle(delta_time)
	SEND_SIGNAL(src, COMSIG_PLANT_EAT_TICK, delta_time)
	return

/obj/structure/plant/update_icon_state()
	. = ..()
	if(dead)
		icon_state = icon_dead
	else if(harvestable)
		icon_state = icon_ripe
	else if(growthstage > 0)
		icon_state = "[species]-[growthstage]"

/obj/structure/plant/proc/can_grow_harvestable()
	if(!produced)
		return FALSE
	if(growthstage != growthstages)
		return FALSE
	return TRUE

/obj/structure/plant/proc/grown()
	SEND_SIGNAL(src, COMSIG_PLANT_ON_GROWN)
	lastcycle_produce = world.time
	if(!produced && lifespan == INFINITY)
		STOP_PROCESSING(SSplants, src)

/obj/structure/plant/proc/growthcycle()
	var/res = SEND_SIGNAL(src, COMSIG_PLANT_ON_GROW)
	if(res & COMPONENT_CANCEL_PLANT_GROW)
		return
	age++
	growthstage = clamp(growthstage+1, 1, growthstages)
	if(age == growthstages)
		grown()

/obj/structure/plant/proc/producecycle()
	SEND_SIGNAL(src, COMSIG_PLANT_PRODUCE_TICK)
	if(harvestable)
		return
	if(can_grow_harvestable())
		harvestable = TRUE
		if(lifespan == INFINITY)
			STOP_PROCESSING(SSplants, src)

/obj/structure/plant/proc/damagecycle(delta_time)
	SEND_SIGNAL(src, COMSIG_PLANT_DAMAGE_TICK, delta_time)
	if(age > lifespan)
		health -= rand(1,3) * delta_time
	if(health <= 0 && !dead)
		plantdies()
		update_appearance(UPDATE_ICON)

/obj/structure/plant/proc/harvest(mob/user)
	. = TRUE
	var/speed_mod = user.get_skill_modifier(/datum/skill/farming, SKILL_SPEED_MODIFIER)
	var/min_mod = user.get_skill_modifier(/datum/skill/farming, SKILL_AMOUNT_MIN_MODIFIER)
	var/max_mod = user.get_skill_modifier(/datum/skill/farming, SKILL_AMOUNT_MAX_MODIFIER)
	if(!do_after(user, 5 SECONDS * speed_mod, src))
		return FALSE
	if(QDELETED(src) || !harvestable)
		return
	harvestable = FALSE
	lastcycle_produce = world.time
	// spawn seeds separately, we don't want those in produced list
	if(seed_type)
		for(var/i in 1 to rand(1+min_mod, 1+max_mod))
			new seed_type(get_turf(user))
	// spawn all produced items
	for(var/_P in produced)
		var/obj/item/growable/P = _P
		var/harvested = rand(0+min_mod, produced[P]+max_mod)
		if(growth_modifiers && growth_modifiers["fertilizer"] < 1 && growth_modifiers["fertilizer"] != 0) // it's fertilized
			harvested += 3
		if(harvested)
			for(var/i in 1 to harvested)
				new P(get_turf(user))
			to_chat(user, span_notice("You harvest [initial(P.name)] from [src]."))
			user.adjust_experience(/datum/skill/farming, harvested*8)
		else
			to_chat(user, span_warning("You fail to harvest [initial(P.name)] from [src]."))
			user.adjust_experience(/datum/skill/farming, 5)
	START_PROCESSING(SSplants, src)
	update_appearance()

/obj/structure/plant/attack_hand(mob/user)
	if(!harvestable)
		to_chat(user, span_warning("There is nothing to harvest!"))
		return
	if(!dead)
		harvest(user)
	else
		if(plot)
			plot.attack_hand(user)
		else
			to_chat(user, span_notice("You remove the dead plant."))
			qdel(src)

/obj/structure/plant/proc/set_growthstage(new_growthstage)
	if(growthstage == new_growthstage)
		return
	growthstage = new_growthstage
	update_appearance(UPDATE_ICON)

/obj/structure/plant/proc/adjust_damage(damage)
	if(dead)
		return
	health += damage
	if(health <= 0)
		plantdies()
		update_appearance(UPDATE_ICON)

/obj/structure/plant/proc/rate2adjective(rate)
	switch(rate)
		if(0)
			return "nonexistent"
		if(0 to 0.5)
			return "minimal"
		if(0.5 to 0.8)
			return "low"
		if(0.8 to 1.2)
			return "moderate"
		if(1.2 to INFINITY)
			return "high"
		else
			return "unknown"
