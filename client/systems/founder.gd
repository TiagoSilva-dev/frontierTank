class_name FounderPack
extends RefCounted

# Founder Pack — Edição Paladino do Sol (docs/FOUNDER_PACK.md). Only looks: the pack's
# items are premium cosmetics with no attributes; what changes is the art around them.
# Owning the Selo de Fundador (delivered by mail with the pack) makes a player a
# Founder: the badge, the title and the frame show everywhere, and the Founder effects
# (aura, pet, footsteps, lobby entrance) can be switched on and off in the Founder
# screen. The effects ride on `look.founder`, which the server builds from the profile,
# so every player in a match sees the same thing.

const SKIN: String = "roupa_paladino_sol"
const WEAPON: String = "solaris"
const WINGS: String = "asas_aurora"
const SEAL: String = "selo_fundador"
const SKU: String = "founder_pack"
const FX_KEYS: Array[String] = ["aura", "pet", "foot", "lobby"]
const FX_NAMES: Dictionary = {"aura": "Aura do Primeiro Sol", "pet": "Pet Solis", "foot": "Footstep celestial", "lobby": "Entrada no lobby"}  # i18n
const ITEMS: Array[String] = [SKIN, WEAPON, WINGS, SEAL]
const ART: String = "res://assets/founder/"

# All effects start on; old saves and bad data fall back to that.
static func clean_fx(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	for key: String in FX_KEYS:
		result[key] = bool(raw.get(key, true)) if raw is Dictionary else true
	return result

static func owns(profile: PlayerProfile) -> bool:
	return profile.has_item(SEAL)

# What travels in `look.founder` for a Founder: the seal plus the effects they chose.
static func look_extras(profile: PlayerProfile) -> Dictionary:
	var fx: Dictionary = clean_fx(profile.founder_fx)
	return {"seal": true, "aura": fx.aura, "pet": fx.pet, "foot": fx.foot, "lobby": fx.lobby}

static func wears_skin(look: Dictionary) -> bool:
	return str(look.get("skin", "")) == SKIN

static func wields_weapon(look: Dictionary) -> bool:
	return str(look.get("weapon", "")) == WEAPON

# The full set (skin + Solaris + wings) unlocks the lobby entrance.
static func complete(look: Dictionary) -> bool:
	return wears_skin(look) and wields_weapon(look) and str(look.get("wings", "")) == WINGS

static func is_founder(look: Dictionary) -> bool:
	var extras: Variant = look.get("founder", {})
	return extras is Dictionary and bool(extras.get("seal", false))

static func texture(path: String) -> Texture2D:
	var full: String = ART + path
	return load(full) if ResourceLoader.exists(full) else null

# Frames of a folder (frame_00.png ...), for halos, auras and footsteps.
static func frames(folder: String, prefix: String = "frame_") -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for i in range(64):
		var path: String = "%s%s/%s%02d.png" % [ART, folder, prefix, i]
		if not ResourceLoader.exists(path):
			break
		list.append(load(path))
	return list

# Frames of any res:// folder holding frame_00.png, frame_01.png ... (projectile art).
static func folder_frames(folder: String) -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for i in range(64):
		var path: String = "%s/frame_%02d.png" % [folder, i]
		if not ResourceLoader.exists(path):
			break
		list.append(load(path))
	return list
