class_name Legal
extends RefCounted

# Terms of Use and Privacy Policy (launch checklist, LGPD/GDPR). The texts live in
# legal/<kind>_<pt|en>.md, go inside the game package (export_presets.cfg) and are shown by
# LegalScreen. VERSION must match LEGAL_VERSION in the API: a new version makes every
# player accept the texts again before entering a server (the game server refuses the
# login with "terms_required" until then). Who runs the game (company, e-mail...) is
# filled once in legal/controller.json and replaces the {{KEY}} marks in the texts.

const VERSION: String = "2026-09-25"
const KINDS: Array[String] = ["terms", "privacy"]
const TITLES: Dictionary = {"terms": "Termos de Uso", "privacy": "Política de Privacidade"}  # i18n
const CONTROLLER: String = "res://legal/controller.json"

static func path(kind: String, english: bool) -> String:
	return "res://legal/%s_%s.md" % [kind, "en" if english else "pt"]

static func title(kind: String) -> String:
	return Lang.t(str(TITLES.get(kind, kind)))

# The text in the game language, with the controller's details filled in.
static func text(kind: String) -> String:
	var file: String = path(kind, Lang.is_english())
	if not FileAccess.file_exists(file):
		file = path(kind, false)
	var body: String = FileAccess.get_file_as_string(file)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTROLLER)) if FileAccess.file_exists(CONTROLLER) else null
	if parsed is Dictionary:
		for key: String in parsed:
			body = body.replace("{{%s}}" % key, str(parsed[key]))
	return body.replace("{{VERSION}}", VERSION)

# The little Markdown the legal texts use (headings, lists, bold, links, tables as plain
# lines) as BBCode for a RichTextLabel.
static func to_bbcode(markdown: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for raw: String in markdown.split("\n"):
		var line: String = raw.strip_edges(false, true)
		var size: int = 0
		if line.begins_with("### "):
			line = line.substr(4)
			size = 18
		elif line.begins_with("## "):
			line = line.substr(3)
			size = 21
		elif line.begins_with("# "):
			line = line.substr(2)
			size = 26
		elif line.begins_with("|---") or line.begins_with("| ---"):
			continue
		line = escape(line) if not line.contains("](") else inline_links(line)
		line = bold(line)
		if line.begins_with("- "):
			line = "  •  " + line.substr(2)
		elif line.begins_with("|"):
			line = "  " + line.trim_prefix("|").trim_suffix("|").replace(" | ", "  ·  ").strip_edges()
		if size > 0:
			line = "[font_size=%d][b]%s[/b][/font_size]" % [size, line]
		lines.append(line)
	return "\n".join(lines)

static func bold(line: String) -> String:
	var parts: PackedStringArray = line.split("**")
	var out: String = parts[0]
	for i in range(1, parts.size()):
		out += ("[b]" if i % 2 == 1 else "[/b]") + parts[i]
	if parts.size() % 2 == 0:
		out += "[/b]"
	return out

static func inline_links(line: String) -> String:
	var link: RegEx = RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	var out: String = ""
	var at: int = 0
	for found: RegExMatch in link.search_all(line):
		out += escape(line.substr(at, found.get_start() - at))
		out += "[url=%s][color=#2a5ad8]%s[/color][/url]" % [found.get_string(2), found.get_string(1)]
		at = found.get_end()
	return out + escape(line.substr(at))

# Square brackets shown as text ("[preencher: ...]") instead of BBCode tags.
static func escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")
