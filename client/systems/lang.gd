class_name Lang
extends RefCounted

# Game languages (roadmap item 4.3): Portuguese is the source language and every
# visible text is its own translation key, gettext style, so a text without a
# translation shows up in Portuguese instead of breaking. English lives in
# locale/en.po. Nodes call tr("..."); static code (catalogs, rules) calls Lang.t("...").
# Names from the balance JSON (items, enemies, maps, modifiers) are keys too.
# tools/i18n.py collects every key into locale/messages.pot and keeps en.po in sync;
# tests/i18n_tests.gd fails when a key has no English text.
# The chosen language is saved in user://settings.cfg; the first launch follows the
# system language (Portuguese systems get Portuguese, everything else English).

const LOCALES: Array[String] = ["pt_BR", "en"]
# Each language is named in itself.
const LABELS: Dictionary = {"pt_BR": "Português", "en": "English"}  # no-i18n
const SETTINGS_PATH: String = "user://settings.cfg"

# Tests pin the language (and never write the settings file).
static var override: String = ""

static func t(text: String) -> String:
	return String(TranslationServer.translate(text))

static func locale() -> String:
	return "en" if TranslationServer.get_locale().begins_with("en") else "pt_BR"

static func is_english() -> bool:
	return locale() == "en"

static func setup(forced: String = "") -> void:
	# Order: tests, command line (--lang=en), saved choice, system language.
	var chosen: String = override if override != "" else forced
	if chosen == "":
		var config: ConfigFile = ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK:
			chosen = str(config.get_value("game", "locale", ""))
	if chosen == "":
		chosen = "pt_BR" if OS.get_locale_language() == "pt" else "en"
	TranslationServer.set_locale(normalize(chosen))

static func normalize(code: String) -> String:
	return "en" if code.begins_with("en") else "pt_BR"

static func set_locale(code: String) -> void:
	# Player choice (title screen): applied now and remembered.
	TranslationServer.set_locale(normalize(code))
	if override != "":
		return
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("game", "locale", normalize(code))
	config.save(SETTINGS_PATH)
