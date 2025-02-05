/* SURGERY STEPS */

/obj/
	var/surgery_odds = 0 // Used for tables/etc which can have surgery done of them.

/datum/surgery_step
	var/priority = 0	//steps with higher priority would be attempted first

	var/req_open = 1	//1 means the part must be cut open, 0 means it doesn't

	// type path referencing tools that can be used for this step, and how well are they suited for it
	var/list/allowed_tools = null
	// type paths referencing races that this step applies to.
	var/list/allowed_species = null
	var/list/disallowed_species = null

	// duration of the step
	var/min_duration = 0
	var/max_duration = 0

	// evil infection stuff that will make everyone hate me
	var/can_infect = 0
	//How much blood this step can get on surgeon. 1 - hands, 2 - full body.
	var/blood_level = 0

	//returns how well tool is suited for this step
	proc/tool_quality(obj/item/tool)
		for (var/T in allowed_tools)
			if (istype(tool,T))
				return allowed_tools[T]
		return 0

	// Checks if this step applies to the user mob at all
	proc/is_valid_target(mob/living/carbon/human/target)
		if(!hasorgans(target))
			return 0

		if(allowed_species)
			for(var/species in allowed_species)
				if(target.species.get_bodytype() == species)
					return 1

		if(disallowed_species)
			for(var/species in disallowed_species)
				if(target.species.get_bodytype() == species)
					return 0

		return 1


	// checks whether this step can be applied with the given user and target
	proc/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
		return 0

	// does stuff to begin the step, usually just printing messages. Moved germs transfering and bloodying here too
	proc/begin_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
		var/obj/item/organ/external/affected = target.get_organ(target_zone)
		if (can_infect && affected)
			spread_germs_to_organ(affected, user)
		if (ishuman(user) && prob(60))
			var/mob/living/carbon/human/H = user
			if (blood_level)
				H.bloody_hands(target,0)
			if (blood_level > 1)
				H.bloody_body(target,0)
		return

	// does stuff to end the step, which is normally print a message + do whatever this step changes
	proc/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
		return

	// stuff that happens when the step fails
	proc/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
		return null

/proc/spread_germs_to_organ(var/obj/item/organ/external/E, var/mob/living/carbon/human/user)
	if(!istype(user) || !istype(E)) return

	var/germ_level = user.germ_level
	if(user.gloves)
		germ_level = user.gloves.germ_level

	E.germ_level = max(germ_level,E.germ_level) //as funny as scrubbing microbes out with clean gloves is - no.


/obj/item/proc/can_do_surgery(mob/living/carbon/M, mob/living/user)
//	if(M == user)
//		return 0
	if(!ishuman(M))
		return 1
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/external/affected = H.get_organ(user.zone_sel.selecting)
	if(affected)
		for(var/datum/surgery_step/S in surgery_steps)
			if(!affected.open && S.req_open)
				return 0
	return 0

/obj/item/proc/do_surgery(mob/living/carbon/M, mob/living/user)
	if(!istype(M))
		return 0
	if (user.a_intent == I_HURT)	//check for Hippocratic Oath
		return 0
	var/zone = user.zone_sel.selecting
	if(zone in M.op_stage.in_progress) //Can't operate on someone repeatedly.
		user << "<span class='warning'>You can't operate on this area while surgery is already in progress.</span>"
		return 1
	for(var/datum/surgery_step/S in surgery_steps)
		//check if tool is right or close enough and if this step is possible
		if(S.tool_quality(src))
			var/step_is_valid = S.can_use(user, M, zone, src)
			if(step_is_valid && S.is_valid_target(M))

				if(M == user)	// Once we determine if we can actually do a step at all, give a slight delay to self-surgery to confirm attempts.
					to_chat(user, "<span class='critical'>You focus on attempting to perform surgery upon yourself.</span>")

					if(!do_after(user, 3 SECONDS, M))
						return 0

				if(step_is_valid == SURGERY_FAILURE) // This is a failure that already has a message for failing.
					return 1
				M.op_stage.in_progress += zone
				S.begin_step(user, M, zone, src)		//start on it
				var/success = TRUE

				// Bad tools make it less likely to succeed.
				if(!prob(S.tool_quality(src)))
					success = FALSE

				// Bad or no surface may mean failure as well.
				var/obj/surface = M.get_surgery_surface(user)
				if(!surface || !prob(surface.surgery_odds))
					success = FALSE

				// Not staying still fails you too.
				if(success)
					var/calc_duration = rand(S.min_duration, S.max_duration)
					if(!do_mob(user, M, calc_duration * toolspeed, zone))
						success = FALSE
						to_chat(user, "<span class='warning'>You must remain close to and keep focused on your patient to conduct surgery.</span>")

				if(success)
					S.end_step(user, M, zone, src)
				else
					S.fail_step(user, M, zone, src)

				M.op_stage.in_progress -= zone 									// Clear the in-progress flag.
				if (ishuman(M))
					var/mob/living/carbon/human/H = M
					H.update_surgery()
				return	1	  												//don't want to do weapony things after surgery
	return 0

/proc/sort_surgeries()
	var/gap = surgery_steps.len
	var/swapped = 1
	while (gap > 1 || swapped)
		swapped = 0
		if(gap > 1)
			gap = round(gap / 1.247330950103979)
		if(gap < 1)
			gap = 1
		for(var/i = 1; gap + i <= surgery_steps.len; i++)
			var/datum/surgery_step/l = surgery_steps[i]		//Fucking hate
			var/datum/surgery_step/r = surgery_steps[gap+i]	//how lists work here
			if(l.priority < r.priority)
				surgery_steps.Swap(i, gap + i)
				swapped = 1

/datum/surgery_status/
	var/eyes	=	0
	var/face	=	0
	var/brainstem = 0
	var/head_reattach = 0
	var/current_organ = "organ"
	var/list/in_progress = list()