GLOBAL_VAR_INIT(temperature_seed, 0)
GLOBAL_VAR(surface_z)

/datum/map_generator/caves
	keys = list("ore", "plants", "mobs", "forest", "troll_rock")
	var/list/ores = list(
		/obj/item/stack/ore/smeltable/gold = 20,
		/obj/item/stack/ore/smeltable/iron = 40,
		/obj/item/stack/ore/gem/diamond=10,
		/obj/item/stack/ore/gem/ruby=10,
		/obj/item/stack/ore/gem/sapphire=10,
		/obj/item/stack/ore/coal=40,
		/obj/item/stack/ore/smeltable/copper=30)

	/// Amount of troll spawn attempts per chunk in generate_rest()
	var/troll_amount = 0

/datum/map_generator/caves/generate_turfs()
	#ifdef TESTING
	var/start_timeofday = REALTIMEOFDAY
	#endif
	if(!GLOB.temperature_seed)
		GLOB.temperature_seed = rand(1, 2000)
	var/list/height_values = fbm(world.maxx, world.maxy)
	var/list/temp_values = fbm3d(world.maxx, world.maxy, z, GLOB.temperature_seed, frequency=0.006, lacunarity=0.4, persistence=0.4)
	for(var/y in 1 to world.maxy)
		for(var/x in 1 to world.maxx)
			var/turf/T = locate(x, y, z)
			if(!(T.loc.type in allowed_areas))
				continue
			var/height = text2num(height_values[world.maxx * (y-1) + x])
			var/temp = text2num(temp_values[world.maxx * (y-1) + x])
			switch(height)
				if(-INFINITY to -0.7)
					T.ChangeTurfQuick(/turf/open/water, flags=CHANGETURF_DEFER_CHANGE)
				if(-0.7 to -0.45)
					T.ChangeTurfQuick(/turf/open/floor/dirt, flags=CHANGETURF_DEFER_CHANGE)
				if(-0.45 to -0.3)
					if(temp > 0)
						T = T.ChangeTurfQuick(/turf/open/floor/rock, /datum/material/sandstone, flags=CHANGETURF_DEFER_CHANGE)
						T.set_hardness(hardness_level)
					else
						T = T.ChangeTurfQuick(/turf/open/floor/rock, /datum/material/stone, flags=CHANGETURF_DEFER_CHANGE)
						T.set_hardness(hardness_level)
				if(-0.3 to INFINITY)
					if(temp > 0)
						T = T.ChangeTurfQuick(/turf/closed/mineral/sand, flags=CHANGETURF_DEFER_CHANGE)
						T.set_hardness(hardness_level)
					else
						T = T.ChangeTurfQuick(/turf/closed/mineral/stone, flags=CHANGETURF_DEFER_CHANGE)
						T.set_hardness(hardness_level)
	#ifdef TESTING
	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	to_chat(world, span_warn("[type].generate_turfs() at z[z]: [time]s"))
	log_runtime("[type].generate_turfs() at z[z]: [time]s")
	#endif

/datum/map_generator/caves/generate_rest()
	#ifdef TESTING
	var/start_timeofday = REALTIMEOFDAY
	#endif

	for(var/turf/T in grid_turfs(z, 30, 1))
		generate_forest(T)

	for(var/turf/T in grid_turfs(z, 30, 4))
		generate_wild_plants(T, SSplants.cave_plants, 3, 7)

	for(var/turf/T in grid_turfs(z, 30, 2))
		generate_turf_fauna(T)

	for(var/turf/T in grid_turfs(z, 30, 2))
		generate_ore(T)

	for(var/turf/closed/mineral/stone/T in grid_turfs(z, 30, troll_amount))
		T.has_troll = TRUE

	#ifdef TESTING
	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	to_chat(world, span_warn("[type].generate_rest() at z[z]: [time]s"))
	log_runtime("[type].generate_rest() at z[z]: [time]s")
	#endif

/datum/map_generator/caves/bottom/generate_rest()
	spawn_rivers(z, 6)
	. = ..()

/datum/map_generator/caves/upper
	hardness_level = 1
	troll_amount = 4
	ores = list(
		/obj/item/stack/ore/smeltable/cassiterite = 30,
		/obj/item/stack/ore/coal=40,
		/obj/item/stack/ore/smeltable/copper=30,
		/obj/item/stack/ore/smeltable/aluminum=5)

/datum/map_generator/caves/middle_upper
	hardness_level = 2
	troll_amount = 8
	ores = list(
		/obj/item/stack/ore/smeltable/cassiterite = 30,
		/obj/item/stack/ore/coal=20,
		/obj/item/stack/ore/smeltable/copper=30,
		/obj/item/stack/ore/smeltable/aluminum=20,
		/obj/item/stack/ore/smeltable/galena=10)

/datum/map_generator/caves/middle
	hardness_level = 3
	troll_amount = 12
	ores = list(
		/obj/item/stack/ore/smeltable/aluminum=30,
		/obj/item/stack/ore/coal=10,
		/obj/item/stack/ore/smeltable/galena=20,
		/obj/item/stack/ore/smeltable/copper=20,
		/obj/item/stack/ore/smeltable/silver=10,
		/obj/item/stack/ore/smeltable/gold=5,
		/obj/item/stack/ore/smeltable/iron=5)

/datum/map_generator/caves/middle_bottom
	hardness_level = 4
	troll_amount = 18
	ores = list(
		/obj/item/stack/ore/smeltable/gold = 30,
		/obj/item/stack/ore/smeltable/silver=30,
		/obj/item/stack/ore/smeltable/iron = 40,
		/obj/item/stack/ore/smeltable/galena=5,
		/obj/item/stack/ore/gem/diamond=5,
		/obj/item/stack/ore/gem/ruby=5,
		/obj/item/stack/ore/gem/sapphire=5,
		/obj/item/stack/ore/coal=20,)

/datum/map_generator/caves/bottom
	hardness_level = 5
	troll_amount = 25
	ores = list(
		/obj/item/stack/ore/smeltable/iron=5,
		/obj/item/stack/ore/smeltable/silver=5,
		/obj/item/stack/ore/smeltable/gold = 20,
		/obj/item/stack/ore/smeltable/platinum = 30,
		/obj/item/stack/ore/smeltable/adamantine = 5,
		/obj/item/stack/ore/gem/diamond=10,
		/obj/item/stack/ore/gem/ruby=10,
		/obj/item/stack/ore/gem/sapphire=10)

/datum/map_generator/surface
	keys = list("plants", "mobs", "forest")

/datum/map_generator/surface/generate_turfs()
	#ifdef TESTING
	var/start_timeofday = REALTIMEOFDAY
	#endif

	var/list/some_values = fbm(world.maxx, world.maxy)
	for(var/y in 1 to world.maxy)
		for(var/x in 1 to world.maxx)
			var/turf/T = locate(x, y, z)
			if(!(T.loc.type in allowed_areas))
				continue
			var/value = text2num(some_values[world.maxx * (y-1) + x])
			switch(value)
				if(-INFINITY to -0.6)
					T.ChangeTurfQuick(/turf/open/water, flags=CHANGETURF_DEFER_CHANGE)
				if(-0.6 to -0.45)
					T.ChangeTurfQuick(/turf/open/floor/sand, flags=CHANGETURF_DEFER_CHANGE)
				if(-0.45 to -0.3)
					T.ChangeTurfQuick(/turf/open/floor/dirt, flags=CHANGETURF_DEFER_CHANGE)
				if(-0.3 to 0.4)
					continue
				if(0.4 to INFINITY)
					T.ChangeTurfQuick(/turf/closed/mineral/stone, flags=CHANGETURF_DEFER_CHANGE)

	#ifdef TESTING
	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	to_chat(world, span_warn("[type].generate_turfs() at z[z]: [time]s"))
	log_runtime("[type].generate_turfs() at z[z]: [time]s")
	#endif

/datum/map_generator/surface/generate_rest()
	#ifdef TESTING
	var/start_timeofday = REALTIMEOFDAY
	#endif
	// for(var/list/data in post_queue["forest"])
	// 	var/turf/T = data[1]
	for(var/turf/T in grid_turfs(z, 30, 1))
		generate_forest(T)

	// for(var/list/data in post_queue["plants"])
	// 	var/turf/T = data[1]
	for(var/turf/T in grid_turfs(z, 30, 4))
		generate_wild_plants(T, SSplants.surface_plants, 3, 7)

	// for(var/list/data in post_queue["mobs"])
	// 	var/turf/T = data[1]
	for(var/turf/T in grid_turfs(z, 30, 2))
		generate_turf_fauna(T)

	#ifdef TESTING
	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	to_chat(world, span_warn("[type].generate_rest() at z[z]: [time]s"))
	log_runtime("[type].generate_rest() at z[z]: [time]s")
	#endif

/datum/map_generator/proc/set_generated_plant_growthstage(obj/structure/plant/plant, stage)
	if(SSatoms.initialized == INITIALIZATION_INSSATOMS)
		plant.growthstage = stage
	else
		plant.set_growthstage(stage)

/datum/map_generator/proc/generate_wild_plants(turf/center, list/plant_types, min_plants=1, max_plants=5)
	var/plant_type = pick(plant_types)
	for(var/i in 1 to rand(min_plants, max_plants))
		var/turf/T = locate(center.x + rand(-3, 3), center.y + rand(-3, 3), z)
		if(!istype(T, /turf/open/floor/dirt))
			continue
		if(is_blocked_turf(T))
			continue
		var/obj/structure/plant/plant = new plant_type(T)
		set_generated_plant_growthstage(plant, rand(0, plant.growthstages))
		plant.lifespan = INFINITY
		plant.growthdelta += rand(-plant.growthdelta*0.2, plant.growthdelta*0.6)

/datum/map_generator/surface/proc/generate_forest(turf/center)
	if((locate(/obj/structure/plant/tree) in view(40, center)))
		return
	var/center_radius = rand(10, 20)
	var/list/center_range = circlerangeturfs(center, center_radius)
	for(var/turf/T in center_range)
		if(prob(40))
			continue
		if(!T || !istype(T, /turf/open/floor/dirt) || T.is_blocked_turf() || (locate(/obj/structure/plant) in T) || istype(T.loc, /area/fortress))
			continue
		var/tree = /obj/structure/plant/tree/pine
		if(prob(0.1))
			tree = /obj/structure/plant/tree/apple
		var/obj/structure/plant/tree/TR = new tree(T)
		set_generated_plant_growthstage(TR, rand(1, 7))
		TR.growthdelta += rand(-10 SECONDS, 1 MINUTES)
	var/mid_radius = center_radius + rand(15, 25)
	var/list/mid_range = circlerangeturfs(center, mid_radius) - center_range
	for(var/turf/T in mid_range)
		if(prob(80))
			continue
		if(!T || !istype(T, /turf/open/floor/dirt) || T.is_blocked_turf() || (locate(/obj/structure/plant) in T) || istype(T.loc, /area/fortress))
			continue
		var/tree = /obj/structure/plant/tree/pine
		if(prob(0.1))
			tree = /obj/structure/plant/tree/apple
		var/obj/structure/plant/tree/TR = new tree(T)
		set_generated_plant_growthstage(TR, rand(1, 7))
		TR.growthdelta += rand(-10 SECONDS, 1 MINUTES)
	var/outer_radius = mid_radius + rand(15, 25)
	var/list/outer_range = circlerangeturfs(center, outer_radius) - center_range - mid_range
	for(var/turf/T in outer_range)
		if(prob(95))
			continue
		if(!T || !istype(T, /turf/open/floor/dirt) || T.is_blocked_turf() || (locate(/obj/structure/plant) in T) || istype(T.loc, /area/fortress))
			continue
		var/tree = /obj/structure/plant/tree/pine
		if(prob(0.01))
			tree = /obj/structure/plant/tree/apple
		var/obj/structure/plant/tree/TR = new tree(T)
		set_generated_plant_growthstage(TR, rand(1, 7))
		TR.growthdelta += rand(-10 SECONDS, 1 MINUTES)

/datum/map_generator/caves/proc/generate_forest(turf/center)
	if((locate(/obj/structure/plant/tree) in view(30, center)))
		return
	var/center_radius = rand(5, 20)
	var/list/center_range = circlerangeturfs(center, center_radius)
	for(var/turf/T in center_range)
		if(prob(70))
			continue
		if(!T || !istype(T, /turf/open/floor/dirt) || T.is_blocked_turf() || (locate(/obj/structure/plant) in T) || istype(T.loc, /area/fortress))
			continue
		var/obj/structure/plant/tree/TR = new /obj/structure/plant/tree/towercap(T)
		set_generated_plant_growthstage(TR, rand(1, 7))
		TR.growthdelta += rand(-10 SECONDS, 1 MINUTES)
	var/mid_radius = center_radius + rand(10, 20)
	var/list/mid_range = circlerangeturfs(center, mid_radius) - center_range
	for(var/turf/T in mid_range)
		if(prob(90))
			continue
		if(!T || !istype(T, /turf/open/floor/dirt) || T.is_blocked_turf() || (locate(/obj/structure/plant) in T) || istype(T.loc, /area/fortress))
			continue
		var/obj/structure/plant/tree/TR = new /obj/structure/plant/tree/towercap(T)
		set_generated_plant_growthstage(TR, rand(1, 7))
		TR.growthdelta += rand(-10 SECONDS, 1 MINUTES)

/datum/map_generator/surface/generate_turf_fauna(turf/center)
	var/list/possible_animals = list(
		/mob/living/simple_animal/chicken=60,
		/mob/living/simple_animal/goat=40,
		/mob/living/simple_animal/hostile/bear=20
	)
	var/animal_type = pickweight(possible_animals)
	//hostile mobs spawn alone; other mobs can spawn in a group
	var/max_amount = ispath(animal_type, /mob/living/simple_animal/hostile) ? 1 : 3
	for(var/i in 1 to rand(1, max_amount))
		var/turf/T = locate(center.x + rand(-3, 3), center.y + rand(-3, 3), z)
		if(!isopenturf(T) || T.is_blocked_turf())
			continue
		new animal_type(T)

/datum/map_generator/caves/generate_turf_fauna(turf/center)
	var/list/possible_animals = list(
		/mob/living/simple_animal/hostile/giant_spider=20,
		/mob/living/simple_animal/hostile/troll=50
	)
	var/animal_type = pickweight(possible_animals)
	//hostile mobs spawn alone; other mobs can spawn in a group
	var/max_amount = ispath(animal_type, /mob/living/simple_animal/hostile) ? 1 : 3
	//we don't want hostile animals too close to each other
	if((locate(/mob/living/simple_animal/hostile) in range(25, center)))
		return
	for(var/i in 1 to rand(1, max_amount))
		var/turf/T = locate(center.x + rand(-3, 3), center.y + rand(-3, 3), z)
		if(!isopenturf(T) || T.is_blocked_turf())
			continue
		new animal_type(T)

/datum/map_generator/caves/proc/generate_ore(turf/closed/mineral/center)
	var/obj/item/stack/ore/O = pickweight(ores)
	var/vein_type = initial(O.vein_type)
	if(!vein_type)
		center.mineralType = O
		center.mineralAmt = rand(1, 5)
	else
		var/datum/vein/V = new vein_type(center)
		V.generate(O)
		qdel(V)
