@tool
class_name FacetsAdmission
extends RefCounted
## Admission of portable characters into local rules.
##
## Standard admission preserves identity and proposes a legal build from the
## imported preferences with a stable greedy procedure (implementation
## decision D-009):
##   facets  start at the policy baseline; allocate points by preferred rating
##           descending (ties in FACETS order) up to the preference, then any
##           remaining points in the same order up to the cap;
##   skills  allocate by preferred rank descending (ties by skill ID) up to
##           the preference and cap, then remaining points in that order;
##   talents eligible preferred talents in preferred order, then other
##           eligible talents by ID.
## "Closest" is advisory, not an optimization guarantee. Accumulated Growth
## and unadmitted equipment and powers are dropped; memories stay
## source-labeled references.


static func propose(character: FacetsPortableCharacter, policy: FacetsAdmissionPolicy, registry: FacetsRegistry) -> FacetsReply:
	var proposal := FacetsAdmissionProposal.new()
	proposal.character_id = character.character_id
	proposal.policy_id = policy.id
	proposal.identity = character.identity.duplicate(true)
	proposal.extensions = character.extensions.duplicate(true)
	proposal.accomplishments = character.accomplishments.duplicate()
	var preferred := character.preferred_build
	var build := FacetsBuild.new()

	# Facets.
	var facet_order: Array[String] = FacetsRules.FACETS.duplicate()
	facet_order.sort_custom(func(a: String, b: String) -> bool:
		var pa := preferred.facet(a)
		var pb := preferred.facet(b)
		if pa != pb:
			return pa > pb
		return FacetsRules.facet_index(a) < FacetsRules.facet_index(b))
	for facet_id in FacetsRules.FACETS:
		build.facets[facet_id] = policy.facet_min
	var facet_points := policy.facet_total - policy.facet_min * FacetsRules.FACETS.size()
	for facet_id in facet_order:
		var wanted := clampi(preferred.facet(facet_id) - policy.facet_min, 0, policy.facet_cap - policy.facet_min)
		var given := mini(wanted, facet_points)
		build.facets[facet_id] = build.facet(facet_id) + given
		facet_points -= given
		if preferred.facet(facet_id) > policy.facet_cap:
			proposal.warnings.append("Facet %s preferred %d; admitted at most %d." % [facet_id, preferred.facet(facet_id), policy.facet_cap])
	for facet_id in facet_order:
		var given := mini(policy.facet_cap - build.facet(facet_id), facet_points)
		build.facets[facet_id] = build.facet(facet_id) + given
		facet_points -= given
	proposal.explanation.append("Facets: baseline %d each, %d points by preference order %s." % [policy.facet_min, policy.facet_total - policy.facet_min * FacetsRules.FACETS.size(), ", ".join(facet_order)])

	# Skills.
	var skill_order: Array[String] = registry.skill_ids()
	skill_order.sort_custom(func(a: String, b: String) -> bool:
		var pa := preferred.skill(a)
		var pb := preferred.skill(b)
		if pa != pb:
			return pa > pb
		return a < b)
	var skill_points := policy.skill_points
	for skill_id in skill_order:
		var given := mini(mini(preferred.skill(skill_id), policy.skill_cap), skill_points)
		if given > 0:
			build.skills[skill_id] = given
			skill_points -= given
		if preferred.skill(skill_id) > policy.skill_cap:
			proposal.warnings.append("Skill %s preferred %d; admitted at most %d." % [skill_id, preferred.skill(skill_id), policy.skill_cap])
	for skill_id in skill_order:
		if skill_points <= 0:
			break
		var given := mini(policy.skill_cap - build.skill(skill_id), skill_points)
		if given > 0:
			build.skills[skill_id] = build.skill(skill_id) + given
			skill_points -= given
	proposal.explanation.append("Skills: %d points by preference, ties by skill ID, at most %d each." % [policy.skill_points, policy.skill_cap])

	# Talents.
	var candidates: Array[String] = []
	for talent_id in preferred.talents:
		if not candidates.has(talent_id):
			candidates.append(talent_id)
	for talent_id in registry.talent_ids():
		if not candidates.has(talent_id):
			candidates.append(talent_id)
	for talent_id in candidates:
		if build.talents.size() >= policy.talent_count:
			break
		var definition := registry.get_talent(talent_id)
		if definition.is_empty():
			continue
		if str(definition.get("package", "core")) != "core" and not preferred.talents.has(talent_id):
			continue
		if FacetsValidator.prerequisites_met(definition, build):
			build.talents.append(talent_id)
		elif preferred.talents.has(talent_id):
			proposal.warnings.append("Preferred talent %s is not eligible with the admitted build." % talent_id)
	proposal.explanation.append("Talents: eligible preferred talents first, then by ID.")

	# Capabilities, Growth, equipment, memories.
	for capability_id in preferred.capabilities:
		if policy.allowed_capabilities.has(capability_id):
			build.capabilities.append(capability_id)
		else:
			proposal.exclusions.append({"kind": "capability", "id": capability_id, "reason": "Not admitted by %s." % policy.id})
	if character.growth > 0:
		proposal.exclusions.append({"kind": "growth", "id": "growth", "amount": character.growth, "reason": "Accumulated Growth does not transfer."})
	for item_id in character.equipment:
		if not policy.allowed_equipment.has(item_id):
			proposal.exclusions.append({"kind": "equipment", "id": item_id, "reason": "Not admitted by %s." % policy.id})
	for memory in character.memories:
		var reference: Dictionary = memory.duplicate(true)
		reference["status"] = "reference"
		proposal.memories.append(reference)

	var errors := FacetsValidator.validate_policy_build(build, registry, policy, "build")
	if not errors.is_empty():
		return FacetsReply.failures(errors)
	proposal.build = build
	return FacetsReply.success(proposal)


## Creates a fresh journey state from an accepted proposal. The host adds it
## to a session explicitly; nothing here replaces a live build.
static func accept(proposal: FacetsAdmissionProposal, display_name: String = "") -> FacetsActorState:
	var state := FacetsActorState.new()
	state.actor_id = proposal.character_id
	state.display_name = display_name if not display_name.is_empty() else str(proposal.identity.get("name", proposal.character_id))
	state.identity = proposal.identity.duplicate(true)
	state.build = proposal.build.copy()
	state.base_build = state.build.to_dict()
	state.memories = proposal.memories.duplicate(true)
	state.profile = {"accomplishments": Array(proposal.accomplishments)}
	return state
