/obj/aiming_overlay
	name = ""
	desc = "Stick 'em up!"
	icon = 'icons/effects/Targeted.dmi'
	icon_state = "locking"
	anchored = 1
	density = 0
	opacity = 0
	layer = FLY_LAYER
	simulated = 0
	mouse_opacity = 0

	var/mob/living/aiming_at   // Who are we currently targeting, if anyone?
	var/obj/item/aiming_with   // What are we targeting with?
	var/mob/living/owner       // Who do we belong to?
	var/locked =    0          // Have we locked on?
	var/lock_time = 0          // When -will- we lock on?
	var/active =    0          // Is our owner intending to take hostages?
	var/target_permissions = 0 // Permission bitflags.

/obj/aiming_overlay/New(var/newowner)
	..()
	owner = newowner
	loc = null
	verbs.Cut()

/obj/aiming_overlay/proc/toggle_permission(var/perm)

	if(target_permissions & perm)
		target_permissions &= ~perm
	else
		target_permissions |= perm

	// Update HUD icons.
/*	if(owner.gun_move_icon)
		if(!(target_permissions & TARGET_CAN_MOVE))
			owner.gun_move_icon.icon_state = "no_walk0"
			owner.gun_move_icon.name = "Allow Movement"
		else
			owner.gun_move_icon.icon_state = "no_walk1"
			owner.gun_move_icon.name = "Disallow Movement"

	if(owner.item_use_icon)
		if(!(target_permissions & TARGET_CAN_CLICK))
			owner.item_use_icon.icon_state = "no_item0"
			owner.item_use_icon.name = "Allow Item Use"
		else
			owner.item_use_icon.icon_state = "no_item1"
			owner.item_use_icon.name = "Disallow Item Use"

	if(owner.radio_use_icon)
		if(!(target_permissions & TARGET_CAN_RADIO))
			owner.radio_use_icon.icon_state = "no_radio0"
			owner.radio_use_icon.name = "Allow Radio Use"
		else
			owner.radio_use_icon.icon_state = "no_radio1"
			owner.radio_use_icon.name = "Disallow Radio Use"*/

	var/message = "no longer permitted to "
	var/use_span = "warning"
	if(target_permissions & perm)
		message = "now permitted to "
		use_span = "notice"

	switch(perm)
		if(TARGET_CAN_MOVE)
			message += "move"
		if(TARGET_CAN_CLICK)
			message += "use items"
		if(TARGET_CAN_RADIO)
			message += "use a radio"
		else
			return

	owner << "<span class='[use_span]'>[aiming_at ? "\The [aiming_at] is" : "Your targets are"] [message].</span>"
	if(aiming_at)
		aiming_at << "<span class='[use_span]'>You are [message].</span>"

/obj/aiming_overlay/Process()
	if(!owner)
		qdel(src)
		return
	..()
	update_aiming()

/obj/aiming_overlay/Destroy()
	cancel_aiming(1)
	owner = null
	return ..()

obj/aiming_overlay/proc/update_aiming_deferred()
	set waitfor = 0
	sleep(0)
	update_aiming()

/obj/aiming_overlay/proc/update_aiming()

	if(!owner)
		qdel(src)
		return

	if(!aiming_at)
		cancel_aiming()
		return

	if(!locked && lock_time >= world.time)
		locked = 1
		update_icon()

	var/cancel_aim = 1

	if(!(aiming_with in owner) || (ishuman(owner) && (owner.l_hand != aiming_with && owner.r_hand != aiming_with)))
		owner << SPAN_WARNING("You must keep hold of your weapon!")
	else if(owner.eye_blind)
		owner << SPAN_WARNING("You are blind and cannot see your target!")
	else if(!aiming_at || !istype(aiming_at.loc, /turf))
		owner << SPAN_WARNING("You have lost sight of your target!")
	else if(owner.incapacitated() || owner.lying || owner.restrained())
		owner << SPAN_WARNING("You must be conscious and standing to keep track of your target!")
	else if(aiming_at.alpha == 0 || (aiming_at.invisibility > owner.see_invisible))
		owner << SPAN_WARNING("Your target has become invisible!")
	else if(!(aiming_at in view(owner)))
		owner << SPAN_WARNING("Your target is too far away to track!")
	else
		cancel_aim = 0

	forceMove(get_turf(aiming_at))

	if(cancel_aim)
		cancel_aiming()
		return

	if(!owner.incapacitated() && owner.client)
		spawn(0)
			owner.set_dir(get_dir(get_turf(owner), get_turf(src)))

/obj/aiming_overlay/proc/aim_at(var/mob/target, var/obj/thing)

	if(!owner)
		return

	if(owner.incapacitated())
		owner << SPAN_WARNING("You cannot aim a gun in your current state.")
		return
	if(owner.lying)
		owner << SPAN_WARNING("You cannot aim a gun while prone.")
		return
	if(owner.restrained())
		owner << SPAN_WARNING("You cannot aim a gun while handcuffed.")
		return

	if(aiming_at)
		if(aiming_at == target)
			return
		cancel_aiming(1)
		owner.visible_message(SPAN_DANGER("\The [owner] turns \the [thing] on \the [target]!"))
	else
		owner.visible_message(SPAN_DANGER("\The [owner] aims \the [thing] at \the [target]!"))

	if(owner.client)
		owner.client.add_gun_icons()
	target << SPAN_DANGER("You now have a gun pointed at you. No sudden moves!")
	aiming_with = thing
	aiming_at = target
	if(istype(aiming_with, /obj/item/weapon/gun))
		playsound(get_turf(owner), 'sound/weapons/TargetOn.ogg', 50,1)

	forceMove(get_turf(target))
	START_PROCESSING(SSobj, src)

	aiming_at.aimed |= src
	toggle_active(1)
	locked = 0
	update_icon()
	lock_time = world.time + 35
	moved_event.register(owner, src, /obj/aiming_overlay/proc/update_aiming)
	moved_event.register(aiming_at, src, /obj/aiming_overlay/proc/target_moved)
	destroyed_event.register(aiming_at, src, /obj/aiming_overlay/proc/cancel_aiming)

/obj/aiming_overlay/update_icon()
	if(locked)
		icon_state = "locked"
	else
		icon_state = "locking"

/obj/aiming_overlay/proc/toggle_active(var/force_state = null)
	if(!isnull(force_state))
		if(active == force_state)
			return
		active = force_state
	else
		active = !active

	if(!active)
		cancel_aiming()

	if(owner.client)
		if(active)
			owner << SPAN_NOTICE("You will now aim rather than fire.")
			owner.client.add_gun_icons()
		else
			owner << SPAN_NOTICE("You will no longer aim rather than fire.")
			owner.client.remove_gun_icons()

/obj/aiming_overlay/proc/cancel_aiming(var/no_message = 0)
	if(!aiming_with || !aiming_at)
		return
	if(istype(aiming_with, /obj/item/weapon/gun))
		playsound(get_turf(owner), 'sound/weapons/TargetOff.ogg', 50,1)
	if(!no_message)
		owner.visible_message(SPAN_NOTICE("\The [owner] lowers \the [aiming_with]."))

	moved_event.unregister(owner, src)
	if(aiming_at)
		moved_event.unregister(aiming_at, src)
		destroyed_event.unregister(aiming_at, src)
		aiming_at.aimed -= src
		aiming_at = null

	aiming_with = null
	loc = null
	STOP_PROCESSING(SSobj, src)

/obj/aiming_overlay/proc/target_moved()
	update_aiming()
	trigger(TARGET_CAN_MOVE)
