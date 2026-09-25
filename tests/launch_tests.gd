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
	test_legal_texts()
	await test_privacy_screens()
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

# ---------- privacy and accounts (LGPD/GDPR) ----------

func test_legal_texts() -> void:
	var api_config: String = FileAccess.get_file_as_string("res://server/api/config.go")
	check(api_config.contains('env("LEGAL_VERSION", "%s")' % Legal.VERSION), "the game and the API ask for the same version of the texts (%s)" % Legal.VERSION)
	for english in [false, true]:
		Lang.override = "en" if english else "pt_BR"
		Lang.setup()
		for kind in Legal.KINDS:
			var body: String = Legal.text(kind)
			check(FileAccess.file_exists(Legal.path(kind, english)) and body.begins_with("# ") and body.contains(Legal.VERSION) and not body.contains("{{"), "%s (%s) exists, shows the version and has no unfilled mark" % [kind, "en" if english else "pt"])
		var privacy: String = Legal.text("privacy")
		for topic in (["Marco Civil", "LGPD", "GDPR", "13", "ANPD"] if not english else ["Marco Civil", "LGPD", "GDPR", "13", "ANPD"]):
			check(privacy.contains(topic), "the privacy policy (%s) covers %s" % ["en" if english else "pt", topic])
	Lang.override = "pt_BR"
	Lang.setup()
	check(Legal.text("terms").contains("Termos de Uso") and Legal.title("privacy") == "Política de Privacidade", "Portuguese texts in Portuguese")
	var code: String = Legal.to_bbcode("# Título\n- item **forte** [preencher: e-mail]\n| a | b |\n|---|---|")
	check(code.contains("[font_size=26][b]Título[/b][/font_size]") and code.contains("•") and code.contains("[b]forte[/b]") and code.contains("[lb]preencher: e-mail[rb]") and not code.contains("|---"), "the Markdown of the texts becomes BBCode (brackets escaped)")
	var presets: ConfigFile = ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(str(presets.get_value("preset.0", "include_filter", "")).contains("legal/*.md"), "the legal texts go inside the game package")

func test_privacy_screens() -> void:
	AuthClient.config_path = "user://launch_test_online.cfg"
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var title: TitleScreen = app.screen
	var link: Button = title.find_child("TermsLink", true, false)
	check(link != null and title.find_child("PrivacyLink", true, false) != null, "the title screen links the Terms and the Privacy Policy")
	link.pressed.emit()
	await process_frame
	var viewer: LegalScreen = null
	for node in title.get_children():
		if node is LegalScreen:
			viewer = node
	check(viewer != null and viewer.text_view.get_parsed_text().contains("Termos de Uso"), "the Terms open over the title")
	viewer.show_kind("privacy")
	check(viewer.text_view.get_parsed_text().contains("Política de Privacidade"), "the viewer switches to the Privacy Policy")
	viewer.queue_free()
	# Consent: nothing reaches the API without both boxes ticked.
	var dialog: ConsentDialog = ConsentDialog.open(app.ui, "create")
	await process_frame
	var confirm: Button = dialog.find_child("Confirm", true, false)
	check(confirm.disabled, "the account cannot be created without accepting")
	dialog.accept_box.button_pressed = true
	check(confirm.disabled, "accepting the texts is not enough without the age statement")
	dialog.age_box.button_pressed = true
	check(not confirm.disabled, "both boxes ticked: the account can be created")
	var answer: Array = []
	dialog.decided.connect(func(accepted: bool) -> void: answer.append(accepted))
	confirm.pressed.emit()
	check(answer == [true], "the dialog tells the player accepted")
	var update: ConsentDialog = ConsentDialog.open(app.ui, "update")
	await process_frame
	check(update.age_box == null and update.find_child("Confirm", true, false).disabled, "new texts: only the acceptance is asked again")
	update.finish(false)
	# CRIAR CONTA opens the consent first; cancelling it creates nothing.
	title.servers = [{"name": "Teste", "url": "ws://127.0.0.1:1", "state": "", "color": "ffffff"}, TitleScreen.OFFLINE]
	title.chosen = 0
	title.build_servers()
	title.build_account()
	title.user_field.text = "nova_conta"
	title.password_field.text = "senha-forte-1"
	title.create_account()
	await process_frame
	var asked: ConsentDialog = null
	for node in title.get_children():
		if node is ConsentDialog:
			asked = node
	check(asked != null and asked.mode == "create", "CRIAR CONTA asks for the consent first")
	asked.finish(false)
	await process_frame
	check(app.auth.token == "" and title.status_label.text.contains("aceite"), "without the consent no account is created")
	# Ajuda: the texts and Minha conta; offline there is no account to delete.
	app.open_help()
	var help: Control = app.ui.find_child("HelpDialog", true, false)
	check(help != null and help.find_child("HelpTerms", true, false) != null and help.find_child("HelpPrivacy", true, false) != null, "Ajuda links the Terms and the Privacy Policy")
	(help.find_child("HelpAccount", true, false) as Button).pressed.emit()
	await process_frame
	var account: AccountScreen = null
	for node in app.ui.get_children():
		if node is AccountScreen:
			account = node
	check(account != null and account.find_child("Delete", true, false) == null and account.find_child("Terms", true, false) != null, "Minha conta offline: the texts, nothing to delete")
	app.queue_free()
	await process_frame
	if FileAccess.file_exists(AuthClient.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthClient.config_path))
