/obj/machinery/portable_atmospherics/hydroponics/process()

	//Do this even if we're not ready for a plant cycle.
	process_reagents()

	// Update values every cycle rather than every process() tick.
	if(force_update)
		force_update = 0
	else if(world.time < (lastcycle + cycledelay))
		if(update_icon_after_process)
			update_icon()
		return
	lastcycle = world.time

	if (pollination <= 0)
		bees = 0
	else
		pollination--
		bees = 1


	// Weeds like water and nutrients, there's a chance the weed population will increase.
	// Bonus chance if the tray is unoccupied.
	// This process is up here because it still happens even when the tray is empty.
	if(waterlevel > 10 && nutrilevel > 2 && prob(isnull(seed) ? 5 : (1/(1+bees)))) //I hate whoever wrote this check
		weedlevel += 1 * HYDRO_SPEED_MULTIPLIER * weed_coefficient
		if(draw_warnings)
			update_icon_after_process = 1

	// There's a chance for a weed explosion to happen if the weeds take over.
	// Plants that are themselves weeds (weed_tolerance > 8) are unaffected.
	if (weedlevel >= 10 && prob(10))
		if(!seed || weedlevel >= seed.weed_tolerance+2)
			weed_invasion()

	// If there is no seed data (and hence nothing planted),
	// or the plant is dead, process nothing further.
	if(!seed || dead)
		if(update_icon_after_process)
			update_icon() //Harvesting would fail to set alert icons properly.
		return

	// On each tick, there's a chance the pest population will increase.
	// This process is under the !seed check because it only happens when a live plant is in the tray.
	if(prob(1/(1+bees)))
		pestlevel += 0.5 * HYDRO_SPEED_MULTIPLIER
		if(draw_warnings)
			update_icon_after_process = 1

	//Bees will attempt to aid the plant's longevity and make it fruit faster.
	if(bees && age >= seed.maturation && prob(50))
		if(harvest)
			skip_aging++
		else
			lastproduce--

	// Advance plant age.
	if(!has_slime)
		if(skip_aging)
			skip_aging--
		else
			if(prob(80))
				age += 1 * HYDRO_SPEED_MULTIPLIER
				update_icon_after_process = 1

	//Highly mutable plants have a chance of mutating every tick.
	if(seed.immutable == -1)
		if(prob(5))
			mutate(rand(5,15))

	// Maintain tray nutrient and water levels.
	if(seed.nutrient_consumption > 0 && nutrilevel > 0 && prob(25))
		nutrilevel -= max(0,seed.nutrient_consumption * HYDRO_SPEED_MULTIPLIER)
		if(draw_warnings)
			update_icon_after_process = 1
	if(seed.water_consumption > 0 && waterlevel > 0  && prob(25))
		waterlevel -= max(0,seed.water_consumption * HYDRO_SPEED_MULTIPLIER)
		if(draw_warnings)
			update_icon_after_process = 1

	var/healthmod = rand(1,3) * HYDRO_SPEED_MULTIPLIER

	// Make sure the plant is not starving or thirsty. Adequate water and nutrients will
	// cause a plant to become healthier. Lack of sustenance will stunt the plant's growth.
	if(prob(35))
		if(nutrilevel > 2)
			plant_health += healthmod
		else
			affect_growth(-1)
			plant_health -= healthmod
		if(draw_warnings)
			update_icon_after_process = 1
	if(prob(35))
		if(waterlevel > 10)
			plant_health += healthmod
		else
			affect_growth(-1)
			plant_health -= healthmod
		if(draw_warnings)
			update_icon_after_process = 1

	// Check that pressure, heat and light are all within bounds.
	// First, handle an open system or an unconnected closed system.

	var/turf/T = loc
	var/datum/gas_mixture/environment

	// If we're closed, take from our internal sources.
	if(closed_system && (connected_port || holding))
		environment = air_contents

	// If atmos input is not there, grab from turf.
	if(!environment)
		if(istype(T))
			environment = T.return_air()

	if(!environment)
		if(istype(T, /turf/space))
			environment = space_gas
		else
			return

	// Handle gas consumption.
	if(seed.consume_gasses && seed.consume_gasses.len && environment)
		missing_gas = 0
		for(var/gas in seed.consume_gasses)
			if(environment[gas] < seed.consume_gasses[gas])
				missing_gas++
				continue
			environment.adjust_gas(gas, -(seed.consume_gasses[gas]), FALSE)
		environment.update_values()

		if(missing_gas > 0)
			plant_health -= missing_gas * HYDRO_SPEED_MULTIPLIER
			if(draw_warnings)
				update_icon_after_process = 1

	// Process it.
	var/pressure = environment.return_pressure()
	if(pressure < seed.lowkpa_tolerance || pressure > seed.highkpa_tolerance)
		plant_health -= healthmod
		improper_kpa = 1
		if(draw_warnings)
			update_icon_after_process = 1
	else
		improper_kpa = 0

	if(abs(environment.temperature - seed.ideal_heat) > seed.heat_tolerance)
		plant_health -= healthmod
		improper_heat = 1
		if(draw_warnings)
			update_icon_after_process = 1
	else
		improper_heat = 0

	// Handle gas production.
	if(seed.exude_gasses && seed.exude_gasses.len)
		for(var/gas in seed.exude_gasses)
			environment.adjust_gas(gas, max(1,round((seed.exude_gasses[gas]*round(seed.potency))/seed.exude_gasses.len)))

	if(seed.alter_temp)
		if((environment.temperature < seed.ideal_heat - seed.heat_tolerance) || (environment.temperature > seed.ideal_heat + seed.heat_tolerance))
			var/energy_cap = seed.potency * 60 * MOLES_CELLSTANDARD //This is totally arbitrary. It just serves to approximate the behavior from when this modified temperature rather than thermal energy.
			var/energy_change = clamp(environment.get_thermal_energy_change(seed.ideal_heat), -energy_cap, energy_cap)
			environment.add_thermal_energy(energy_change)

	// If we're attached to a pipenet, then we should let the pipenet know we might have modified some gasses
	//if (closed_system && connected_port)
	//'	update_connected_network()

	// Handle light requirements.

	var/light_available = 5
	if(T.dynamic_lighting)
		light_available = T.get_lumcount() * 10

	if(!seed.biolum && abs(light_available - seed.ideal_light) > seed.light_tolerance)
		plant_health -= healthmod
		if(prob(35))
			affect_growth(-1)
		improper_light = 1
		if(draw_warnings)
			update_icon_after_process = 1
	else
		improper_light = 0

	// Toxin levels beyond the plant's tolerance cause damage, but
	// toxins are sucked up each tick and slowly reduce over time.
	if(toxins > 0)
		var/toxin_uptake = max(1,round(toxins/10))
		if(toxins > seed.toxins_tolerance)
			plant_health -= toxin_uptake
		toxins -= toxin_uptake * (1+bees)
		if(draw_warnings)
			update_icon_after_process = 1

	// Check for pests and weeds.
	// Some carnivorous plants happily eat pests.
	if(pestlevel > 0)
		if(seed.carnivorous)
			plant_health += HYDRO_SPEED_MULTIPLIER
			pestlevel -= HYDRO_SPEED_MULTIPLIER
		else if (pestlevel >= seed.pest_tolerance)
			plant_health -= HYDRO_SPEED_MULTIPLIER
		if(draw_warnings)
			update_icon_after_process = 1

	// Some plants thrive and live off of weeds.
	if(weedlevel > 0)
		if(seed.parasite)
			plant_health += HYDRO_SPEED_MULTIPLIER
			weedlevel -= HYDRO_SPEED_MULTIPLIER
		else if (weedlevel >= seed.weed_tolerance)
			plant_health -= HYDRO_SPEED_MULTIPLIER
		if(draw_warnings)
			update_icon_after_process = 1

	// Handle life and death.
	// If the plant is too old, it loses health fast.
	if(age > seed.lifespan)
		plant_health -= (rand(3,5) * HYDRO_SPEED_MULTIPLIER)/(1+bees)
		if(draw_warnings)
			update_icon_after_process = 1
	// If the plant's age is negative, let's revert it into a seed packet, for funsies
	else if(age < 0)
		seed.spawn_seed_packet(get_turf(src))
		remove_plant()
		force_update = 1
		process()

	check_health()

	if(harvest && seed.harvest_repeat == 2)
		autoharvest()

	// If enough time (in cycles, not ticks) has passed since the plant was harvested, we're ready to harvest again.
	if(!dead && seed.products && seed.products.len)
		if (age > seed.production)
			if ((age - lastproduce) > seed.production && !harvest)
				harvest = 1
				lastproduce = age
		else
			if(harvest) //It's a baby plant ready to harvest... must have aged backwards!
				harvest = 0
				lastproduce = age

	// If we're a spreading vine, let's go ahead and try to spread our love.
	if(seed.spread && !closed_system && age >= seed.maturation && prob(2 * max(10,seed.potency)))
		if((nutrilevel < 8 && waterlevel < 80) || seed.hematophage || seed.carnivorous) // Unless we're particularly vicious, let's not try to spread while our needs are met.
			if(!(locate(/obj/effect/plantsegment) in T))
				new /obj/effect/plantsegment(T, seed)
				switch(seed.spread)
					if(1)
						msg_admin_attack("limited growth creeper vines ([seed.display_name]) have spread out of a tray. <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>(JMP)</a>, last touched by [key_name_last_user]. Seed id: [seed.uid]. ([bad_stuff()])")
					if(2)
						msg_admin_attack("space vines ([seed.display_name]) have spread out of a tray. <A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>(JMP)</a>, last touched by [key_name_last_user]. Seed id: [seed.uid]. ([bad_stuff()])")

	check_level_sanity()
	if(update_icon_after_process)
		update_icon()

/obj/machinery/portable_atmospherics/hydroponics/proc/check_health()
	if(plant_health <= 0)
		die() //ominous

/obj/machinery/portable_atmospherics/hydroponics/proc/affect_growth(var/amount)
	if(amount > 0)
		if(age < seed.maturation)
			age += amount
		else if(!harvest && seed.yield != -1)
			lastproduce -= amount
	else
		if(age < seed.maturation)
			skip_aging++
		else if(!harvest && seed.yield != -1)
			lastproduce += amount


/obj/machinery/portable_atmospherics/hydroponics/proc/update_name()
	if(seed)
		//name = "[initial(name)] ([seed.seed_name])"
		name = "[seed.display_name]"
	else
		name = initial(name)

	if(labeled)
		name += " ([labeled])"

//Refreshes the icon and sets the luminosity
/obj/machinery/portable_atmospherics/hydroponics/update_icon()
	update_icon_after_process = 0

	overlays.len = 0

	update_name() //fuck it i'll make it not happen constantly later

	// Updates the plant overlay.
	if(!isnull(seed))
		if(draw_warnings && plant_health <= (seed.endurance / 2))
			overlays += image('icons/obj/hydroponics/hydro_tools.dmi',"over_lowhealth3")

		if(dead)
			overlays += image(seed.plant_dmi,"dead")
		else if(harvest)
			overlays += image(seed.plant_dmi,"harvest")
		else if(age < seed.maturation)
			var/t_growthstate = max(1,round((age * seed.growth_stages) / seed.maturation))
			overlays += image(seed.plant_dmi,"stage-[t_growthstate]")
			lastproduce = age
		else
			overlays += image(seed.plant_dmi,"stage-[seed.growth_stages]")

	//Draw the cover.
	if(closed_system)
		overlays += image(icon = icon, icon_state = "hydrocover")

	//Updated the various alert icons.
	if(draw_warnings&& !reagents.has_reagent(SPORTDRINK))
		if(waterlevel <= 10)
			overlays += image(icon = icon, icon_state = "over_lowwater3")
		if(nutrilevel <= 2)
			overlays += image(icon = icon, icon_state = "over_lownutri3")
		if(weedlevel >= 5 || pestlevel >= 5 || toxins >= 40 || improper_heat || improper_light || improper_kpa || missing_gas)
			overlays += image(icon = icon, icon_state = "over_alert3")
		if(harvest)
			overlays += image(icon = icon, icon_state = "over_harvest3")

	// Update bioluminescence and tray light
	calculate_light()

/obj/machinery/portable_atmospherics/hydroponics/proc/calculate_light()
	var/light_out = 0
	if(light_on)
		light_out += internal_light
	if(seed&&seed.biolum)
		light_out+=(1+Ceiling(seed.potency/10))
		if(seed.biolum_colour)
			light_color = seed.biolum_colour
		else
			light_color = null
	set_light(light_out)

/obj/machinery/portable_atmospherics/hydroponics/proc/check_level_sanity()
	//Make sure various values are sane.
	if(seed)
		plant_health = clamp(plant_health, 0, seed.endurance)
	else
		plant_health = 0
		dead = 0

	mutation_level = clamp(mutation_level, 0, 100)
	nutrilevel =     clamp(nutrilevel, 0, 10)
	waterlevel =     clamp(waterlevel, 0, 100)
	pestlevel =      clamp(pestlevel, 0, 10)
	weedlevel =      clamp(weedlevel, 0, 10)
	toxins =         clamp(toxins, 0, 100)
	yield_mod = 	 clamp(yield_mod, 0, 2)
	mutation_mod = 	 clamp(mutation_mod, 0, 3)
