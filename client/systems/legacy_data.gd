class_name LegacyData
extends RefCounted

# The game was called "Frontier Tank: Nova Era" until 26/09/2026; now it is Gustfire.
# Godot keeps user:// in a folder named after the project (app_userdata/<name>), so the
# rename moved it. On the first run under the new name, what the old folder had (offline
# save, language, audio, the remembered account and exported data) is copied over, and
# the old folder is left untouched. The web build keeps user:// in the browser under a
# fixed path, so there is nothing to move there.

# The folder name Godot made from "Frontier Tank: Nova Era" (":" becomes "-").
const OLD_FOLDER: String = "Frontier Tank- Nova Era"
# Godot's own folders, rebuilt by the engine: not worth copying.
const SKIP: Array[String] = ["logs", "shader_cache", "vulkan"]

# Returns how many files were copied (0 when there was nothing to do).
static func migrate(user_dir: String = "") -> int:
	if OS.has_feature("web"):
		return 0
	if user_dir == "":
		user_dir = OS.get_user_data_dir()
	var old_dir: String = user_dir.get_base_dir().path_join(OLD_FOLDER)
	if old_dir == user_dir or not DirAccess.dir_exists_absolute(old_dir):
		return 0
	# Only into a fresh folder: never replace anything saved under the new name.
	for name in ["profile.json", "settings.cfg", "online.cfg"]:
		if FileAccess.file_exists(user_dir.path_join(name)):
			return 0
	return copy_tree(old_dir, user_dir)

static func copy_tree(from: String, to: String) -> int:
	var copied: int = 0
	DirAccess.make_dir_recursive_absolute(to)
	for file in DirAccess.get_files_at(from):
		var target: String = to.path_join(file)
		if not FileAccess.file_exists(target) and DirAccess.copy_absolute(from.path_join(file), target) == OK:
			copied += 1
	for folder in DirAccess.get_directories_at(from):
		if not folder in SKIP:
			copied += copy_tree(from.path_join(folder), to.path_join(folder))
	return copied
