/obj/item/clothing/proc/can_attach_accessory(obj/item/clothing/accessory/A)
	if(valid_accessory_slots && istype(A) && (A.slot in valid_accessory_slots))
		.=1
	else
		return 0
	if(accessories.len && restricted_accessory_slots && (A.slot in restricted_accessory_slots))
		for(var/obj/item/clothing/accessory/AC in accessories)
			if (AC.slot == A.slot)
				return 0

// Override for action buttons.
/obj/item/clothing/attack_self(mob/user)
	if(loc == user && user.get_active_hand() != src)
		attack_hand(user)
	else
		. = ..()

/obj/item/clothing/attackby(var/obj/item/I, var/mob/user)
	if(istype(I, /obj/item/clothing/accessory))

		if(!valid_accessory_slots || !valid_accessory_slots.len)
			to_chat(usr, "<span class='warning'>You cannot attach accessories of any kind to \the [src].</span>")
			return

		var/obj/item/clothing/accessory/A = I
		if(can_attach_accessory(A))
			if(!user.unEquip(A))
				return
			attach_accessory(user, A)
			return
		else
			to_chat(user, "<span class='warning'>You cannot attach more accessories of this type to [src].</span>")
		return

	if(length(accessories))
		for(var/obj/item/clothing/accessory/A in accessories)
			A.attackby(I, user)
		return

	. = ..()

/obj/item/clothing/attack_hand(var/mob/user)
	//only forward to the attached accessory if the clothing is equipped (not in a storage)
	if(accessories.len && src.loc == user)
		for(var/obj/item/clothing/accessory/A in accessories)
			A.attack_hand(user)
		return
	return ..()

/obj/item/clothing/check_mousedrop_adjacency(var/atom/over, var/mob/user)
	. = (loc == user && istype(over, /obj/screen)) || ..()

/obj/item/clothing/handle_mouse_drop(atom/over, mob/user)
	if(ishuman(user) && loc == user && istype(over, /obj/screen/inventory))
		var/obj/screen/inventory/inv = over
		add_fingerprint(user)
		if(user.unEquip(src))
			user.equip_to_slot_if_possible(src, inv.slot_id)
		return TRUE
	. = ..()

/obj/item/clothing/proc/update_accessory_slowdown()
	slowdown_accessory = 0
	for(var/obj/item/clothing/accessory/A in accessories)
		slowdown_accessory += A.slowdown

/**
 *  Attach accessory A to src
 *
 *  user is the user doing the attaching. Can be null, such as when attaching
 *  items on spawn
 */
/obj/item/clothing/proc/attach_accessory(mob/user, obj/item/clothing/accessory/A)
	if(A in accessories)
		return
	accessories += A
	A.on_attached(src, user)
	if(A.removable)
		src.verbs |= /obj/item/clothing/proc/removetie_verb
	update_accessory_slowdown()
	update_icon()
	update_clothing_icon()

/obj/item/clothing/proc/remove_accessory(mob/user, obj/item/clothing/accessory/A)
	if(!A || !(A in accessories))
		return

	A.on_removed(user)
	accessories -= A
	update_accessory_slowdown()
	update_icon()
	update_clothing_icon()

/obj/item/clothing/proc/removetie_verb()
	set name = "Remove Accessory"
	set category = "Object"
	set src in usr

	if(!isliving(usr))
		return

	var/mob/living/player = usr

	if(player.stat)
		return

	if(!LAZYLEN(accessories))
		return

	var/obj/item/clothing/accessory/target_to_remove = null
	if(LAZYLEN(accessories) > 1)
		var/list/options = list()
		for(var/obj/item/clothing/accessory/equipped AS_ANYTHING in accessories)
			var/image/radial_button = image(icon = equipped.icon, icon_state = equipped.icon_state)
			options[equipped] = radial_button
		target_to_remove = show_radial_menu(player, player, options, radius = 42, tooltips = TRUE)
	else
		target_to_remove = accessories[1]

	remove_accessory(usr, target_to_remove)

	if(!LAZYLEN(accessories))
		verbs -= /obj/item/clothing/proc/removetie_verb

/obj/item/clothing/AltClick(var/mob/user)
	if(CanPhysicallyInteract(user))
		removetie_verb()

/obj/item/clothing/emp_act(severity)
	if(length(accessories))
		for(var/obj/item/clothing/accessory/A in accessories)
			A.emp_act(severity)
	..()