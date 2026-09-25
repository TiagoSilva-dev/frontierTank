extends SceneTree

# Launch checklist (roadmap item 4): the web build preset and the benchmark, the name
# and identity review (nothing a player sees uses DDTank's names or brand), privacy and
# accounts (consent, terms, privacy policy, deleting the account in the game), reporting
# in the chat and the Steam layer.

var failures: int = 0
var checks: int = 0

# Names from DDTank that the game used before the review (Portuguese and the literal
# English versions). None may come back in what the players see.
const OLD_NAMES: Array[String] = [
	"Quebra Tijolos", "Fogo Intenso", "Canhão Arco-Íris", "Vento de Deus", "Cesto de Frutas de Newton",
	"Kit Médico", "Eletrodoméstico", "Desentupidor", "Cabeça de Boi", "Bumerangue do Amor",
	"Dom de Anjo", "Bugou", "Escudo do Barão", "Furacão Divino", "Raio Arco-Íris",
	"Brickbreaker", "Blazing Fire", "Rainbow Cannon", "Divine Wind", "Newton's Fruit Basket",
	"Home Appliance", "Plunger", "Bull Head", "Love Boomerang", "Angel's Gift", "Baron's Shield",
	"Divine Hurricane", "Rainbow Beam",
]
const BRANDS: Array[String] = ["ddtank", "dd tank", "7road", "337 games"]

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

static func comment_start(line: String) -> int:
	var quoted: bool = false
	for i in range(line.length()):
		var ch: String = line[i]
		if ch == "\"" and (i == 0 or line[i - 1] != "\\"):
			quoted = not quoted
		elif ch == "#" and not quoted:
			return i
	return -1

static func files(dir: String, extensions: Array, list: Array[String] = []) -> Array[String]:
	if not DirAccess.dir_exists_absolute(dir):
		return list
	for file in DirAccess.get_files_at(dir):
		if extensions.has(file.get_extension()):
			list.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		files(dir + "/" + sub, extensions, list)
	return list

# Everything players can read: the texts of the scripts (comments are left out of the
# exported game), the balance and translation files, the project settings and the
# public documents (legal texts and the Steam page).
static func shipped_texts() -> Dictionary:
	var texts: Dictionary = {}
	for path in files("res://client", ["gd"]) + files("res://server/game", ["gd"]):
		var code: PackedStringArray = PackedStringArray()
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var cut: int = comment_start(line)
			code.append(line if cut < 0 else line.substr(0, cut))
		texts[path] = "\n".join(code)
	for path in files("res://shared", ["json"]) + files("res://locale", ["po", "pot"]) + ["res://project.godot", "res://export_presets.cfg"]:
		texts[path] = FileAccess.get_file_as_string(path)
	for path in files("res://legal", ["md", "txt"]) + files("res://store", ["md", "txt", "json"]):
		texts[path] = FileAccess.get_file_as_string(path)
	return texts

func run_tests() -> void:
	PlayerProfile.path_override = "user://launch_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	Lang.override = "pt_BR"
	Lang.setup()
	test_web()
	test_identity()
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("LAUNCH RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# ---------- web build ----------

func test_web() -> void:
	var presets: ConfigFile = ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "export_presets.cfg exists")
	var web: String = ""
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") and presets.get_value(section, "platform", "") == "Web":
			web = section
	check(web != "", "there is a Web export preset")
	if web == "":
		return
	var options: String = web + ".options"
	check(presets.get_value(options, "variant/thread_support", true) == false, "the web build has no threads (no COOP/COEP headers needed)")
	var excluded: String = str(presets.get_value(web, "exclude_filter", ""))
	for folder in ["docs/*", "tests/*", "tools/*", "server/api/*"]:
		check(excluded.contains(folder), "the web package leaves out %s" % folder)
	check(str(presets.get_value(web, "include_filter", "")).contains("shared/balance/*.json"), "the balance files go into the package")
	check(PerfProbe.percentile(PackedFloat32Array([4, 1, 3, 2]), 0.5) == 2.0 and PerfProbe.percentile(PackedFloat32Array([4, 1, 3, 2]), 1.0) == 4.0, "benchmark percentiles")
	check(is_equal_approx(PerfProbe.average(PackedFloat32Array([1, 2, 3])), 2.0), "benchmark average")

# ---------- names and identity ----------

func test_identity() -> void:
	var texts: Dictionary = shipped_texts()
	check(texts.size() > 50, "the identity check reads the game's texts (%d files)" % texts.size())
	var brand_hits: Array[String] = []
	var name_hits: Array[String] = []
	for path: String in texts:
		var lower: String = str(texts[path]).to_lower()
		for brand in BRANDS:
			if lower.contains(brand):
				brand_hits.append("%s: %s" % [path, brand])
		for old in OLD_NAMES:
			if str(texts[path]).contains(old):
				name_hits.append("%s: %s" % [path, old])
	check(brand_hits.is_empty(), "no DDTank brand in what players see %s" % str(brand_hits.slice(0, 5)))
	check(name_hits.is_empty(), "no weapon or item keeps DDTank's name %s" % str(name_hits.slice(0, 5)))
	# The new names, in both languages (the internal ids and the saves do not change).
	var expected: Dictionary = {"quebra_tijolos": ["Tijolaço", "Bricklayer"], "canhao_arco_iris": ["Prisma", "Prism"], "cesto_newton": ["Pomar", "Orchard"], "escudo_bugou": ["Broquel de Latão", "Brass Buckler"], "dom_de_anjo": ["Bálsamo", "Balm"]}
	for id: String in expected:
		Lang.override = "pt_BR"
		Lang.setup()
		var portuguese: String = Armory.item_name({"id": id})
		Lang.override = "en"
		Lang.setup()
		var english: String = Armory.item_name({"id": id})
		check(portuguese == expected[id][0] and english == expected[id][1], "%s is %s / %s" % [id, portuguese, english])
	Lang.override = "pt_BR"
	Lang.setup()
	var profile: PlayerProfile = PlayerProfile.new()
	profile.load_profile()
	check(Armory.item_name(profile.equipped_instance("arma")) == "Tijolaço", "a new account still starts with the first weapon (same id, new name)")
