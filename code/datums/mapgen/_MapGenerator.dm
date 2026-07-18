///This type is responsible for any map generation behavior that is done in z levels.
/datum/map_generator
	var/allowed_areas = list(/area/cavesgen, /area/surface)
	/// Z level of this generator
	var/z
	/// A list that is used in generate_rest proc. We populate it in generate_turfs proc to avoid looping multiple times
	var/list/post_queue = list()
	/// A list of keys used in post_queue. We use it to prevent crashes during generation if it so happens that a key doesn't get populated
	var/list/keys = list()

	/// Controls mineral hardness for this cave generator across the whole z-level. See closed/mineral code to how exactly it works.
	var/hardness_level = 1

/datum/map_generator/New(zlevel=null)
	if(!zlevel)
		CRASH("Initialized map_generator datum without a z level!")
	z = zlevel
	for(var/key in keys)
		post_queue[key] = list()
	. = ..()

/datum/map_generator/proc/queue(key, value)
	if(!(key in post_queue))// this should never happen
		post_queue[key] = list()
	post_queue[key] += list(value)// wrap value in list to avoid adding value's items if it's a list. Otherwise works as intended

/datum/map_generator/proc/prob_queue(chance, key, ...)
	if(prob(chance))
		var/value = args.Copy(3)
		queue(key, value)

/// Main proc for starting generation
/datum/map_generator/proc/run_generation()
	set background = 1
	generate_turfs()
	// Yield cooperatively rather than imposing a fixed per-z delay.
	CHECK_TICK
	generate_rest()

///This proc will be ran by areas on Initialize
/datum/map_generator/proc/generate_turfs()
	set background = 1
	return

/datum/map_generator/proc/generate_rest()
	set background = 1
	return

/datum/map_generator/proc/generate_turf_flora(turf/T)
	return

/datum/map_generator/proc/generate_turf_fauna(turf/T)
	return
