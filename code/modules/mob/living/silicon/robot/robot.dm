#define CYBORG_POWER_USAGE_MULTIPLIER 2.5 // Multiplier for amount of power cyborgs use.

/mob/living/silicon/robot
	name = "robot"
	real_name = "robot"
	icon = 'icons/mob/robots/robot.dmi'
	icon_state = ICON_STATE_WORLD
	maxHealth = 300
	health = 300
	mob_sort_value = 4

	z_flags = ZMM_MANGLE_PLANES

	mob_bump_flag = ROBOT
	mob_swap_flags = ROBOT|MONKEY|SLIME|SIMPLE_ANIMAL
	mob_push_flags = ~HEAVY //trundle trundle
	skillset = /datum/skillset/silicon/robot

	var/panel_icon = 'icons/mob/robots/_panels.dmi'

	var/lights_on = 0 // Is our integrated light on?
	var/used_power_this_tick = 0
	var/power_efficiency = 1
	var/sight_mode = 0
	var/custom_name = ""
	var/crisis //Admin-settable for combat module use.
	var/crisis_override = 0
	var/integrated_light_power = 0.6
	var/integrated_light_range = 4
	var/datum/wires/robot/wires
	var/module_category = ROBOT_MODULE_TYPE_GROUNDED
	var/dismantle_type = /obj/item/robot_parts/robot_suit

	var/icon_selected = TRUE //If icon selection has been completed yet

//Hud stuff

	var/obj/screen/inv1 = null
	var/obj/screen/inv2 = null
	var/obj/screen/inv3 = null
	var/obj/screen/robot_drop_grab/ui_drop_grab

	var/shown_robot_modules = 0 //Used to determine whether they have the module menu shown or not
	var/obj/screen/robot_modules_background

//3 Modules can be activated at any one time.
	var/obj/item/robot_module/module = null
	var/obj/item/module_active
	var/obj/item/module_state_1
	var/obj/item/module_state_2
	var/obj/item/module_state_3

	silicon_camera = /obj/item/camera/siliconcam/robot_camera
	silicon_radio = /obj/item/radio/borg

	var/mob/living/silicon/ai/connected_ai = null
	var/obj/item/cell/cell = /obj/item/cell/high

	var/cell_emp_mult = 2.5

	// Components are basically robot organs.
	var/list/components = list()

	var/obj/item/mmi/mmi = null

	var/opened = 0
	var/emagged = 0
	var/wiresexposed = 0
	var/locked = 1
	var/has_power = 1
	var/spawn_module = null

	var/spawn_sound = 'sound/voice/liveagain.ogg'
	var/pitch_toggle = 1
	var/list/req_access = list(access_robotics)
	var/ident = 0
	var/viewalerts = 0
	var/modtype = "Default"
	var/lower_mod = 0
	var/jetpack = 0
	var/datum/effect/effect/system/ion_trail_follow/ion_trail = null
	var/jeton = 0
	var/killswitch = 0
	var/killswitch_time = 60
	var/weapon_lock = 0
	var/weaponlock_time = 120
	var/lawupdate = 1 //Cyborgs will sync their laws with their AI by default
	var/lockcharge //If a robot is locked down
	var/speed = 0 //Cause sec borgs gotta go fast //No they dont!
	var/scrambledcodes = 0 // Used to determine if a borg shows up on the robotics console.  Setting to one hides them.
	var/tracking_entities = 0 //The number of known entities currently accessing the internal camera
	var/braintype = "Cyborg"
	var/intenselight = 0	// Whether cyborg's integrated light was upgraded
	var/vtec = FALSE

	var/list/robot_verbs_default = list(
		/mob/living/silicon/robot/proc/sensor_mode,
		/mob/living/silicon/robot/proc/robot_checklaws
	)

	light_wedge = LIGHT_WIDE

/mob/living/silicon/robot/Initialize()
	. = ..()

	add_language(/decl/language/binary, 1)
	add_language(/decl/language/machine, 1)
	add_language(/decl/language/human/common, 1)

	wires = new(src)

	robot_modules_background = new()
	robot_modules_background.icon_state = "block"
	ident = random_id(/mob/living/silicon/robot, 1, 999)

	updatename(modtype)
	update_icon()

	if(!scrambledcodes)
		set_extension(src, /datum/extension/network_device/camera/robot, null, null, null, TRUE, list(CAMERA_CHANNEL_ROBOTS), name)
		verbs |= /mob/living/silicon/robot/proc/configure_camera
	init()
	initialize_components()

	for(var/V in components) if(V != "power cell")
		var/datum/robot_component/C = components[V]
		C.installed = 1
		C.wrapped = new C.external_type

	if(ispath(cell))
		cell = new cell(src)

	if(cell)
		var/datum/robot_component/cell_component = components["power cell"]
		cell_component.wrapped = cell
		cell_component.installed = 1

	add_robot_verbs()

	// Disables lay down verb for robots due they're can't lay down and it cause some movement, vision issues.
	verbs -= /mob/living/verb/lay_down

	hud_list[HEALTH_HUD]      = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[STATUS_HUD]      = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudhealth100")
	hud_list[LIFE_HUD]        = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudhealth100")
	hud_list[ID_HUD]          = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[WANTED_HUD]      = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[IMPLOYAL_HUD]    = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[IMPCHEM_HUD]     = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[IMPTRACK_HUD]    = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")
	hud_list[SPECIALROLE_HUD] = new /image/hud_overlay('icons/mob/hud.dmi', src, "hudblank")

	AddMovementHandler(/datum/movement_handler/robot/use_power, /datum/movement_handler/mob/space)

/mob/living/silicon/robot/proc/recalculate_synth_capacities()
	if(!module || !module.synths)
		return
	var/mult = 1
	for(var/obj/item/stock_parts/matter_bin/storage in stock_parts)
		if(storage.is_functional())
			mult += storage.rating
	for(var/datum/matter_synth/M in module.synths)
		M.set_multiplier(mult)

/mob/living/silicon/robot/proc/init()
	if(ispath(module))
		new module(src)
	if(lawupdate)
		var/new_ai = select_active_ai_with_fewest_borgs(get_z(src))
		if(new_ai)
			lawupdate = 1
			connect_to_ai(new_ai)
		else
			lawupdate = 0

	playsound(loc, spawn_sound, 75, pitch_toggle)

/mob/living/silicon/robot/fully_replace_character_name(pickedName as text)
	custom_name = pickedName
	updatename()

/mob/living/silicon/robot/proc/sync()
	if(lawupdate && connected_ai)
		lawsync()
		photosync()

/mob/living/silicon/robot/drain_power(var/drain_check, var/surge, var/amount = 0)

	if(drain_check)
		return 1

	if(!cell || !cell.charge)
		return 0

	// Actual amount to drain from cell, using CELLRATE
	var/cell_amount = amount * CELLRATE

	if(cell.charge > cell_amount)
		// Spam Protection
		if(prob(10))
			to_chat(src, "<span class='danger'>Warning: Unauthorized access through power channel [rand(11,29)] detected!</span>")
		cell.use(cell_amount)
		return amount
	return 0

//If there's an MMI in the robot, have it ejected when the mob goes away. --NEO
//Improved /N
/mob/living/silicon/robot/Destroy()
	if(mmi)//Safety for when a cyborg gets dust()ed. Or there is no MMI inside.
		if(mind)
			mmi.dropInto(loc)
			if(mmi.brainmob)
				mind.transfer_to(mmi.brainmob)
			else
				to_chat(src, "<span class='danger'>Oops! Something went very wrong, your MMI was unable to receive your mind. You have been ghosted. Please make a bug report so we can fix this bug.</span>")
				ghostize()
				//ERROR("A borg has been destroyed, but its MMI lacked a brainmob, so the mind could not be transferred. Player: [ckey].")
			mmi = null
		else
			QDEL_NULL(mmi)
	if(connected_ai)
		connected_ai.connected_robots -= src
	connected_ai = null
	QDEL_NULL(module)
	QDEL_NULL(wires)
	. = ..()

/mob/living/silicon/robot/proc/reset_module(var/suppress_alert = null)
	// Clear hands and module icon.
	uneq_all()
	if(shown_robot_modules)
		hud_used.toggle_show_robot_modules()
	modtype = initial(modtype)
	if(hands)
		hands.icon_state = initial(hands.icon_state)
	// If the robot had a module and this wasn't an uncertified change, let the AI know.
	if(module)
		if (!suppress_alert)
			notify_ai(ROBOT_NOTIFICATION_MODULE_RESET, module.name)
		// Delete the module.
		module.Reset(src)
		QDEL_NULL(module)
	updatename("Default")

/mob/living/silicon/robot/proc/pick_module(var/override)
	if(module && !override)
		return

	var/decl/security_state/security_state = GET_DECL(global.using_map.security_state)
	var/is_crisis_mode = crisis_override || (crisis && security_state.current_security_level_is_same_or_higher_than(security_state.high_security_level))
	var/list/robot_modules = SSrobots.get_available_modules(module_category, is_crisis_mode, override)

	if(!override)
		if(is_crisis_mode)
			to_chat(src, SPAN_WARNING("Crisis mode active. Additional modules available."))
		modtype = input("Please select a module!", "Robot module", null, null) as null|anything in robot_modules
	else
		if(module)
			QDEL_NULL(module)
		modtype = override

	if(module || !modtype)
		return

	var/module_type = robot_modules[modtype]
	if(!module_type)
		to_chat(src, SPAN_WARNING("You are unable to select a module."))
		return

	new module_type(src)

	if(hands)
		hands.icon_state = lowertext(modtype)
	SSstatistics.add_field("cyborg_[lowertext(modtype)]",1)
	updatename()
	recalculate_synth_capacities()
	if(module)
		notify_ai(ROBOT_NOTIFICATION_NEW_MODULE, module.name)
		if(!get_crewmember_record(name) && !module.hide_on_manifest)
			CreateModularRecord(src, /datum/computer_file/report/crew_record/synth)

/mob/living/silicon/robot/get_cell()
	return cell

/mob/living/silicon/robot/proc/updatename(var/prefix as text)
	if(prefix)
		modtype = prefix

	if(istype(mmi, /obj/item/organ/internal/posibrain))
		braintype = "Robot"
	else if(istype(mmi, /obj/item/mmi/digital/robot))
		braintype = "Drone"
	else
		braintype = "Cyborg"

	var/changed_name = ""
	if(custom_name)
		changed_name = custom_name
		notify_ai(ROBOT_NOTIFICATION_NEW_NAME, real_name, changed_name)
	else
		changed_name = "[modtype] [braintype]-[num2text(ident)]"

	create_or_rename_email(changed_name, "root.rt")
	real_name = changed_name
	name = real_name
	if(mind)
		mind.name = changed_name

	//We also need to update name of internal camera.
	var/datum/extension/network_device/camera/robot/D = get_extension(src, /datum/extension/network_device)
	if(D)
		D.display_name = changed_name

	//Flavour text.
	if(client)
		var/module_flavour = client.prefs.flavour_texts_robot[modtype]
		if(module_flavour)
			flavor_text = module_flavour
		else
			flavor_text = client.prefs.flavour_texts_robot["Default"]

/mob/living/silicon/robot/verb/Namepick()
	set category = "Silicon Commands"
	if(custom_name)
		return 0

	spawn(0)
		var/newname
		newname = sanitizeName(input(src,"You are a robot. Enter a name, or leave blank for the default name.", "Name change","") as text, MAX_NAME_LEN, allow_numbers = 1)
		if (newname)
			custom_name = newname

		updatename()
		update_icon()

/mob/living/silicon/robot/verb/toggle_panel_lock()
	set name = "Toggle Panel Lock"
	set category = "Silicon Commands"
	if(!opened && has_power && do_after(usr, 60) && !opened && has_power)
		to_chat(src, "You [locked ? "un" : ""]lock your panel.")
		locked = !locked


/mob/living/silicon/robot/proc/self_diagnosis()
	if(!is_component_functioning("diagnosis unit"))
		return null

	var/dat = "<HEAD><TITLE>[src.name] Self-Diagnosis Report</TITLE></HEAD><BODY>\n"
	for (var/V in components)
		var/datum/robot_component/C = components[V]
		dat += "<b>[C.name]</b><br><table><tr><td>Brute Damage:</td><td>[C.brute_damage]</td></tr><tr><td>Electronics Damage:</td><td>[C.electronics_damage]</td></tr><tr><td>Powered:</td><td>[(!C.idle_usage || C.is_powered()) ? "Yes" : "No"]</td></tr><tr><td>Toggled:</td><td>[ C.toggled ? "Yes" : "No"]</td></table><br>"

	return dat

/mob/living/silicon/robot/verb/toggle_lights()
	set category = "Silicon Commands"
	set name = "Toggle Lights"

	if(stat == DEAD)
		return

	lights_on = !lights_on
	to_chat(usr, "You [lights_on ? "enable" : "disable"] your integrated light.")
	update_robot_light()

/mob/living/silicon/robot/verb/self_diagnosis_verb()
	set category = "Silicon Commands"
	set name = "Self Diagnosis"

	if(!is_component_functioning("diagnosis unit"))
		to_chat(src, "<span class='warning'>Your self-diagnosis component isn't functioning.</span>")
		return

	var/datum/robot_component/CO = get_component("diagnosis unit")
	if (!cell_use_power(CO.active_usage))
		to_chat(src, "<span class='warning'>Low Power.</span>")
		return
	var/dat = self_diagnosis()
	show_browser(src, dat, "window=robotdiagnosis")


/mob/living/silicon/robot/verb/toggle_component()
	set category = "Silicon Commands"
	set name = "Toggle Component"
	set desc = "Toggle a component, conserving power."

	var/list/installed_components = list()
	for(var/V in components)
		if(V == "power cell") continue
		var/datum/robot_component/C = components[V]
		if(C.installed)
			installed_components += V

	var/toggle = input(src, "Which component do you want to toggle?", "Toggle Component") as null|anything in installed_components
	if(!toggle)
		return

	var/datum/robot_component/C = components[toggle]
	if(C.toggled)
		C.toggled = 0
		to_chat(src, "<span class='warning'>You disable [C.name].</span>")
	else
		C.toggled = 1
		to_chat(src, "<span class='warning'>You enable [C.name].</span>")

/mob/living/silicon/robot/proc/configure_camera()
	set category = "Silicon Commands"
	set name = "Configure Camera"
	set desc = "Configure your internal camera's network settings."

	if(stat == DEAD)
		return

	var/datum/extension/network_device/camera/C = get_extension(src, /datum/extension/network_device/)
	if(C)
		C.ui_interact(src)

/mob/living/silicon/robot/proc/update_robot_light()
	if(lights_on)
		if(intenselight)
			set_light(integrated_light_range, min(0.8, integrated_light_power * 2))
		else
			set_light(integrated_light_range, integrated_light_power)
	else
		set_light(0)

// this function displays jetpack pressure in the stat panel
/mob/living/silicon/robot/proc/show_jetpack_pressure()
	// if you have a jetpack, show the internal tank pressure
	var/obj/item/tank/jetpack/current_jetpack = installed_jetpack()
	if (current_jetpack)
		stat("Internal Atmosphere Info", current_jetpack.name)
		stat("Tank Pressure", current_jetpack.air_contents.return_pressure())


// this function returns the robots jetpack, if one is installed
/mob/living/silicon/robot/proc/installed_jetpack()
	if(module)
		return (locate(/obj/item/tank/jetpack) in module.equipment)
	return 0


// this function displays the cyborgs current cell charge in the stat panel
/mob/living/silicon/robot/proc/show_cell_power()
	if(cell)
		stat(null, text("Charge Left: [round(cell.percent())]%"))
		stat(null, text("Cell Rating: [round(cell.maxcharge)]")) // Round just in case we somehow get crazy values
		stat(null, text("Power Cell Load: [round(used_power_this_tick)]W"))
	else
		stat(null, text("No Cell Inserted!"))


// update the status screen display
/mob/living/silicon/robot/Stat()
	. = ..()
	if (statpanel("Status"))
		show_cell_power()
		show_jetpack_pressure()
		stat(null, text("Lights: [lights_on ? "ON" : "OFF"]"))
		if(module)
			for(var/datum/matter_synth/ms in module.synths)
				stat("[ms.name]: [ms.energy]/[ms.max_energy_multiplied]")

/mob/living/silicon/robot/restrained()
	return 0

/mob/living/silicon/robot/bullet_act(var/obj/item/projectile/Proj)
	..(Proj)
	if(prob(75) && Proj.damage > 0)
		spark_at(src, 5, holder=src)
	return 2

/mob/living/silicon/robot/attackby(obj/item/W, mob/user)

	if(istype(W, /obj/item/inducer) || istype(W, /obj/item/handcuffs))
		return TRUE

	if(opened) // Are they trying to insert something?
		for(var/V in components)
			var/datum/robot_component/C = components[V]
			if(!C.installed && C.accepts_component(W))
				if(!user.unEquip(W))
					return
				C.installed = 1
				C.wrapped = W
				C.install()
				W.forceMove(null)

				var/obj/item/robot_parts/robot_component/WC = W
				if(istype(WC))
					C.brute_damage = WC.brute
					C.electronics_damage = WC.burn

				to_chat(usr, "<span class='notice'>You install the [W.name].</span>")
				return
		// If the robot is having something inserted which will remain inside it, self-inserting must be handled before exiting to avoid logic errors. Use the handle_selfinsert proc.
		if(try_stock_parts_install(W, user))
			return

	if(isWelder(W) && user.a_intent != I_HURT)
		if (src == user)
			to_chat(user, "<span class='warning'>You lack the reach to be able to repair yourself.</span>")
			return

		if (!getBruteLoss())
			to_chat(user, "Nothing to fix here!")
			return
		var/obj/item/weldingtool/WT = W
		if (WT.remove_fuel(0))
			user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
			adjustBruteLoss(-30)
			updatehealth()
			add_fingerprint(user)
			user.visible_message(SPAN_NOTICE("\The [user] has fixed some of the dents on \the [src]!"))
		else
			to_chat(user, "Need more welding fuel!")
			return

	else if(istype(W, /obj/item/stack/cable_coil) && (wiresexposed || istype(src,/mob/living/silicon/robot/drone)))
		if (!getFireLoss())
			to_chat(user, "Nothing to fix here!")
			return
		var/obj/item/stack/cable_coil/coil = W
		if (coil.use(1))
			user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
			adjustFireLoss(-30)
			updatehealth()
			user.visible_message(SPAN_NOTICE("\The [user] has fixed some of the burnt wires on \the [src]!"))

	else if(isCrowbar(W) && user.a_intent != I_HURT)	// crowbar means open or close the cover - we all know what a crowbar is by now
		if(opened)
			if(cell)
				user.visible_message("<span class='notice'>\The [user] begins clasping shut \the [src]'s maintenance hatch.</span>", "<span class='notice'>You begin closing up \the [src].</span>")
				if(do_after(user, 50, src))
					to_chat(user, "<span class='notice'>You close \the [src]'s maintenance hatch.</span>")
					opened = 0
					update_icon()

			else if(wiresexposed && wires.IsAllCut())
				//Cell is out, wires are exposed, remove MMI, produce damaged chassis, baleet original mob.
				if(!mmi)
					to_chat(user, "\The [src] has no brain to remove.")
					return

				user.visible_message("<span class='notice'>\The [user] begins ripping [mmi] from [src].</span>", "<span class='notice'>You jam the crowbar into the robot and begin levering [mmi].</span>")
				if(do_after(user, 50, src))
					dismantle(user)

			else
				// Okay we're not removing the cell or an MMI, but maybe something else?
				var/list/removable_components = list()
				for(var/V in components)
					if(V == "power cell") continue
					var/datum/robot_component/C = components[V]
					if(C.installed == 1 || C.installed == -1)
						removable_components += V
				removable_components |= stock_parts
				var/remove = input(user, "Which component do you want to pry out?", "Remove Component") as null|anything in removable_components
				if(!remove || !opened || !(remove in (stock_parts|components)) || !Adjacent(user))
					return
				var/obj/item/removed_item
				if(istype(components[remove], /datum/robot_component))
					var/datum/robot_component/C = components[remove]
					var/obj/item/robot_parts/robot_component/I = C.wrapped
					if(istype(I))
						I.brute = C.brute_damage
						I.burn = C.electronics_damage

					removed_item = I
					if(C.installed == 1)
						C.uninstall()
					C.installed = 0
				else if(istype(remove, /obj/item/stock_parts))
					stock_parts -= remove
					removed_item = remove
				if(removed_item)
					to_chat(user, SPAN_NOTICE("You remove \the [removed_item]."))
					removed_item.forceMove(loc)
		else
			if(locked)
				to_chat(user, "The cover is locked and cannot be opened.")
			else
				user.visible_message("<span class='notice'>\The [user] begins prying open \the [src]'s maintenance hatch.</span>", "<span class='notice'>You start opening \the [src]'s maintenance hatch.</span>")
				if(do_after(user, 50, src))
					to_chat(user, "<span class='notice'>You open \the [src]'s maintenance hatch.</span>")
					opened = 1
					update_icon()

	else if (istype(W, /obj/item/cell) && opened)	// trying to put a cell inside
		var/datum/robot_component/C = components["power cell"]
		if(wiresexposed)
			to_chat(user, "Close the panel first.")
		else if(cell)
			to_chat(user, "There is a power cell already installed.")
		else if(W.w_class != ITEM_SIZE_NORMAL)
			to_chat(user, "\The [W] is too [W.w_class < ITEM_SIZE_NORMAL? "small" : "large"] to fit here.")
		else if(user.unEquip(W, src))
			cell = W
			handle_selfinsert(W, user) //Just in case.
			to_chat(user, "You insert the power cell.")
			C.installed = 1
			C.wrapped = W
			C.install()
			// This means that removing and replacing a power cell will repair the mount.
			C.brute_damage = 0
			C.electronics_damage = 0

	else if(isWirecutter(W) || isMultitool(W))
		if (wiresexposed)
			wires.Interact(user)
		else
			to_chat(user, "You can't reach the wiring.")
	else if(isScrewdriver(W) && opened && !cell)	// haxing
		wiresexposed = !wiresexposed
		to_chat(user, "The wires have been [wiresexposed ? "exposed" : "unexposed"].")
		update_icon()

	else if(isScrewdriver(W) && opened && cell)	// radio
		if(silicon_radio)
			silicon_radio.attackby(W,user)//Push it to the radio to let it handle everything
		else
			to_chat(user, "Unable to locate a radio.")
		update_icon()

	else if(istype(W, /obj/item/encryptionkey/) && opened)
		if(silicon_radio)//sanityyyyyy
			silicon_radio.attackby(W,user)//GTFO, you have your own procs
		else
			to_chat(user, "Unable to locate a radio.")
	else if (istype(W, /obj/item/card/id)||istype(W, /obj/item/modular_computer)||istype(W, /obj/item/card/robot))			// trying to unlock the interface with an ID card
		if(emagged)//still allow them to open the cover
			to_chat(user, "The interface seems slightly damaged.")
		if(opened)
			to_chat(user, "You must close the cover to swipe an ID card.")
		else
			if(allowed(usr))
				locked = !locked
				to_chat(user, "You [ locked ? "lock" : "unlock"] [src]'s interface.")
				update_icon()
			else
				to_chat(user, "<span class='warning'>Access denied.</span>")
	else if(istype(W, /obj/item/borg/upgrade))
		var/obj/item/borg/upgrade/U = W
		if(!opened)
			to_chat(usr, "You must access the borgs internals!")
		else if(!src.module && U.require_module)
			to_chat(usr, "The borg must choose a module before he can be upgraded!")
		else if(U.locked)
			to_chat(usr, "The upgrade is locked and cannot be used yet!")
		else
			if(U.action(src))
				if(!user.unEquip(U, src))
					return
				to_chat(usr, "You apply the upgrade to [src]!")
				handle_selfinsert(W, user)
			else
				to_chat(usr, "Upgrade error!")

	else
		if(!(istype(W, /obj/item/robotanalyzer) || istype(W, /obj/item/scanner/health)) && W.force && user.a_intent != I_HELP)
			spark_at(src, 5, holder=src)
		return ..()

/mob/living/silicon/robot/proc/handle_selfinsert(obj/item/W, mob/user)
	if ((user == src) && istype(get_active_hand(),/obj/item/gripper))
		var/obj/item/gripper/H = get_active_hand()
		if (W.loc == H) //if this triggers something has gone very wrong, and it's safest to abort
			return
		else if (H.wrapped == W)
			H.wrapped = null

/mob/living/silicon/robot/default_help_interaction(mob/user)
	if(ishuman(user))
		user.attempt_hug(src)
		return TRUE
	. = ..()

/mob/living/silicon/robot/default_hurt_interaction(mob/user)
	var/decl/species/user_species = user.get_species()
	if(user_species?.can_shred(user))
		attack_generic(user, rand(30,50), "slashed")
		return TRUE
	. = ..()

/mob/living/silicon/robot/default_interaction(mob/user)
	if(user.a_intent != I_GRAB && opened && !wiresexposed && (!istype(user, /mob/living/silicon)))
		var/datum/robot_component/cell_component = components["power cell"]
		if(cell)
			cell.update_icon()
			cell.add_fingerprint(user)
			user.put_in_active_hand(cell)
			to_chat(user, "You remove \the [cell].")
			cell = null
			cell_component.wrapped = null
			cell_component.installed = 0
			update_icon()
		else if(cell_component.installed == -1)
			cell_component.installed = 0
			var/obj/item/broken_device = cell_component.wrapped
			to_chat(user, "You remove \the [broken_device].")
			user.put_in_active_hand(broken_device)
		return TRUE
	. = ..()

//Robots take half damage from basic attacks.
/mob/living/silicon/robot/attack_generic(var/mob/user, var/damage, var/attack_message)
	return ..(user,FLOOR(damage/2),attack_message)

/mob/living/silicon/robot/get_req_access()
	return req_access

/mob/living/silicon/robot/get_eye_overlay()
	var/eye_icon_state = "[icon_state]-eyes"
	if(check_state_in_icon(eye_icon_state, icon))
		return emissive_overlay(icon, eye_icon_state)

/mob/living/silicon/robot/on_update_icon()

	..()

	icon_state = ICON_STATE_WORLD
	if(stat == CONSCIOUS)
		var/image/eyes = get_eye_overlay()
		if(eyes)
			add_overlay(eyes)

	if(opened)
		if(wiresexposed)
			add_overlay(image(panel_icon, "ov-openpanel +w"))
		else if(cell)
			add_overlay(image(panel_icon, "ov-openpanel +c"))
		else
			add_overlay(image(panel_icon, "ov-openpanel -c"))

	if(module_active && istype(module_active, /obj/item/borg/combat/shield))
		add_overlay("[icon_state]-shield")

	var/datum/extension/hattable/hattable = get_extension(src, /datum/extension/hattable)
	var/image/hat = hattable?.get_hat_overlay(src)
	if(hat)
		add_overlay(hat)

/mob/living/silicon/robot/proc/installed_modules()
	if(weapon_lock)
		to_chat(src, "<span class='warning'>Weapon lock active, unable to use modules! Count:[weaponlock_time]</span>")
		return

	if(!module)
		pick_module()
		return
	var/dat = "<HEAD><TITLE>Modules</TITLE></HEAD><BODY>\n"
	dat += {"
	<B>Activated Modules</B>
	<BR>
	Module 1: [module_state_1 ? "<A HREF=?src=\ref[src];mod=\ref[module_state_1]>[module_state_1]<A>" : "No Module"]<BR>
	Module 2: [module_state_2 ? "<A HREF=?src=\ref[src];mod=\ref[module_state_2]>[module_state_2]<A>" : "No Module"]<BR>
	Module 3: [module_state_3 ? "<A HREF=?src=\ref[src];mod=\ref[module_state_3]>[module_state_3]<A>" : "No Module"]<BR>
	<BR>
	<B>Installed Modules</B><BR><BR>"}


	for (var/obj in module.equipment)
		if (!obj)
			dat += text("<B>Resource depleted</B><BR>")
		else if(activated(obj))
			dat += text("[obj]: <B>Activated</B><BR>")
		else
			dat += text("[obj]: <A HREF=?src=\ref[src];act=\ref[obj]>Activate</A><BR>")
	if (emagged)
		if(activated(module.emag))
			dat += text("[module.emag]: <B>Activated</B><BR>")
		else
			dat += text("[module.emag]: <A HREF=?src=\ref[src];act=\ref[module.emag]>Activate</A><BR>")
/*
		if(activated(obj))
			dat += text("[obj]: \[<B>Activated</B> | <A HREF=?src=\ref[src];deact=\ref[obj]>Deactivate</A>\]<BR>")
		else
			dat += text("[obj]: \[<A HREF=?src=\ref[src];act=\ref[obj]>Activate</A> | <B>Deactivated</B>\]<BR>")
*/
	show_browser(src, dat, "window=robotmod")


/mob/living/silicon/robot/OnSelfTopic(href_list)
	if (href_list["showalerts"])
		open_subsystem(/datum/nano_module/alarm_monitor/all)
		return TOPIC_HANDLED

	if (href_list["mod"])
		var/obj/item/O = locate(href_list["mod"])
		if (istype(O) && (O.loc == src))
			O.attack_self(src)
		return TOPIC_HANDLED

	if (href_list["act"])
		var/obj/item/O = locate(href_list["act"])
		if (!istype(O))
			return TOPIC_HANDLED

		if(!((O in module.equipment) || (O == src.module.emag)))
			return TOPIC_HANDLED

		if(activated(O))
			to_chat(src, "Already activated.")
			return TOPIC_HANDLED
		if(!module_state_1)
			module_state_1 = O
			O.hud_layerise()
			O.forceMove(src)
			if(istype(module_state_1,/obj/item/borg/sight))
				sight_mode |= module_state_1:sight_mode
		else if(!module_state_2)
			module_state_2 = O
			O.hud_layerise()
			O.forceMove(src)
			if(istype(module_state_2,/obj/item/borg/sight))
				sight_mode |= module_state_2:sight_mode
		else if(!module_state_3)
			module_state_3 = O
			O.hud_layerise()
			O.forceMove(src)
			if(istype(module_state_3,/obj/item/borg/sight))
				sight_mode |= module_state_3:sight_mode
		else
			to_chat(src, "You need to disable a module first!")
		installed_modules()
		return TOPIC_HANDLED

	if (href_list["deact"])
		var/obj/item/O = locate(href_list["deact"])
		if(activated(O))
			if(module_state_1 == O)
				module_state_1 = null
				O.forceMove(null)
			else if(module_state_2 == O)
				module_state_2 = null
				O.forceMove(null)
			else if(module_state_3 == O)
				module_state_3 = null
				O.forceMove(null)
			else
				to_chat(src, "Module isn't activated.")
		else
			to_chat(src, "Module isn't activated.")
		installed_modules()
		return TOPIC_HANDLED
	return ..()

/mob/living/silicon/robot/proc/radio_menu()
	silicon_radio.interact(src)//Just use the radio's Topic() instead of bullshit special-snowflake code


/mob/living/silicon/robot/Move(a, b, flag)

	. = ..()

	if(module)
		if(module.type == /obj/item/robot_module/janitor)
			var/turf/tile = loc
			if(isturf(tile))
				tile.clean_blood()
				if (istype(tile, /turf/simulated))
					var/turf/simulated/S = tile
					S.dirt = 0
				for(var/A in tile)
					if(istype(A, /obj/effect))
						if(istype(A, /obj/effect/rune) || istype(A, /obj/effect/decal/cleanable) || istype(A, /obj/effect/overlay))
							qdel(A)
					else if(istype(A, /obj/item))
						var/obj/item/cleaned_item = A
						cleaned_item.clean_blood()
					else if(istype(A, /mob/living/carbon/human))
						var/mob/living/carbon/human/cleaned_human = A
						if(cleaned_human.lying)
							if(cleaned_human.head)
								cleaned_human.head.clean_blood()
							if(cleaned_human.wear_suit)
								cleaned_human.wear_suit.clean_blood()
							else if(cleaned_human.w_uniform)
								cleaned_human.w_uniform.clean_blood()
							if(cleaned_human.shoes)
								cleaned_human.shoes.clean_blood()
							cleaned_human.clean_blood(1)
							to_chat(cleaned_human, "<span class='warning'>[src] cleans your face!</span>")
		return

/mob/living/silicon/robot/proc/self_destruct()
	gib()
	return

/mob/living/silicon/robot/proc/UnlinkSelf()
	disconnect_from_ai()
	lawupdate = 0
	lockcharge = 0
	scrambledcodes = 1
	//Disconnect it's camera so it's not so easily tracked.
	var/datum/extension/network_device/camera/robot/D = get_extension(src, /datum/extension/network_device)
	if(D)
		D.remove_channels(D.channels)

/mob/living/silicon/robot/proc/ResetSecurityCodes()
	set category = "Silicon Commands"
	set name = "Reset Identity Codes"
	set desc = "Scrambles your security and identification codes and resets your current buffers. Unlocks you and but permanently severs you from your AI and the robotics console and will deactivate your camera system."

	var/mob/living/silicon/robot/R = src

	if(R)
		R.UnlinkSelf()
		to_chat(R, "Buffers flushed and reset. Camera system shutdown.  All systems operational.")
		src.verbs -= /mob/living/silicon/robot/proc/ResetSecurityCodes

/mob/living/silicon/robot/proc/SetLockdown(var/state = 1)
	// They stay locked down if their wire is cut.
	if(wires.LockedCut())
		state = 1
	else if(has_zeroth_law())
		state = 0

	if(lockcharge != state)
		lockcharge = state
		UpdateLyingBuckledAndVerbStatus()
		return 1
	return 0

/mob/living/silicon/robot/mode()
	set name = "Activate Held Object"
	set category = "IC"
	set src = usr

	var/obj/item/W = get_active_hand()
	if (W)
		W.attack_self(src)

	return

/mob/living/silicon/robot/proc/choose_icon(list/module_sprites)

	set waitfor = FALSE

	if(!length(module_sprites))
		to_chat(src, "Something is badly wrong with the sprite selection. Harass a coder.")
		CRASH("Can't setup robot icon for [src] ([src.client]). Module: [module?.name]")

	icon_selected = FALSE

	var/selected_icon
	if(length(module_sprites) == 1 || !client)
		icon = module_sprites[module_sprites[1]]
	else
		var/list/options = list()
		for(var/sprite in module_sprites)
			var/image/radial_button =  image(icon = module_sprites[sprite], icon_state = ICON_STATE_WORLD)
			radial_button.overlays.Add(image(icon = module_sprites[sprite], icon_state = "[ICON_STATE_WORLD]-eyes"))
			radial_button.name = sprite
			options[sprite] = radial_button
		var/chosen_icon = show_radial_menu(src, src, options, radius = 42, tooltips = TRUE)
		if(!chosen_icon || icon_selected)
			return
		selected_icon = chosen_icon

	if(!selected_icon)
		return

	icon = module_sprites[selected_icon]
	icon_selected = TRUE
	update_icon()
	to_chat(src, "Your icon has been set. You now require a module reset to change it.")

/mob/living/silicon/robot/proc/sensor_mode() //Medical/Security HUD controller for borgs
	set name = "Set Sensor Augmentation"
	set category = "Silicon Commands"
	set desc = "Augment visual feed with internal sensor overlays."
	toggle_sensor_mode()

/mob/living/silicon/robot/proc/add_robot_verbs()
	src.verbs |= robot_verbs_default

/mob/living/silicon/robot/proc/remove_robot_verbs()
	src.verbs -= robot_verbs_default

// Uses power from cyborg's cell. Returns 1 on success or 0 on failure.
// Properly converts using CELLRATE now! Amount is in Joules.
/mob/living/silicon/robot/proc/cell_use_power(var/amount = 0)
	// No cell inserted
	if(!cell)
		return 0

	var/power_use = amount * CYBORG_POWER_USAGE_MULTIPLIER
	if(cell.checked_use(CELLRATE * power_use))
		used_power_this_tick += power_use
		return 1
	return 0

/mob/living/silicon/robot/binarycheck()
	if(is_component_functioning("comms"))
		var/datum/robot_component/RC = get_component("comms")
		use_power(RC.active_usage)
		return 1
	return 0

/mob/living/silicon/robot/proc/notify_ai(var/notifytype, var/first_arg, var/second_arg)
	if(!connected_ai)
		return
	switch(notifytype)
		if(ROBOT_NOTIFICATION_NEW_UNIT) //New Robot
			to_chat(connected_ai, "<br><br><span class='notice'>NOTICE - New [lowertext(braintype)] connection detected: <a href='byond://?src=\ref[connected_ai];track2=\ref[connected_ai];track=\ref[src]'>[name]</a></span><br>")
		if(ROBOT_NOTIFICATION_NEW_MODULE) //New Module
			to_chat(connected_ai, "<br><br><span class='notice'>NOTICE - [braintype] module change detected: [name] has loaded the [first_arg].</span><br>")
		if(ROBOT_NOTIFICATION_MODULE_RESET)
			to_chat(connected_ai, "<br><br><span class='notice'>NOTICE - [braintype] module reset detected: [name] has unloaded the [first_arg].</span><br>")
		if(ROBOT_NOTIFICATION_NEW_NAME) //New Name
			if(first_arg != second_arg)
				to_chat(connected_ai, "<br><br><span class='notice'>NOTICE - [braintype] reclassification detected: [first_arg] is now designated as [second_arg].</span><br>")
/mob/living/silicon/robot/proc/disconnect_from_ai()
	if(connected_ai)
		sync() // One last sync attempt
		connected_ai.connected_robots -= src
		connected_ai = null

/mob/living/silicon/robot/proc/connect_to_ai(var/mob/living/silicon/ai/AI)
	if(AI && AI != connected_ai)
		disconnect_from_ai()
		connected_ai = AI
		connected_ai.connected_robots |= src
		notify_ai(ROBOT_NOTIFICATION_NEW_UNIT)
		sync()

/mob/living/silicon/robot/emag_act(var/remaining_charges, var/mob/user)
	if(!opened)//Cover is closed
		if(locked)
			if(prob(90))
				to_chat(user, "You emag the cover lock.")
				locked = 0
			else
				to_chat(user, "You fail to emag the cover lock.")
				to_chat(src, "Hack attempt detected.")
			return 1
		else
			to_chat(user, "The cover is already unlocked.")
		return

	if(opened) //Cover is open
		if(emagged)
			return //Prevents the X has hit Y with Z message also you cant emag them twice
		if(wiresexposed)
			to_chat(user, "You must close the panel first.")
			return
		else
			sleep(6)
			if(prob(50))
				emagged = 1
				lawupdate = 0
				disconnect_from_ai()
				to_chat(user, "You emag [src]'s interface.")
				log_and_message_admins("emagged cyborg [key_name_admin(src)].  Laws overridden.", src)
				clear_supplied_laws()
				clear_inherent_laws()
				laws = new /datum/ai_laws/syndicate_override
				var/time = time2text(world.realtime,"hh:mm:ss")
				global.lawchanges.Add("[time] <B>:</B> [user.name]([user.key]) emagged [name]([key])")
				var/decl/pronouns/G = user.get_pronouns(ignore_coverings = TRUE)
				set_zeroth_law("Only [user.real_name] and people [G.he] designate[G.s] as being such are operatives.")
				SetLockdown(0)
				. = 1
				spawn()
					to_chat(src, "<span class='danger'>ALERT: Foreign software detected.</span>")
					sleep(5)
					to_chat(src, "<span class='danger'>Initiating diagnostics...</span>")
					sleep(20)
					to_chat(src, "<span class='danger'>SynBorg v1.7.1 loaded.</span>")
					sleep(5)
					to_chat(src, "<span class='danger'>LAW SYNCHRONISATION ERROR</span>")
					sleep(5)
					to_chat(src, "<span class='danger'>Would you like to send a report to the vendor? Y/N</span>")
					sleep(10)
					to_chat(src, "<span class='danger'>> N</span>")
					sleep(20)
					to_chat(src, "<span class='danger'>ERRORERRORERROR</span>")
					to_chat(src, "<b>Obey these laws:</b>")
					laws.show_laws(src)
					to_chat(src, "<span class='danger'>ALERT: [user.real_name] is your new master. Obey your new laws and his commands.</span>")
					if(module)
						module.handle_emagged()
					update_icon()
			else
				to_chat(user, "You fail to hack [src]'s interface.")
				to_chat(src, "Hack attempt detected.")
			return 1

/mob/living/silicon/robot/incapacitated(var/incapacitation_flags = INCAPACITATION_DEFAULT)
	if ((incapacitation_flags & INCAPACITATION_FORCELYING) && (lockcharge || !is_component_functioning("actuator")))
		return 1
	if ((incapacitation_flags & INCAPACITATION_KNOCKOUT) && !is_component_functioning("actuator"))
		return 1
	return ..()

/mob/living/silicon/robot/proc/dismantle(var/mob/user)
	to_chat(user, SPAN_NOTICE("You damage some parts of the chassis, but eventually manage to rip out the central processor."))
	var/obj/item/robot_parts/robot_suit/C = new dismantle_type(loc)
	C.dismantled_from(src)
	qdel(src)

/mob/living/silicon/robot/try_stock_parts_install(obj/item/stock_parts/W, mob/user)
	if(!opened)
		return
	. = ..()
	if(.)
		handle_selfinsert(W, user)
		recalculate_synth_capacities()

/mob/living/silicon/robot/get_admin_job_string()
	return ASSIGNMENT_ROBOT

/mob/living/silicon/robot/handle_pre_transformation()
	QDEL_NULL(mmi)
