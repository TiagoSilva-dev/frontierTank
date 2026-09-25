extends SceneTree

# Roadmap 4.3 (languages): every key has English, locale/messages.pot matches the code
# and the balance JSON (same rules as tools/i18n.py), translations keep their %d/%s
# markers, no Portuguese text is left outside tr()/Lang.t(), the Pixel Operator font
# covers Portuguese, Spanish and French, and switching the language switches the game.

var failures: int = 0
var checks: int = 0
const JSON_KEYS: Array[String] = ["name", "desc", "text", "label", "attack", "fury_name"]
const LETTERS: Dictionary = {
	"pt": "ÁÀÂÃÇÉÊÍÓÔÕÚÜáàâãçéêíóôõúü",
	"es": "ÁÉÍÓÚÜÑáéíóúüñ¡¿",
	"fr": "ÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸàâæçéèêëîïôœùûüÿ«»",
}
# Arrows and marks that already come from the system fallback font in Portuguese.
const FALLBACK: String = "←→↑↓▶◀►⇄↵✓"

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func comment_start(line: String) -> int:
	var quoted: bool = false
	for i in range(line.length()):
		var ch: String = line[i]
		if ch == "\"" and (i == 0 or line[i - 1] != "\\"):
			quoted = not quoted
		elif ch == "#" and not quoted:
			return i
	return -1

func gd_files(dir: String, list: Array[String] = []) -> Array[String]:
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			list.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		gd_files(dir + "/" + sub, list)
	return list

func keeps(text: String, marked: bool) -> bool:
	if text.strip_edges() == "" or RegEx.create_from_string("[A-Za-zÀ-ÿ]").search(text) == null:
		return false
	if marked and (RegEx.create_from_string("^([a-z0-9_]+|[0-9a-fA-F]{6,8})$").search(text) != null or text.begins_with("res://")):
		return false
	return true

func code_keys() -> Dictionary:
	# tr("...") / Lang.t("...") literals and whole "# i18n" lines, like tools/i18n.py.
	var found: Dictionary = {}
	var call: RegEx = RegEx.create_from_string("(?:\\btr|\\bLang\\.t)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*\\)")
	var any: RegEx = RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for path in gd_files("res://client") + gd_files("res://server/game"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var cut: int = comment_start(line)
			var code: String = line if cut < 0 else line.substr(0, cut)
			var marked: bool = cut >= 0 and line.substr(cut).strip_edges().begins_with("# i18n")
			for found_match in (any if marked else call).search_all(code):
				var text: String = found_match.get_string(1).c_unescape()
				if keeps(text, marked):
					found[text] = path
	for path in ["res://shared/balance/items.json", "res://shared/balance/combat.json", "res://shared/balance/store.json", "res://shared/balance/achievements.json"]:
		walk(JSON.parse_string(FileAccess.get_file_as_string(path)), found, path)
	return found

func walk(node: Variant, found: Dictionary, path: String) -> void:
	if node is Dictionary:
		for key: String in node:
			if key in JSON_KEYS and node[key] is String:
				if keeps(node[key], false):
					found[node[key]] = path
			else:
				walk(node[key], found, path)
	elif node is Array:
		for value: Variant in node:
			walk(value, found, path)

func pot_keys() -> Array[String]:
	var keys: Array[String] = []
	var current: String = ""
	var reading: bool = false
	for raw in FileAccess.get_file_as_string("res://locale/messages.pot").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("msgid "):
			current = line.substr(7, line.length() - 8).c_unescape()
			reading = true
		elif line.begins_with("\"") and reading:
			current += line.substr(1, line.length() - 2).c_unescape()
		elif line.begins_with("msgstr"):
			if current != "":
				keys.append(current)
			reading = false
	return keys

func markers(text: String) -> Array:
	var list: Array = []
	for found_match in RegEx.create_from_string("%(?:\\.\\d+)?[dsf]|%%").search_all(text):
		list.append(found_match.get_string())
	return list

func run_tests() -> void:
	PlayerProfile.path_override = "user://i18n_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	Lang.override = "pt_BR"
	Lang.setup()
	# --- Keys and translations
	var english: Translation = load("res://locale/en.po")
	check(english != null and english.locale == "en", "locale/en.po loads as the English translation")
	check(TranslationServer.get_loaded_locales().has("en"), "the project registers the English translation")
	var keys: Array[String] = pot_keys()
	var code: Dictionary = code_keys()
	var missing_in_pot: Array = code.keys().filter(func(text: String) -> bool: return not keys.has(text))
	var stale: Array = keys.filter(func(text: String) -> bool: return not code.has(text))
	check(missing_in_pot.is_empty(), "every tr()/Lang.t() text and JSON name is in messages.pot %s" % str(missing_in_pot.slice(0, 5)))
	check(stale.is_empty(), "messages.pot has no key the game stopped using %s" % str(stale.slice(0, 5)))
	var untranslated: Array = keys.filter(func(text: String) -> bool: return String(english.get_message(text)) == "")
	check(keys.size() > 600 and untranslated.is_empty(), "all %d keys have English %s" % [keys.size(), str(untranslated.slice(0, 5))])
	var twice: Array = keys.filter(func(text: String) -> bool:
		var once: String = String(english.get_message(text))
		return once != text and keys.has(once) and String(english.get_message(once)) != once)
	check(twice.is_empty(), "no English text is also a Portuguese key (it would be translated twice) %s" % str(twice))
	var broken: Array = keys.filter(func(text: String) -> bool: return markers(text) != markers(String(english.get_message(text))))
	check(broken.is_empty(), "translations keep the same %%d/%%s markers in the same order %s" % str(broken.slice(0, 3)))
	# --- Nothing Portuguese left outside the translation calls
	var accent: RegEx = RegEx.create_from_string("[ÁÀÂÃÇÉÊÍÓÔÕÚáàâãçéêíóôõú]")
	var literal: RegEx = RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var loose: Array[String] = []
	for path in gd_files("res://client") + gd_files("res://server/game"):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for n in range(lines.size()):
			var cut: int = comment_start(lines[n])
			if cut >= 0 and lines[n].substr(cut).contains("i18n"):
				continue
			for found_match in literal.search_all(lines[n] if cut < 0 else lines[n].substr(0, cut)):
				var text: String = found_match.get_string(1).c_unescape()
				if accent.search(text) != null and not keys.has(text):
					loose.append("%s:%d %s" % [path.get_file(), n + 1, text])
	check(loose.is_empty(), "no Portuguese text outside tr()/Lang.t() %s" % str(loose.slice(0, 5)))
	# --- Font
	var font: Font = UiKit.font()
	for language: String in LETTERS:
		var gaps: String = ""
		for ch in LETTERS[language]:
			if not font.has_char(ch.unicode_at(0)):
				gaps += ch
		check(gaps == "", "Pixel Operator covers the %s letters %s" % [language, gaps])
	var outside: Dictionary = {}
	for text in keys:
		for ch in String(english.get_message(text)):
			if not font.has_char(ch.unicode_at(0)) and not FALLBACK.contains(ch) and ch != "\n":
				outside[ch] = text
	check(outside.is_empty(), "every English text uses letters the font has %s" % str(outside.keys()))
	# --- Switching the language
	Lang.override = ""
	Lang.setup("en")
	check(Lang.is_english(), "--lang=en picks English")
	Lang.setup("pt_BR")
	check(not Lang.is_english() and Armory.item_name({"id": "kit_medico", "quality": "verdadeira", "level": 5}) == "Verdadeiro Tônico +5", "Portuguese stays the source language")
	Lang.override = "en"
	Lang.setup()
	check(Armory.item_name({"id": "kit_medico", "quality": "verdadeira", "level": 5}) == "True Tonic +5" and Armory.item_name({"id": "trovao", "quality": "excelente"}) == "Excellent Lightning Rod", "item names follow the language (True Tonic +5)")
	check(Crafting.mod_text({"id": "dano", "value": 12}) == "+12% damage" and Crafting.currency_name("espelho") == "Sky Mirror" and Crafting.tier_name(1) == "T1", "bonuses, currencies and tiers in English")
	check(InstanceRun.map_name({"instance": "picos_gelados", "level": 7}) == "Map: Frozen Peaks — Level 7" and InstanceRun.mod_text({"id": "enemy_hp", "value": 30}) == "Enemies have +30% HP", "maps and their modifiers in English")
	check(TankFighter.rank_for(1) == "Recruit" and Armory.slot_name("asas") == "Wings" and Armory.quality_label("verdadeira") == "True", "ranks, slots and qualities in English")
	var profile: PlayerProfile = PlayerProfile.new()
	check(profile.redeem("NOPE") == "Invalid coupon." and Crafting.check("coroa", {"id": "trovao", "quality": "normal"}) == "Crowns only work on Excellent items.", "messages from the rules in English")
	var scene: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var app: Node = scene
	var enter: Button = app.screen.find_child("EnterButton", true, false)
	check(enter != null and enter.text == "ENTER" and app.screen.find_child("Lang_pt_BR", true, false) != null, "the title screen is in English with a language choice")
	app.screen.choose_language("pt_BR")
	await process_frame
	check(app.screen.find_child("EnterButton", true, false).text == "ENTRAR", "choosing Português rebuilds the title in Portuguese")
	app.screen.choose_language("en")
	await process_frame
	app.profile.created = true
	app.screen.enter()
	await process_frame
	var labels: Array = app.screen.find_children("*", "Label", true, false).map(func(node: Label) -> String: return node.text)
	check(labels.has("Game Hall") and labels.has("Blacksmith") and labels.has("Dungeon"), "city buildings are named in English")
	app.open_bag()
	await process_frame
	check(app.bag.find_child("Tab_Todos", true, false).text == "All" and app.bag.find_child("Tab_Mapas", true, false).text == "Maps", "the Bag tabs are in English")
	app.bag.open_smith()
	await process_frame
	var smith: SmithScreen = app.bag.get_children().filter(func(node: Node) -> bool: return node is SmithScreen).front()
	smith.select_tab("Moedas")
	check(smith.find_children("*", "Button", true, false).any(func(node: Button) -> bool: return node.text == "Currency"), "the Blacksmith's Currency tab")
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	Lang.override = "pt_BR"
	Lang.setup()
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	print("I18N RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
