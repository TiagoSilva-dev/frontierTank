class_name PetMotion
extends RefCounted

# Procedural idle animation for the pets (0.21): one motion style per species, so the
# static PixelLab portraits come alive without generating new frames. Visual only.

const DEFAULT_STYLE: String = "prowl"
# hop: bounces; float: flaps and drifts; prowl: breathes, sways and shakes; waddle: rolls
# side to side; scuttle: quick little steps.
const STYLES: Dictionary = {
	"escaravelho_solar": "scuttle", "chacal_ambar": "prowl", "leao_dourado": "prowl", "fenix_dourada": "float",
	"brasinha": "hop", "diabrete_mascarado": "hop", "cao_de_lava": "prowl", "rei_mascara": "float",
	"pinguim_cristal": "waddle", "coelho_neve": "hop", "raposa_glacial": "prowl", "lobo_boreal": "prowl",
	"nuvenzinha": "float", "passaro_trovao": "float", "grifinho": "float", "dragao_tempestade": "float",
	"corvo_runico": "scuttle", "javali_guerra": "waddle", "urso_berserker": "waddle", "lobo_fenrir": "prowl",
}

static func style_of(species: String) -> String:
	return str(STYLES.get(species, DEFAULT_STYLE))

# Offset of the species' own rhythm so two pets never move in lockstep.
static func phase_of(species: String) -> float:
	return float(species.hash() % 1000) / 1000.0 * TAU

# The pose at time `t`: {"pos": Vector2 (pixels, y up is negative), "rot": radians,
# "scale": Vector2}. The pivot is the pet's feet, so squash and tilt stay on the ground.
static func sample(style: String, t: float) -> Dictionary:
	var pos: Vector2 = Vector2.ZERO
	var rot: float = 0.0
	var scale: Vector2 = Vector2.ONE
	match style:
		"hop":
			var cycle: float = fmod(t, 1.15) / 1.15
			if cycle < 0.55:
				pos.y = -sin(cycle / 0.55 * PI) * 13.0
				scale = Vector2(1.0 - sin(cycle / 0.55 * PI) * 0.05, 1.0 + sin(cycle / 0.55 * PI) * 0.07)
			else:
				var land: float = sin((cycle - 0.55) / 0.45 * PI)
				scale = Vector2(1.0 + land * 0.07, 1.0 - land * 0.08)
			rot = sin(t * 5.4) * 0.025
		"float":
			pos.y = -12.0 + sin(t * 2.2) * 5.0
			pos.x = sin(t * 1.1) * 4.0
			rot = sin(t * 1.5) * 0.07
			var flap: float = sin(t * 7.0)
			scale = Vector2(1.0 + flap * 0.035, 1.0 - flap * 0.03)
		"waddle":
			var step: float = sin(t * 3.4)
			rot = step * 0.1
			pos.y = -absf(step) * 3.5
			pos.x = step * 2.0
			scale.y = 1.0 + sin(t * 2.0) * 0.02
		"scuttle":
			var tick: float = sin(t * 10.0)
			pos.x = sin(t * 1.7) * 6.0
			pos.y = -absf(tick) * 2.5
			rot = tick * 0.045
			scale.y = 1.0 + sin(t * 3.0) * 0.02
		_:
			# prowl: slow breathing and sway, with a shake of the head every few seconds.
			scale.y = 1.0 + sin(t * 2.4) * 0.03
			scale.x = 1.0 - sin(t * 2.4) * 0.012
			rot = sin(t * 1.1) * 0.035
			var shake_t: float = fmod(t, 4.6)
			if shake_t < 0.55:
				var fade: float = 1.0 - shake_t / 0.55
				rot += sin(shake_t * 38.0) * 0.1 * fade
				pos.y -= sin(shake_t / 0.55 * PI) * 3.0
	return {"pos": pos, "rot": rot, "scale": scale}
