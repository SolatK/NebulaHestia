/*
Contains most of the procs that are called when a mob is attacked by something

bullet_act
ex_act
meteor_act

*/

/mob/living/carbon/human/bullet_act(var/obj/item/projectile/P, var/def_zone)

	def_zone = check_zone(def_zone, src)
	if(!has_organ(def_zone))
		return PROJECTILE_FORCE_MISS //if they don't have the organ in question then the projectile just passes by.

	//Shields
	var/shield_check = check_shields(P.damage, P, null, def_zone, "the [P.name]")
	if(shield_check)
		if(shield_check < 0)
			return shield_check
		else
			P.on_hit(src, 100, def_zone)
			return 100

	var/blocked = ..(P, def_zone)

	radio_interrupt_cooldown = world.time + (RADIO_INTERRUPT_DEFAULT * 0.8)

	return blocked

/mob/living/carbon/human/stun_effect_act(var/stun_amount, var/agony_amount, var/def_zone)
	var/obj/item/organ/external/affected = get_organ(def_zone)
	if(!affected)
		return

	var/siemens_coeff = get_siemens_coefficient_organ(affected)
	stun_amount *= siemens_coeff
	agony_amount *= siemens_coeff
	agony_amount *= affected.get_agony_multiplier()

	affected.stun_act(stun_amount, agony_amount)

	radio_interrupt_cooldown = world.time + RADIO_INTERRUPT_DEFAULT

	if(!affected.can_feel_pain() || (GET_CHEMICAL_EFFECT(src, CE_PAINKILLER)/3 > agony_amount)) //stops blurry eyes and stutter if you can't feel pain
		agony_amount = 0

	..(stun_amount, agony_amount, def_zone)

/mob/living/carbon/human/get_blocked_ratio(def_zone, damage_type, damage_flags, armor_pen, damage)
	if(!def_zone && (damage_flags & DAM_DISPERSED))
		var/tally
		for(var/zone in organ_rel_size)
			tally += organ_rel_size[zone]
		for(var/zone in organ_rel_size)
			def_zone = zone
			. += .() * organ_rel_size/tally
		return
	return ..()

/mob/living/carbon/human/get_armors_by_zone(obj/item/organ/external/def_zone, damage_type, damage_flags)
	if(!def_zone)
		def_zone = ran_zone()
	if(!istype(def_zone))
		def_zone = get_organ(def_zone)
	if(!def_zone)
		return ..()

	. = list()
	var/list/protective_gear = list(head, wear_mask, wear_suit, w_uniform, gloves, shoes)
	for(var/obj/item/clothing/gear in protective_gear)
		if(gear.accessories.len)
			for(var/obj/item/clothing/accessory/bling in gear.accessories)
				if(bling.body_parts_covered & def_zone.body_part)
					var/armor = get_extension(bling, /datum/extension/armor)
					if(armor)
						. += armor
		if(gear.body_parts_covered & def_zone.body_part)
			var/armor = get_extension(gear, /datum/extension/armor)
			if(armor)
				. += armor

	// Add inherent armor to the end of list so that protective equipment is checked first
	. += ..()

//this proc returns the Siemens coefficient of electrical resistivity for a particular external organ.
/mob/living/carbon/human/proc/get_siemens_coefficient_organ(var/obj/item/organ/external/def_zone)
	if (!def_zone)
		return 1.0

	var/siemens_coefficient = max(species.siemens_coefficient,0)

	var/list/clothing_items = list(head, wear_mask, wear_suit, w_uniform, gloves, shoes) // What all are we checking?
	for(var/obj/item/clothing/C in clothing_items)
		if(istype(C) && (C.body_parts_covered & def_zone.body_part)) // Is that body part being targeted covered?
			siemens_coefficient *= C.siemens_coefficient

	return siemens_coefficient

/mob/living/carbon/human/proc/check_head_coverage()

	var/list/body_parts = list(head, wear_mask, wear_suit, w_uniform)
	for(var/bp in body_parts)
		if(!bp)	continue
		if(bp && istype(bp ,/obj/item/clothing))
			var/obj/item/clothing/C = bp
			if(C.body_parts_covered & SLOT_HEAD)
				return 1
	return 0

//Used to check if they can be fed food/drinks/pills
/mob/living/carbon/human/check_mouth_coverage()
	var/list/protective_gear = list(head, wear_mask, wear_suit, w_uniform)
	for(var/obj/item/gear in protective_gear)
		if(istype(gear) && (gear.body_parts_covered & SLOT_FACE) && !(gear.item_flags & ITEM_FLAG_FLEXIBLEMATERIAL))
			return gear

/mob/living/carbon/human/proc/check_shields(var/damage = 0, var/atom/damage_source = null, var/mob/attacker = null, var/def_zone = null, var/attack_text = "the attack")
	var/list/checking_slots = get_held_items()
	LAZYDISTINCTADD(checking_slots, wear_suit)
	for(var/obj/item/shield in checking_slots)
		if(shield.handle_shield(src, damage, damage_source, attacker, def_zone, attack_text))
			return TRUE
	return FALSE

/mob/living/carbon/human/resolve_item_attack(obj/item/I, mob/living/user, var/target_zone)

	for (var/obj/item/grab/G in grabbed_by)
		if(G.resolve_item_attack(user, I, target_zone))
			return null

	if(user == src) // Attacking yourself can't miss
		return target_zone

	var/accuracy_penalty = user.melee_accuracy_mods()
	accuracy_penalty += 10*get_skill_difference(SKILL_COMBAT, user)
	accuracy_penalty += 10*(I.w_class - ITEM_SIZE_NORMAL)
	accuracy_penalty -= I.melee_accuracy_bonus

	var/hit_zone = get_zone_with_miss_chance(target_zone, src, accuracy_penalty)

	if(!hit_zone)
		visible_message("<span class='danger'>\The [user] misses [src] with \the [I]!</span>")
		return null

	if(check_shields(I.force, I, user, target_zone, "the [I.name]"))
		return null

	var/obj/item/organ/external/affecting = get_organ(hit_zone)
	if (!affecting || affecting.is_stump())
		to_chat(user, "<span class='danger'>They are missing that limb!</span>")
		return null

	return hit_zone

/mob/living/carbon/human/hit_with_weapon(obj/item/I, mob/living/user, var/effective_force, var/hit_zone)
	var/obj/item/organ/external/affecting = get_organ(hit_zone)
	if(!affecting)
		return //should be prevented by attacked_with_item() but for sanity.

	var/weapon_mention
	if(I.attack_message_name())
		weapon_mention = " with [I.attack_message_name()]"
	if(effective_force)
		visible_message("<span class='danger'>[src] has been [I.attack_verb.len? pick(I.attack_verb) : "attacked"] in the [affecting.name][weapon_mention] by [user]!</span>")
	else
		visible_message("<span class='warning'>[src] has been [I.attack_verb.len? pick(I.attack_verb) : "attacked"] in the [affecting.name][weapon_mention] by [user]!</span>")
		return // If it has no force then no need to do anything else.

	return standard_weapon_hit_effects(I, user, effective_force, hit_zone)

/mob/living/carbon/human/standard_weapon_hit_effects(obj/item/I, mob/living/user, var/effective_force, var/hit_zone)
	var/obj/item/organ/external/affecting = get_organ(hit_zone)
	if(!affecting)
		return 0

	var/blocked = get_blocked_ratio(hit_zone, I.damtype, I.damage_flags(), I.armor_penetration, I.force)
	// Handle striking to cripple.
	if(user.a_intent == I_DISARM)
		effective_force *= 0.66 //reduced effective force...
		if(!..(I, user, effective_force, hit_zone))
			return 0

		//set the dislocate mult less than the effective force mult so that
		//dislocating limbs on disarm is a bit easier than breaking limbs on harm
		attack_joint(affecting, I, effective_force, 0.5, blocked) //...but can dislocate joints
	else if(!..())
		return 0

	if(effective_force > 10 || effective_force >= 5 && prob(33))
		forcesay(global.hit_appends)	//forcesay checks stat already
		radio_interrupt_cooldown = world.time + (RADIO_INTERRUPT_DEFAULT * 0.8) //getting beat on can briefly prevent radio use

	if((I.damtype == BRUTE || I.damtype == PAIN) && prob(25 + (effective_force * 2)))
		if(!stat)
			if(headcheck(hit_zone))
				//Harder to score a stun but if you do it lasts a bit longer
				if(prob(effective_force))
					apply_effect(20, PARALYZE, blocked)
					if(lying)
						visible_message("<span class='danger'>[src] [species.knockout_message]</span>")
			else
				//Easier to score a stun but lasts less time
				if(prob(effective_force + 5))
					apply_effect(3, WEAKEN, blocked)
					if(lying)
						visible_message("<span class='danger'>[src] has been knocked down!</span>")

		//Apply blood
		attack_bloody(I, user, effective_force, hit_zone)

		animate_receive_damage(src)

	return 1

/mob/living/carbon/human/proc/attack_bloody(obj/item/W, mob/attacker, var/effective_force, var/hit_zone)
	if(W.damtype != BRUTE)
		return

	//make non-sharp low-force weapons less likely to be bloodied
	if(W.sharp || prob(effective_force*4))
		if(!(W.atom_flags & ATOM_FLAG_NO_BLOOD))
			W.add_blood(src)
	else
		return //if the weapon itself didn't get bloodied than it makes little sense for the target to be bloodied either

	//getting the weapon bloodied is easier than getting the target covered in blood, so run prob() again
	if(prob(33 + W.sharp*10))
		var/turf/location = loc
		if(istype(location, /turf/simulated))
			location.add_blood(src)
		if(ishuman(attacker))
			var/mob/living/carbon/human/H = attacker
			if(get_dist(H, src) <= 1) //people with TK won't get smeared with blood
				H.bloody_body(src)
				H.bloody_hands(src)

		switch(hit_zone)
			if(BP_HEAD)
				if(wear_mask)
					wear_mask.add_blood(src)
					update_inv_wear_mask(0)
				if(head)
					head.add_blood(src)
					update_inv_head(0)
				if(glasses && prob(33))
					glasses.add_blood(src)
					update_inv_glasses(0)
			if(BP_CHEST)
				bloody_body(src)

/mob/living/carbon/human/proc/projectile_hit_bloody(obj/item/projectile/P, var/effective_force, var/hit_zone, var/obj/item/organ/external/organ)
	if(P.damage_type != BRUTE || P.nodamage)
		return
	if(!(P.sharp || prob(effective_force*4)))
		return
	if(prob(effective_force))
		var/turf/location = loc
		if(istype(location, /turf/simulated))
			location.add_blood(src)
		if(hit_zone)
			organ = get_organ(hit_zone)
		var/list/bloody = get_covering_equipped_items(organ.body_part)
		for(var/obj/item/clothing/C in bloody)
			C.add_blood(src)
			C.update_clothing_icon()

/mob/living/carbon/human/proc/attack_joint(var/obj/item/organ/external/organ, var/obj/item/W, var/effective_force, var/dislocate_mult, var/blocked)
	if(!organ || (organ.dislocated == 2) || (organ.dislocated == -1) || blocked >= 100)
		return 0
	if(W.damtype != BRUTE)
		return 0

	//want the dislocation chance to be such that the limb is expected to dislocate after dealing a fraction of the damage needed to break the limb
	var/dislocate_chance = effective_force/(dislocate_mult * organ.min_broken_damage * config.organ_health_multiplier)*100
	if(prob(dislocate_chance * blocked_mult(blocked)))
		visible_message("<span class='danger'>[src]'s [organ.joint] [pick("gives way","caves in","crumbles","collapses")]!</span>")
		organ.dislocate(1)
		return 1
	return 0

/mob/living/carbon/human/emag_act(var/remaining_charges, mob/user, var/emag_source)
	var/obj/item/organ/external/affecting = get_organ(user.zone_sel.selecting)
	if(!affecting || !affecting.is_robotic())
		to_chat(user, "<span class='warning'>That limb isn't robotic.</span>")
		return -1
	if(affecting.status & ORGAN_SABOTAGED)
		to_chat(user, "<span class='warning'>[src]'s [affecting.name] is already sabotaged!</span>")
		return -1
	to_chat(user, "<span class='notice'>You sneakily slide [emag_source] into the dataport on [src]'s [affecting.name] and short out the safeties.</span>")
	affecting.status |= ORGAN_SABOTAGED
	return 1

//this proc handles being hit by a thrown atom
/mob/living/carbon/human/hitby(atom/movable/AM, var/datum/thrownthing/TT)

	if(istype(AM,/obj/))
		var/obj/O = AM

		if(in_throw_mode && !get_active_hand() && TT.speed <= THROWFORCE_SPEED_DIVISOR)	//empty active hand and we're in throw mode
			if(!incapacitated())
				if(isturf(O.loc))
					put_in_active_hand(O)
					visible_message("<span class='warning'>[src] catches [O]!</span>")
					throw_mode_off()
					process_momentum(AM, TT)
					return

		var/dtype = O.damtype
		var/throw_damage = O.throwforce*(TT.speed/THROWFORCE_SPEED_DIVISOR)

		var/zone = BP_CHEST
		if (TT.target_zone)
			zone = check_zone(TT.target_zone, src)
		else
			zone = ran_zone()	//Hits a random part of the body, -was already geared towards the chest

		//check if we hit
		var/miss_chance = max(15*(TT.dist_travelled-2),0)
		zone = get_zone_with_miss_chance(zone, src, miss_chance, ranged_attack=1)

		if(zone && TT.thrower && TT.thrower != src)
			var/shield_check = check_shields(throw_damage, O, TT.thrower, zone, "[O]")
			if(shield_check == PROJECTILE_FORCE_MISS)
				zone = null
			else if(shield_check)
				return

		var/obj/item/organ/external/affecting = (zone && get_organ(zone))
		if(!affecting)
			visible_message(SPAN_NOTICE("\The [O] misses \the [src] narrowly!"))
			return

		var/datum/wound/created_wound
		visible_message(SPAN_DANGER("\The [src] has been hit in \the [affecting.name] by \the [O]."))
		created_wound = apply_damage(throw_damage, dtype, zone, O.damage_flags(), O, O.armor_penetration)

		if(TT.thrower)
			var/client/assailant = TT.thrower.client
			if(assailant)
				admin_attack_log(TT.thrower, src, "Threw \an [O] at their victim.", "Had \an [O] thrown at them", "threw \an [O] at")

		//thrown weapon embedded object code.
		if(dtype == BRUTE && istype(O,/obj/item))
			var/obj/item/I = O
			if (!is_robot_module(I))
				var/sharp = I.can_embed()
				var/damage = throw_damage //the effective damage used for embedding purposes, no actual damage is dealt here
				damage *= (1 - get_blocked_ratio(zone, BRUTE, O.damage_flags(), O.armor_penetration, I.force))

				//blunt objects should really not be embedding in things unless a huge amount of force is involved
				var/embed_chance = sharp? damage/I.w_class : damage/(I.w_class*3)
				var/embed_threshold = sharp? 5*I.w_class : 15*I.w_class

				//Sharp objects will always embed if they do enough damage.
				//Thrown sharp objects have some momentum already and have a small chance to embed even if the damage is below the threshold
				if((sharp && prob(damage/(10*I.w_class)*100)) || (damage > embed_threshold && prob(embed_chance)))
					affecting.embed(I, supplied_wound = created_wound)
					I.has_embedded()

		process_momentum(AM, TT)

	else
		..()

/mob/living/carbon/human/embed(var/obj/O, var/def_zone=null, var/datum/wound/supplied_wound)
	if(!def_zone) ..()

	var/obj/item/organ/external/affecting = get_organ(def_zone)
	if(affecting)
		affecting.embed(O, supplied_wound = supplied_wound)

/mob/living/carbon/human/proc/bloody_hands(var/mob/living/source, var/amount = 2)
	var/obj/item/clothing/gloves/gloves = get_equipped_item(slot_gloves_str)
	if(istype(gloves))
		gloves.add_blood(source, amount)
	else
		add_blood(source, amount)
	update_inv_gloves()		//updates on-mob overlays for bloody hands and/or bloody gloves

/mob/living/carbon/human/proc/bloody_body(var/mob/living/source)
	if(wear_suit)
		wear_suit.add_blood(source)
		update_inv_wear_suit(0)
	if(w_uniform)
		w_uniform.add_blood(source)
		update_inv_w_uniform(0)

/mob/living/carbon/human/proc/handle_suit_punctures(var/damtype, var/damage, var/def_zone)

	// Tox and oxy don't matter to suits.
	if(damtype != BURN && damtype != BRUTE) return

	// The rig might soak this hit, if we're wearing one.
	if(back && istype(back,/obj/item/rig))
		var/obj/item/rig/rig = back
		rig.take_hit(damage)

	// We may also be taking a suit breach.
	if(!wear_suit) return
	if(!istype(wear_suit,/obj/item/clothing/suit/space)) return
	var/obj/item/clothing/suit/space/SS = wear_suit
	SS.create_breaches(damtype, damage)

/mob/living/carbon/human/reagent_permeability()
	var/perm = 0

	var/list/perm_by_part = list(
		"head" = THERMAL_PROTECTION_HEAD,
		"upper_torso" = THERMAL_PROTECTION_UPPER_TORSO,
		"lower_torso" = THERMAL_PROTECTION_LOWER_TORSO,
		"legs" = THERMAL_PROTECTION_LEG_LEFT + THERMAL_PROTECTION_LEG_RIGHT,
		"feet" = THERMAL_PROTECTION_FOOT_LEFT + THERMAL_PROTECTION_FOOT_RIGHT,
		"arms" = THERMAL_PROTECTION_ARM_LEFT + THERMAL_PROTECTION_ARM_RIGHT,
		"hands" = THERMAL_PROTECTION_HAND_LEFT + THERMAL_PROTECTION_HAND_RIGHT
		)

	for(var/obj/item/clothing/C in src.get_equipped_items())
		if(C.permeability_coefficient == 1 || !C.body_parts_covered)
			continue
		if(C.body_parts_covered & SLOT_HEAD)
			perm_by_part["head"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_UPPER_BODY)
			perm_by_part["upper_torso"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_LOWER_BODY)
			perm_by_part["lower_torso"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_LEGS)
			perm_by_part["legs"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_FEET)
			perm_by_part["feet"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_ARMS)
			perm_by_part["arms"] *= C.permeability_coefficient
		if(C.body_parts_covered & SLOT_HANDS)
			perm_by_part["hands"] *= C.permeability_coefficient

	for(var/part in perm_by_part)
		perm += perm_by_part[part]

	return perm

/mob/living/carbon/human/lava_act(datum/gas_mixture/air, temperature, pressure)
	var/was_burned = FireBurn(0.4 * vsc.fire_firelevel_multiplier, temperature, pressure)
	if (was_burned)
		fire_act(air, temperature)
	return FALSE

//Removed the horrible safety parameter. It was only being used by ninja code anyways.
//Now checks siemens_coefficient of the affected area by default
/mob/living/carbon/human/electrocute_act(var/shock_damage, var/obj/source, var/base_siemens_coeff = 1.0, var/def_zone = null)

	if(status_flags & GODMODE)	return 0	//godmode

	if(species.siemens_coefficient == -1)
		if(stored_shock_by_ref["\ref[src]"])
			stored_shock_by_ref["\ref[src]"] += shock_damage
		else
			stored_shock_by_ref["\ref[src]"] = shock_damage
		return

	if (!def_zone)
		def_zone = pick(BP_L_HAND, BP_R_HAND)

	return ..(shock_damage, source, base_siemens_coeff, def_zone)

/mob/living/carbon/human/explosion_act(severity)
	..()
	var/b_loss = null
	var/f_loss = null
	switch (severity)
		if(1)
			b_loss = 400
			f_loss = 100
			var/atom/target = get_edge_target_turf(src, get_dir(src, get_step_away(src, src)))
			throw_at(target, 200, 4)
		if(2)
			b_loss = 60
			f_loss = 60
			if (get_sound_volume_multiplier() >= 0.2)
				SET_STATUS_MAX(src, STAT_TINNITUS, 30)
				SET_STATUS_MAX(src, STAT_DEAF, 120)
			if(prob(70))
				SET_STATUS_MAX(src, STAT_PARA, 10)
		if(3)
			b_loss = 30
			if (get_sound_volume_multiplier() >= 0.2)
				SET_STATUS_MAX(src, STAT_TINNITUS, 15)
				SET_STATUS_MAX(src, STAT_DEAF, 60)
			if (prob(50))
				SET_STATUS_MAX(src, STAT_PARA, 10)

	// focus most of the blast on one organ
	apply_damage(0.7 * b_loss, BRUTE, null, DAM_EXPLODE, used_weapon = "Explosive blast")
	apply_damage(0.7 * f_loss, BURN, null, DAM_EXPLODE, used_weapon = "Explosive blast")

	// distribute the remaining 30% on all limbs equally (including the one already dealt damage)
	apply_damage(0.3 * b_loss, BRUTE, null, DAM_EXPLODE | DAM_DISPERSED, used_weapon = "Explosive blast")
	apply_damage(0.3 * f_loss, BURN, null, DAM_EXPLODE | DAM_DISPERSED, used_weapon = "Explosive blast")

//Used by various things that knock people out by applying blunt trauma to the head.
//Checks that the species has a "head" (brain containing organ) and that hit_zone refers to it.
/mob/living/carbon/human/proc/headcheck(var/target_zone, var/brain_tag = BP_BRAIN)

	var/obj/item/organ/affecting = get_internal_organ(brain_tag)

	target_zone = check_zone(target_zone, src)
	if(!affecting || affecting.parent_organ != target_zone)
		return 0

	//if the parent organ is significantly larger than the brain organ, then hitting it is not guaranteed
	var/obj/item/organ/parent = get_organ(target_zone)
	if(!parent)
		return 0

	if(parent.w_class > affecting.w_class + 1)
		return prob(100 / 2**(parent.w_class - affecting.w_class - 1))

	return 1

///eyecheck()
///Returns a number between -1 to 2
/mob/living/carbon/human/eyecheck()
	var/total_protection = flash_protection
	if(species.has_organ[species.vision_organ])
		var/obj/item/organ/internal/eyes/I = get_internal_organ(species.vision_organ)
		if(!I?.is_usable())
			return FLASH_PROTECTION_MAJOR
		total_protection = I.get_total_protection(flash_protection)
	else // They can't be flashed if they don't have eyes.
		return FLASH_PROTECTION_MAJOR
	return total_protection

/mob/living/carbon/human/flash_eyes(var/intensity = FLASH_PROTECTION_MODERATE, override_blindness_check = FALSE, affect_silicon = FALSE, visual = FALSE, type = /obj/screen/fullscreen/flash)
	if(species.has_organ[species.vision_organ])
		var/obj/item/organ/internal/eyes/I = get_internal_organ(species.vision_organ)
		if(!isnull(I))
			I.additional_flash_effects(intensity)
	return ..()

/mob/living/carbon/human/proc/getFlashMod()
	if(species.vision_organ)
		var/obj/item/organ/internal/eyes/I = get_internal_organ(species.vision_organ)
		if(istype(I))
			return I.flash_mod
	return species.flash_mod
