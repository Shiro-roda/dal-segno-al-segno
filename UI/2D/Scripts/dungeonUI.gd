extends Control

@onready var room_list = $RoomList
@onready var controller: DungeonController = $"../DungeonController"

var dungeon : DungeonRunState

# ── Keyboard navigation ──────────────────────────────────────────────
var _kb_index : int    = 0
var _kb_focused_btn : Button = null

func _kb_list_buttons() -> Array:
	var result : Array = []
	if not is_instance_valid(room_list):
		return result
	for child in room_list.get_children():
		if child is Button and not (child as Button).disabled:
			result.append(child)
	return result

func _kb_apply_focus() -> void:
	if is_instance_valid(_kb_focused_btn):
		_kb_focused_btn.remove_theme_stylebox_override("normal")
		_kb_focused_btn = null
	var list := _kb_list_buttons()
	if list.is_empty():
		return
	_kb_index = clampi(_kb_index, 0, list.size() - 1)
	_kb_focused_btn = list[_kb_index]
	var p := ThemeManager.palette
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(p.primary.r * 0.3, p.primary.g * 0.3, p.primary.b * 0.3, 0.30)
	sbox.border_color = p.focus_border
	sbox.set_border_width_all(2)
	sbox.set_content_margin_all(4)
	_kb_focused_btn.add_theme_stylebox_override("normal", sbox)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var kc : int = (event as InputEventKey).keycode
	var list := _kb_list_buttons()
	if list.is_empty():
		return
	if kc == KEY_UP:
		_kb_index = (_kb_index - 1 + list.size()) % list.size()
		_kb_apply_focus()
		get_viewport().set_input_as_handled()
	elif kc == KEY_DOWN:
		_kb_index = (_kb_index + 1) % list.size()
		_kb_apply_focus()
		get_viewport().set_input_as_handled()
	elif kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER:
		_kb_index = clampi(_kb_index, 0, list.size() - 1)
		(list[_kb_index] as Button).emit_signal("pressed")
		_kb_index = 0
		call_deferred("_kb_apply_focus")
		get_viewport().set_input_as_handled()

func _ready() -> void:
	add_to_group("dungeon_ui")

func setup(controller_dungeon : DungeonRunState):

	print("Setting up UI.")
	dungeon = controller_dungeon

	if controller == null:
		push_error("DungeonController not found!")


	for child in room_list.get_children():
		child.queue_free()


	for i in range(dungeon.rooms.size()):

		var room = dungeon.rooms[i]

		if room.room_data == null:
			continue

		var button = Button.new()
		button.text = room.room_data.room_name

		button.disabled = i != dungeon.current_room_index

		var index := i

		button.pressed.connect(func():
			controller.dungeon.current_room_index = index
			controller.enter_current_room()
		)


		room_list.add_child(button)
	_kb_index = 0
	call_deferred("_kb_apply_focus")


func show_rest_screen():

	for child in room_list.get_children():
		child.queue_free()

	var room : RoomInstance = controller.dungeon.grid.get(controller.dungeon.current_pos)
	if room == null:
		return

	# Generate options once and cache them on the room so re-entry shows the same choices
	if room.rest_options.is_empty():
		var members = controller.dungeon.run_state.party_members
		var run_state = controller.dungeon.run_state

		var avg_hp_lost : int = 0
		for m in members:
			avg_hp_lost += m.character.base_max_hp - m.current_hp
		avg_hp_lost /= max(1, members.size())
		var avg_max_hp : int = 0
		for m in members:
			avg_max_hp += m.character.base_max_hp
		avg_max_hp /= max(1, members.size())
		var pct_hp  = randi_range(int(avg_hp_lost * 0.4), int(avg_hp_lost * 1.6) + 1)
		var flat_hp = randi_range(int(avg_max_hp  * 0.3), int(avg_max_hp  * 0.7))

		var avg_will_lost : int = 0
		var will_members  : int = 0
		for m in members:
			if m.has_will():
				avg_will_lost += m.max_will - m.will
				will_members  += 1
		var flat_will : int = 0
		var pct_will  : int = 0
		if will_members > 0:
			avg_will_lost /= will_members
			var avg_max_will : int = 0
			for m in members:
				if m.has_will(): avg_max_will += m.max_will
			avg_max_will /= will_members
			pct_will  = randi_range(int(avg_will_lost * 0.4), int(avg_will_lost * 1.6) + 1)
			flat_will = randi_range(int(avg_max_will  * 0.3), int(avg_max_will  * 0.7))

		var ammo_spent : int = run_state.max_ammo - run_state.ammo
		var pct_ammo  = randi_range(int(ammo_spent           * 0.4), int(ammo_spent           * 1.6) + 1)
		var flat_ammo = randi_range(int(run_state.max_ammo   * 0.3), int(run_state.max_ammo   * 0.7))

		var all_options : Array = [
			{"text": "Rest (restore ~%d CORP each)"       % pct_hp,   "type": "hp",   "val": pct_hp},
			{"text": "Slumber (restore ~%d CORP each)"    % flat_hp,  "type": "hp",   "val": flat_hp},
			{"text": "Ruminate (restore ~%d AP each)" % pct_will, "type": "will", "val": pct_will},
			{"text": "Pray (restore ~%d AP each)"     % flat_will,"type": "will", "val": flat_will},
			{"text": "Scavenge (restore ~%d BB)"      % pct_ammo, "type": "ammo", "val": pct_ammo},
			{"text": "Desecrate (restore ~%d BB)"     % flat_ammo,"type": "ammo", "val": flat_ammo},
		]
		all_options.shuffle()
		room.rest_options = all_options.slice(0, 3)

	var label = Label.new()
	label.text = "Choose how to rest:"
	room_list.add_child(label)

	for option in room.rest_options:
		var btn = Button.new()
		btn.text = option["text"]
		var t = option["type"]
		var v = option["val"]
		btn.pressed.connect(func(): _do_rest(t, v))
		room_list.add_child(btn)
	_kb_index = 0
	call_deferred("_kb_apply_focus")

	# Segno placement is now handled exclusively through the SEGNO room type.
	# No legacy button needed here.


func _do_rest(rest_type: String, val: int) -> void:
	var room = controller.dungeon.grid.get(controller.dungeon.current_pos)
	if room:
		room.rested = true

	var rs = controller.dungeon.run_state
	match rest_type:
		"hp":
			for member in rs.party_members:
				member.set_hp(mini(member.current_hp + val, member.character.base_max_hp))
		"will":
			for member in rs.party_members:
				if member.has_will():
					member.restore_will(val)
		"ammo":
			rs.restore_ammo(val)

	clear_room_list()
	controller.on_room_completed()



func show_room_choices(dungeon: DungeonRunState, controller: DungeonController):

	clear_room_list()

	# If a specific slot was clicked in the 3D map, show choices only for that slot.
	# Otherwise show all available positions (post-room-clear flow).
	var positions : Array
	if controller.pending_build_pos != Vector2i(-999, -999):
		positions = [controller.pending_build_pos]
	else:
		positions = controller.get_available_positions()

	for pos in positions:

		var label = Label.new()
		label.text = "Build at " + str(pos)
		room_list.add_child(label)

		var choices : Array = controller.pending_room_choices.get(pos, [])
		for data in choices:

			var button = Button.new()
			button.text = data.room_name

			button.pressed.connect(func():
				clear_room_list()
				controller.build_room(pos, data)
			)

			room_list.add_child(button)
	_kb_index = 0
	call_deferred("_kb_apply_focus")


func clear_room_list():
	if room_list == null:
		push_error("RoomList node missing!")
		return

	for child in room_list.get_children():
		child.queue_free()
