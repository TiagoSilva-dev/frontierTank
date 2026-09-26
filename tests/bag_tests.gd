extends SceneTree

# The Mochila of 0.15: the arrangement kept in the profile (and its network op), moving
# items between cells (also with real mouse drags), equipping by dropping on the
# character or a slot, taking gear off by dragging it out, the item card that follows
# the mouse, and selecting without rebuilding the page.
#   godot --headless --path . --script tests/bag_tests.gd

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	Lang.override = "pt_BR"
	Lang.setup()
	PlayerProfile.path_override = "user://bag_test_profile.json"
	if FileAccess.file_exists(PlayerProfile.path_override):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path_override))
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/balance/combat.json"))
	# --- the layout in the profile
	var clean: Array[String] = PlayerProfile.clean_bag(["uid:3", "bad key", "uid:3", "", "item:solar", "map:7", "tool:1", 12, "", ""])
	check(clean == ["uid:3", "", "", "", "item:solar", "map:7", "tool:1"], "the saved arrangement keeps known keys only, without repeats or empty cells at the end")
	var many: Array = []
	for i in range(2000):
		many.append("uid:%d" % i)
	check(PlayerProfile.clean_bag(many).size() == PlayerProfile.BAG_CELLS and PlayerProfile.clean_bag("x").is_empty(), "the arrangement is bounded and ignores junk")
	var plain: PlayerProfile = PlayerProfile.new()
	check("bag_layout" in PlayerProfile.OPS, "arranging the bag is an operation the server accepts")
	var result: Dictionary = plain.apply_op("bag_layout", [["uid:1", "", "item:brasa"]], balance)
	check(result.error == "" and plain.bag == ["uid:1", "", "item:brasa"], "the bag_layout op stores the arrangement")
	var copy: PlayerProfile = PlayerProfile.new()
	copy.load_data(JSON.parse_string(JSON.stringify(plain.to_data())))
	check(copy.bag == plain.bag, "the arrangement survives saving and loading (and the server's copy)")
	plain.apply_op("bag_layout", [[]], balance)
	check(plain.bag.is_empty(), "an empty arrangement means the default order")
	# --- the screen
	var app: Node = load("res://client/scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile.created = true
	app.profile.redeem("TESTARTUDO")
	app.profile.redeem("MOEDAS")
	app.profile.redeem("MAPAS")
	app.show_city()
	app.open_bag()
	await process_frame
	var bag: CharacterScreen = app.bag
	check(bag.cells_shown.size() == CharacterScreen.PER_PAGE and bag.find_child("Stage", true, false) is HeroStage, "the Mochila shows %d square cells and the character on a stage" % CharacterScreen.PER_PAGE)
	var first: BagSlot = bag.cells_shown[0]
	check(first.key == "uid:%d" % int(app.profile.equipped.arma) and first.equipped, "by default the worn weapon comes first")
	check(bag.cells_shown.any(func(s: BagSlot) -> bool: return s.rarity.a > 0.0) and bag.cells_shown.any(func(s: BagSlot) -> bool: return s.key != "" and s.rarity.a == 0.0), "better qualities glow in their colour, normal items do not")
	bag.select_item(bag.cells_shown[1].key)
	check(is_instance_valid(first) and bag.cells_shown[0] == first and bag.cells_shown[1].selected and not first.selected, "selecting an item only marks it (the page is not rebuilt)")
	# Move to an empty cell on the last page, leaving a gap.
	var moved: String = bag.cells_shown[1].key
	bag.turn_page(99)
	await process_frame
	var empty: BagSlot = bag.cells_shown.filter(func(s: BagSlot) -> bool: return s.key == "").back()
	var target_cell: int = empty.cell
	bag.drop_on_cell(empty, {"bag_key": moved, "from_cell": 1, "equip_slot": ""})
	await process_frame
	var cells: Array[String] = bag.layout()
	check(cells[target_cell] == moved and cells[1] == "" and app.profile.bag[target_cell] == moved, "an item dropped on an empty cell moves there and leaves its old cell empty")
	# Swap two items on the first page.
	bag.turn_page(-99)
	await process_frame
	var a: String = bag.cells_shown[2].key
	var b: String = bag.cells_shown[4].key
	bag.drop_on_cell(bag.cells_shown[4], {"bag_key": a, "from_cell": 2, "equip_slot": ""})
	await process_frame
	cells = bag.layout()
	check(cells[4] == a and cells[2] == b, "an item dropped on another swaps them")
	# A sold item leaves its cell empty; a new item takes the first empty cell.
	var sold: Dictionary = bag.entry_map()[cells[6]].get("inst", {})
	app.profile.sell(int(sold.uid))
	cells = bag.layout()
	check(cells[6] == "" and cells[1] == "", "sold items leave their cell empty")
	var fresh: Dictionary = app.profile.add_instance("trovao", "excelente")
	cells = bag.layout()
	check(cells[1] == "uid:%d" % int(fresh.uid), "a new item goes to the first empty cell")
	# Real mouse drag between two cells.
	bag.refresh_grid()
	await process_frame
	var from_slot: BagSlot = bag.cells_shown[9]
	var to_slot: BagSlot = bag.cells_shown[12]
	var dragged: String = from_slot.key
	var other: String = to_slot.key
	await drag(from_slot.get_global_rect().get_center(), to_slot.get_global_rect().get_center())
	cells = bag.layout()
	check(dragged != "" and cells[12] == dragged and cells[9] == other, "dragging a cell with the mouse onto another swaps them")
	# Filtered tabs keep the same arrangement.
	bag.filter_items("Armas")
	await process_frame
	var w0: String = bag.cells_shown[0].key
	var w1: String = bag.cells_shown[1].key
	var p0: int = bag.layout().find(w0)
	var p1: int = bag.layout().find(w1)
	bag.drop_on_cell(bag.cells_shown[1], {"bag_key": w0, "from_cell": 0, "equip_slot": ""})
	await process_frame
	check(bag.layout().find(w0) == p1 and bag.layout().find(w1) == p0 and bag.entries().all(func(e: Dictionary) -> bool: return e.has("inst") and Armory.kind_of(str(e.inst.id)) == "weapon"), "in the Armas tab items swap in the same arrangement")
	bag.sort_bag()
	await process_frame
	check(app.profile.bag.is_empty() and bag.layout() == bag.all_entries().map(func(e: Dictionary) -> String: return e.key), "ORGANIZAR sorts the bag back to the default order")
	bag.filter_items("Todos")
	await process_frame
	# Equip by dropping on the character; take off by dragging out of the slot.
	var hat: Dictionary = {}
	for inst: Dictionary in app.profile.inventory:
		if Armory.slot_of(str(inst.id)) == "chapeu" and not app.profile.is_equipped(int(inst.uid)):
			hat = inst
			break
	var hat_key: String = "uid:%d" % int(hat.uid)
	var stage: HeroStage = bag.find_child("Stage", true, false)
	check(stage.accepts.call({"bag_key": hat_key, "equip_slot": ""}) and not stage.accepts.call({"bag_key": "item:solar", "equip_slot": ""}), "the character accepts gear, not currencies")
	stage.dropped.emit({"bag_key": hat_key, "from_cell": 0, "equip_slot": ""})
	await process_frame
	check(app.profile.equipped_instance("chapeu").get("uid", -1) == hat.uid, "dropping a hat on the character equips it")
	var hat_slot: BagSlot = bag.equip_cells["chapeu"]
	var weapon_key: String = "uid:%d" % int(app.profile.inventory.filter(func(i: Dictionary) -> bool: return Armory.slot_of(str(i.id)) == "arma" and not app.profile.is_equipped(int(i.uid))).front().uid)
	check(hat_slot.key == hat_key and not hat_slot.accepts.call(hat_slot, {"bag_key": weapon_key, "equip_slot": ""}), "an equipment slot only takes its own kind of item")
	bag.drop_on_cell(bag.cells_shown[20], {"bag_key": hat_key, "from_cell": -1, "equip_slot": "chapeu"})
	await process_frame
	await process_frame
	check(app.profile.equipped_instance("chapeu").is_empty(), "dragging gear out of its slot takes it off")
	var weapon_slot: BagSlot = null
	for slot: BagSlot in bag.cells_shown:
		if slot.key == weapon_key:
			weapon_slot = slot
	if weapon_slot == null:
		bag.select_item(weapon_key)
		bag.toggle_key(weapon_key)
	else:
		weapon_slot.activated.emit(weapon_slot)
	await process_frame
	check(app.profile.equipped.arma == weapon_key.substr(4).to_int(), "double click (or right click) equips")
	# The item card.
	var card: ItemTooltip = bag.tooltip
	var cell: BagSlot = null
	for slot: BagSlot in bag.cells_shown:
		if slot.key.begins_with("uid:") and not app.profile.is_equipped(slot.key.substr(4).to_int()) and Armory.kind_of(str(app.profile.find_instance(slot.key.substr(4).to_int()).id)) == "weapon":
			cell = slot
			break
	bag.on_hover(cell, true)
	bag._process(0.2)
	var text: String = card_text(card)
	check(card.visible and text.contains("Dano") and text.contains("POW:") and text.contains("Nível do item") and text.contains("Vende por"), "hovering an item shows its card: damage, POW, item level, sale value")
	check(text.contains("(+") or text.contains("(-"), "the card compares with the item worn in that slot")
	bag.on_hover(cell, false)
	check(not card.visible, "the card hides when the mouse leaves")
	for key: String in bag.entry_map():
		if key.begins_with("map:"):
			card.show_entry(bag.entry_map()[key], app.profile, app.balance)
			break
	check(card_text(card).contains("Mapa de instância"), "maps have a card too")
	card.show_entry(bag.entry_map()["item:solar"], app.profile, app.balance)
	check(card_text(card).contains("Rerola"), "currencies explain their use on the card")
	app.close_bag()
	await process_frame
	app.queue_free()
	await create_timer(0.3).timeout
	print("BAG RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func drag(from: Vector2, to: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press, true)
	await process_frame
	for i in range(1, 13):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = from.lerp(to, i / 12.0)
		motion.global_position = motion.position
		motion.relative = (to - from) / 12.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	root.push_input(release, true)
	await process_frame
	await process_frame

func card_text(card: ItemTooltip) -> String:
	var parts: Array[String] = []
	for node: Node in card.find_children("*", "", true, false):
		if node is RichTextLabel:
			parts.append((node as RichTextLabel).get_parsed_text())
		elif node is Label:
			parts.append((node as Label).text)
	return "\n".join(parts)
