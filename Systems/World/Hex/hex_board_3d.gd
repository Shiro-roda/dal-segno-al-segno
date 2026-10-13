extends Node3D
## A bare-bones, clickable 3D board for feeling out the hex loop (HexDayCycle).
##
## The world is an endless black plane; a shader draws the hex grid as glowing lines, so
## there is no edge. Only the hexes near the camera get a number label.
##
##   Left click   build (or erase) with the chosen tool
##   Right drag   orbit          Q / E         orbit with the keyboard
##   Middle drag  pan            WASD / arrows pan with the keyboard
##   Wheel        zoom           1-6           pick a tool
##
## Raids are on in this sandbox. Red tags are raiders, cyan tags are your defenders, a hurt
## room shows its health, and the Select tool (6) shows a room's safe zone and its upgrade
## tree.
##
## The segment clock is a stub: it counts down and, at zero, locks building ("overtime").
## The chaser that would hunt you in overtime is not built yet.

const SIZE := 2.5
const SEGMENT_SECONDS := 600.0
## Hexes within this many steps of the view centre get a number label.
const LABEL_RADIUS := 10

const LINE := Color(0.098, 0.275, 0.871, 1.0)
const ROAD := Color(0.85, 1.0, 0.95)
const BAD := Color(1.0, 0.3, 0.3)
## Indexed by HexWorld.Terrain: neutral, red, green, blue.
const TERRAIN_COLORS: Array[Color] = [
	Color(0.7, 0.7, 0.7),
	Color(1.0, 0.3, 0.3),
	Color(0.3, 1.0, 0.45),
	Color(0.35, 0.6, 1.0),
]

## The grid is drawn per pixel: find the hex under the pixel, then how far the pixel is
## from that hex's nearest side. Pointy-top hexes, matching HexGrid.
const GRID_SHADER := """
shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform float hex_size = 1.0;
uniform vec3 line_color : source_color = vec3(0.2, 1.0, 0.6);
uniform float intensity = 1.8;
uniform vec2 focus = vec2(0.0);
uniform float fade_from = 14.0;
uniform float fade_to = 36.0;
uniform bool use_fog = false;
uniform sampler2D fog_tex : filter_nearest;
uniform int fog_radius = 0;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float side_distance(vec2 p, out vec2 hex) {
	vec2 u = p / hex_size;
	float qf = 0.57735027 * u.x - u.y / 3.0;
	float rf = 2.0 / 3.0 * u.y;
	vec3 c = vec3(qf, rf, -qf - rf);
	vec3 rc = round(c);
	vec3 d = abs(rc - c);
	if (d.x > d.y && d.x > d.z) {
		rc.x = -rc.y - rc.z;
	} else if (d.y > d.z) {
		rc.y = -rc.x - rc.z;
	}
	hex = rc.xy;
	vec2 centre = vec2(1.7320508 * (rc.x + rc.y * 0.5), 1.5 * rc.y);
	vec2 l = abs(u - centre);
	float m = max(l.x, dot(l, vec2(0.5, 0.8660254)));
	return (0.8660254 - m) * hex_size;
}

void fragment() {
	vec2 hx;
	float d = side_distance(wp.xz, hx);
	float seen = 1.0;
	if (use_fog) {
		int n = fog_radius * 2 + 1;
		ivec2 idx = ivec2(floor(hx + vec2(0.5))) + ivec2(fog_radius);
		if (idx.x < 0 || idx.y < 0 || idx.x >= n || idx.y >= n) {
			seen = 0.0;
		} else {
			seen = texelFetch(fog_tex, idx, 0).r;
		}
	}
	float w = fwidth(d);
	float core = 1.0 - smoothstep(0.012, 0.012 + w * 1.5, d);
	float glow = exp(-d * 16.0) * 0.45;
	float fade = 1.0 - smoothstep(fade_from, fade_to, distance(wp.xz, focus));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = line_color * (core * intensity + glow) * fade * seen;
}
"""

enum Mode { TOWN, DEN, POST, ERASE, SELECT, WALK, PLACE }

## Every TileDef .tres under here (subfolders included) becomes a room tool.
const ROOM_DIR := "res://Systems/World/Resources"

const FRONTIER := Color(0.2, 0.42, 1.0)
const WILD_TINT := Color(1.0, 0.65, 0.2)
const PARTY_TINT := Color(1.0, 0.9, 0.3)

const RAIDER_TINT := Color(1.0, 0.35, 0.3)
const ALLY_TINT := Color(0.35, 0.9, 1.0)
const ZONE_TINT := Color(0.35, 0.8, 1.0)

var cycle: HexDayCycle
var config: WorldConfig
var exit_def: TileDef
var town_def: TileDef
var den_def: TileDef
var post_def: TileDef
var mode := Mode.TOWN
var time_left := SEGMENT_SECONDS
var overtime := false
## The room the Select tool is looking at (HexGrid.NONE = none).
var selected: Vector3i = HexGrid.NONE

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _cam: Camera3D
var _focus := Vector3.ZERO
var _yaw := 0.6
var _pitch := 0.95
var _dist := 11.0
var _rotating := false
var _panning := false

var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _cell_offsets: Array[Vector2i] = []
var _cells: Array[Dictionary] = []        # {node, label, fill, mat}
var _awake_cells: Array[int] = []
var _center_hex := Vector2i(1 << 20, 1 << 20)
var _fill_mesh: ArrayMesh

var _road_nodes: Dictionary = {}   # Vector3i -> MeshInstance3D
var _room_nodes: Dictionary = {}   # Vector3i -> Node3D
var _ghost_room: MeshInstance3D
var _ghost_road: MeshInstance3D
var _ghost_mat: StandardMaterial3D

var _lbl_title: Label
var _lbl_roll: Label
var _lbl_stock: Label
var _lbl_timer: Label
var _lbl_origin: Label
var _over_panel: PanelContainer
var _over_label: Label
var _lbl_log: Label
var _lbl_status: Label
var _btn_end: Button
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _overlay_root: Node3D
var _zone_root: Node3D
var _frontier_root: Node3D
var _party_root: Node3D
var _wild_root: Node3D
var _fade_mat: StandardMaterial3D
var _fade_fwd: ArrayMesh
var _fade_rev: ArrayMesh
var _known_mmi: MultiMeshInstance3D
var _known_count := -1
var _room_defs: Array[TileDef] = []
var _placing_loaded: TileDef
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_radius := 0
var _fog_shown := -1
var _zone_mat: StandardMaterial3D
var _zone_mesh: Mesh
var _mode_buttons: Array[Button] = []
var _log_lines: Array[String] = []

const COMBAT_HUD_SCENE = preload("res://UI/2D/Scenes/combat_hud.tscn")
const PARTY_MENU_SCENE = preload("res://UI/2D/Scenes/party_menu.tscn")

## The fight being watched, and its HUD. Both are null between fights.
var _fight_session: CombatSession
var _fight_hud: CombatHUD


func _ready() -> void:
	_rng.randomize()
	_build_defs()
	_load_room_defs()
	cycle = HexDayCycle.new(exit_def, config, WorldPersistent.new(), -1)
	cycle.log_line.connect(_log)
	cycle.awake_changed.connect(_refresh_cells)
	cycle.segment_changed.connect(_on_segment_changed)
	cycle.phase_changed.connect(func(_p: int) -> void: _refresh_hud())
	cycle.tile_changed.connect(func(_v: Vector3i) -> void: _sync_all())
	cycle.road_changed.connect(func(_e: Vector3i) -> void: _sync_all())
	cycle.hyle_changed.connect(_refresh_hud)
	cycle.raids_changed.connect(func() -> void:
		_sync_all()
		_refresh_hud())
	cycle.run_ended.connect(_on_run_ended)
	cycle.explored_changed.connect(_sync_all)
	cycle.explored_changed.connect(_refresh_cells)
	cycle.party_changed.connect(_sync_all)
	cycle.wild_changed.connect(_sync_all)
	cycle.present_fights = true
	cycle.fight_starting.connect(_on_fight_starting)
	cycle.fight_started.connect(_on_fight_started)
	cycle.xp_awarded.connect(_on_xp_awarded)
	cycle.begin_run()
	_make_test_party()
	_ensure_party_menu()

	_build_environment()
	_build_ground()
	_build_cells()
	_build_ghosts()
	_build_overlays()
	_build_hud()
	_update_camera()
	_sync_all()
	_refresh_cells()
	_refresh_hud()
	_log("The origin grows the roads. Build rooms where they end.")


# ------------------------------------------------------------------ content

func _build_defs() -> void:
	config = WorldConfig.new()
	config.require_blueprints = false
	config.require_segno = false
	config.infinite_board = false
	config.board_radius = 36  # about a Civilization standard map: ~4,000 hexes
	# No starting pool: notes come from clearing wild enemies and bringing the loot home.
	config.starting_resources = {}
	config.explore_vertices = true
	config.start_explored_radius = 0
	config.wild_enemies_enabled = true
	config.wild_templates = [
		_enemy("Wild beast", EnemyTemplate.NoteColor.NONE),
		_enemy("Red wild", EnemyTemplate.NoteColor.RED),
		_enemy("Green wild", EnemyTemplate.NoteColor.GREEN),
		_enemy("Blue wild", EnemyTemplate.NoteColor.BLUE),
	]
	config.raids_enabled = true
	config.raider_templates = [_enemy("Raider", EnemyTemplate.NoteColor.NONE)]
	# Explored ground outside any dungeon's safe zone breeds raiders that march on the town
	# and, in the end, the origin.
	config.frontier_raids_enabled = true

	exit_def = TileDef.new()
	exit_def.id = &"gate"
	exit_def.display_name = "Gate"
	exit_def.category = TileDef.Category.DUNGEON
	exit_def.is_exit = true

	town_def = TileDef.new()
	town_def.id = &"room"
	town_def.display_name = "Room"
	town_def.category = TileDef.Category.VILLAGE
	town_def.color = Vector3i(20, 20, 20)
	town_def.income = {config.note_ids[0]: 1, config.note_ids[1]: 1, config.note_ids[2]: 1}

	den_def = TileDef.new()
	den_def.id = &"den"
	den_def.display_name = "Dungeon room"
	den_def.category = TileDef.Category.DUNGEON
	den_def.color = Vector3i(30, 20, 20)
	den_def.spawn_count = 2
	den_def.enemies = [
		_enemy("Red enemy", EnemyTemplate.NoteColor.RED),
		_enemy("Green enemy", EnemyTemplate.NoteColor.GREEN),
		_enemy("Blue enemy", EnemyTemplate.NoteColor.BLUE),
	]

	var guard := AllyTemplate.new()
	guard.display_name = "Guard"
	guard.level = 3
	guard.corpus_die = 10

	var red: StringName = config.note_ids[0]
	var green: StringName = config.note_ids[1]
	var blue: StringName = config.note_ids[2]
	# The Den's upgrade tree is a tree of buildings. A room's size (safe-zone reach and how
	# many enemies it holds) comes from its spawn count: 2 is small, 3+ medium, 6+ large.
	#   Dungeon room -> Deep lair -> Garrison / Ranger camp / Warren
	#                -> Lookout
	var deep := _variant(den_def, &"den_deep", "Deep lair")
	deep.spawn_count = 4  # medium: more enemies gather and the zone reaches further
	deep.max_health = 15
	var lookout := _variant(den_def, &"den_lookout", "Lookout")
	lookout.spawn_count = 3  # medium, but no sturdier
	var garrison := _variant(deep, &"garrison", "Garrison")
	garrison.ally = guard
	garrison.ally_cap = 2
	garrison.ally_per_segment = 1
	garrison.ally_behavior = TileDef.AllyBehavior.GUARD
	var rangers := _variant(deep, &"rangers", "Ranger camp")
	rangers.ally = guard
	rangers.ally_cap = 2
	rangers.ally_per_segment = 1
	rangers.ally_behavior = TileDef.AllyBehavior.PATROL
	rangers.ally_patrol_range = 4
	var warren := _variant(deep, &"warren", "Warren")
	warren.spawn_count = 6  # large: it holds far more and covers further, with no defenders

	deep.upgrades = [
		_upgrade(garrison, {blue: 4}, "Guards hold this room."),
		_upgrade(rangers, {blue: 4}, "Rangers patrol the roads for raiders."),
		_upgrade(warren, {blue: 4}, "No defenders, but it holds far more and covers further."),
	]
	den_def.upgrades = [
		_upgrade(deep, {red: 3}, "More enemies gather here, so the room grows. Sturdier too."),
		_upgrade(lookout, {green: 3}, "The room grows, so its safe zone reaches further."),
	]

	post_def = TileDef.new()
	post_def.id = &"post"
	post_def.display_name = "Guard post"
	post_def.category = TileDef.Category.VILLAGE
	post_def.color = Vector3i(10, 10, 10)
	post_def.max_health = 8
	post_def.ally = guard
	post_def.ally_cap = 1
	post_def.ally_per_segment = 1
	post_def.ally_behavior = TileDef.AllyBehavior.GUARD
	# Guard post -> Barracks (more guards) or Patrol post (guards roam the roads).
	var barracks := _variant(post_def, &"barracks", "Barracks")
	barracks.ally_cap = 3
	var patrol_post := _variant(post_def, &"patrol_post", "Patrol post")
	patrol_post.ally_behavior = TileDef.AllyBehavior.PATROL
	patrol_post.ally_patrol_range = 5
	post_def.upgrades = [
		_upgrade(barracks, {red: 3}, "Two more guards."),
		_upgrade(patrol_post, {green: 3}, "Its guards patrol the roads instead of standing watch."),
	]

	# Nothing finishes instantly: rooms and upgrades take segments to build.
	town_def.build_segments = 2
	den_def.build_segments = 3
	post_def.build_segments = 2


## A copy of `base` to hang an upgrade step on: the same building until the caller changes it,
## with no steps of its own yet.
func _variant(base: TileDef, id: StringName, label: String) -> TileDef:
	var def: TileDef = base.duplicate()
	def.id = id
	def.display_name = label
	def.upgrades = []
	return def


## The step that turns a room into `into`, for `price`.
func _upgrade(into: TileDef, price: Dictionary, text: String) -> RoomUpgrade:
	var up := RoomUpgrade.new()
	up.into = into
	up.description = text
	up.cost = price
	up.build_segments = 2
	return up


## The party that walks the map is the game's active roster, so the party menu (TAB) shows
## and edits the same characters. The roster is filled from the character sheets if nothing
## has recruited yet. Three plain heroes stand in only if that fails. Without an engine
## there is no party and Walk refuses.
func _make_test_party() -> void:
	var engine: RulesEngine = Rules.engine
	if engine == null:
		push_warning("hex_board_3d: no rules engine, so the test party was not made.")
		return
	if Rules.roster == null or Rules.roster.active.is_empty():
		PartySetup.recruit_all()
	if Rules.roster != null and not Rules.roster.active.is_empty():
		cycle.set_party(Rules.roster.active_blocks())
		return
	push_warning("hex_board_3d: the roster is empty, so stand-in heroes are used (no party menu).")
	var blocks: Array = []
	for label in ["Hero", "Scout", "Mender"]:
		var hero := AllyTemplate.new()
		hero.display_name = label
		hero.level = 3
		hero.corpus_die = 10
		blocks.append(hero.build_block(engine))
	cycle.set_party(blocks)


## GameController adds the party menu in the real game; the sandbox adds its own. When it
## closes, the party is re-read from the roster so Bring / Leave take effect.
func _ensure_party_menu() -> void:
	var menu := get_tree().get_first_node_in_group("party_menu") as PartyMenu
	if menu == null:
		menu = PARTY_MENU_SCENE.instantiate() as PartyMenu
		add_child(menu)
	if not menu.menu_closed.is_connected(_on_party_menu_closed):
		menu.menu_closed.connect(_on_party_menu_closed)


func _on_party_menu_closed() -> void:
	if cycle.fighting() or Rules.roster == null or Rules.roster.active.is_empty():
		return
	cycle.set_party(Rules.roster.active_blocks())


# --------------------------------------------------------------- watched fights

## The cycle made a session for a fight the party walked into. Putting it in the tree lets
## it run on its own clock; the HUD is shown once the fight has begun.
func _on_fight_starting(session: CombatSession) -> void:
	_fight_session = session
	add_child(session)
	session.combat_ended.connect(_on_fight_ended)


func _on_fight_started(session: CombatSession) -> void:
	_fight_hud = COMBAT_HUD_SCENE.instantiate() as CombatHUD
	add_child(_fight_hud)
	_fight_hud.bind(session)
	_log("Fight! Pick a hero (1-3), then press Space to begin.")
	_refresh_hud()


## The session ended: settle it on the map. The HUD holds VICTORY / DEFEAT, then removes
## itself.
func _on_fight_ended(_victory: bool) -> void:
	var session := _fight_session
	_fight_session = null
	cycle.finish_fight()
	if is_instance_valid(session):
		session.queue_free()
	_sync_all()
	_refresh_hud()


## Level-ups are spent in the party menu (TAB), not forced on the player. Characters set to
## pick automatically (CharacterSheet.auto_pick_recommended) level up right here; for
## everyone else this only says who has earned one.
func _on_xp_awarded(_amount: int, ready_ids: Array) -> void:
	var names: Array[String] = []
	var auto_names: Array[String] = []
	for id in ready_ids:
		var sheet := Rules.roster.get_sheet(id)
		if sheet == null or not Leveling.can_level_up(sheet):
			continue
		var who := sheet.display_name if sheet.display_name != "" else String(id)
		if sheet.auto_pick_recommended \
				and Leveling.auto_resolve(Rules.roster, Leveling.build_offer(Rules.roster, id)):
			auto_names.append("%s (level %d)" % [who, sheet.level])
		else:
			names.append(who)
	if not auto_names.is_empty():
		_log("Levelled up: %s." % ", ".join(auto_names))
	if not names.is_empty():
		_log("%s can level up. Open the party menu (TAB)." % ", ".join(names))


func _enemy(display_name: String, note_color: EnemyTemplate.NoteColor) -> EnemyTemplate:
	var template := EnemyTemplate.new()
	template.display_name = display_name
	template.level = 1
	template.note_color = note_color
	template.notes_per_kill = 2
	template.xp_value = 5  # each active companion earns this when a fight with it is won
	return template


# -------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 200.0
	add_child(_cam)


func _update_camera() -> void:
	# A finite board: the view centre stops at the board's edge.
	if config != null and not config.infinite_board:
		var limit := SIZE * 1.7320508 * float(config.board_radius)
		var flat := Vector2(_focus.x, _focus.z)
		if flat.length() > limit:
			flat = flat.normalized() * limit
			_focus.x = flat.x
			_focus.z = flat.y
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at_from_position(_focus + offset, _focus, Vector3.UP)


## Ground-plane directions that match the screen: where "up" and "right" point.
func _forward() -> Vector2:
	return Vector2(-sin(_yaw), -cos(_yaw))


func _right() -> Vector2:
	return Vector2(cos(_yaw), -sin(_yaw))


# -------------------------------------------------------------------- board

func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	_ground.mesh = plane
	var shader := Shader.new()
	shader.code = GRID_SHADER
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = shader
	_ground_mat.set_shader_parameter("hex_size", SIZE)
	_ground_mat.set_shader_parameter("line_color", LINE)
	_ground.material_override = _ground_mat
	add_child(_ground)
	_build_fog_texture()


## A finite board gets a small texture with one pixel per hex (white = draw its grid, black =
## dark), so the shader can cut the grid at the board edge and keep unexplored hexes hidden.
func _build_fog_texture() -> void:
	var world := cycle.world
	# With vertex fog the grid is drawn edge by edge (_refresh_known_edges), not by this shader.
	if world.vertex_fog:
		_ground.visible = false
		return
	if world.infinite:
		_ground_mat.set_shader_parameter("use_fog", false)
		return
	_fog_radius = 0
	for hex: Vector2i in world.terrain:
		_fog_radius = maxi(_fog_radius, maxi(absi(hex.x), absi(hex.y)))
	var n := _fog_radius * 2 + 1
	_fog_image = Image.create(n, n, false, Image.FORMAT_R8)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_ground_mat.set_shader_parameter("fog_tex", _fog_texture)
	_ground_mat.set_shader_parameter("fog_radius", _fog_radius)
	_ground_mat.set_shader_parameter("use_fog", true)
	_fog_shown = -1
	_refresh_fog_texture()


## Redraws the texture when the set of seen hexes has changed.
func _refresh_fog_texture() -> void:
	if _fog_image == null:
		return
	var world := cycle.world
	var key := world.revealed.size() if world.vertex_fog else -2
	if key == _fog_shown:
		return
	_fog_shown = key
	_fog_image.fill(Color(0.0, 0.0, 0.0))
	for hex: Vector2i in world.terrain:
		if not world.vertex_fog or world.revealed.has(hex):
			_fog_image.set_pixel(hex.x + _fog_radius, hex.y + _fog_radius, Color(1.0, 0.0, 0.0))
	_fog_texture.update(_fog_image)


## A small pool of number labels and wake highlights that follows the view centre, so the
## endless board only ever costs a fixed number of nodes.
func _build_cells() -> void:
	_cell_offsets = HexGrid.hexes_in_radius(LABEL_RADIUS)
	_fill_mesh = _flat_hex_mesh()
	for _i in _cell_offsets.size():
		var node := Node3D.new()
		var fill := MeshInstance3D.new()
		fill.mesh = _fill_mesh
		fill.position.y = 0.02
		var mat := _glow_mat(Color.WHITE, 0.8, 0.3)
		fill.material_override = mat
		fill.visible = false
		node.add_child(fill)
		var label := Label3D.new()
		label.font_size = 80
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 6
		label.outline_modulate = Color.BLACK
		label.position = Vector3(0.0, 0.25, 0.0)
		node.add_child(label)
		add_child(node)
		_cells.append({"node": node, "label": label, "fill": fill, "mat": mat})


func _flat_hex_mesh() -> ArrayMesh:
	var centre := HexGrid.hex_center(Vector2i.ZERO, SIZE)
	var corners: Array[Vector3] = []
	for k in 6:
		var p := HexGrid.vertex_pos(HexGrid.corner(Vector2i.ZERO, k), SIZE) - centre
		corners.append(Vector3(p.x, 0.0, p.y) * 0.96)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in 6:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(corners[k])
		st.add_vertex(corners[(k + 1) % 6])
	return st.commit()


## Re-deals the labels to the hexes around the view centre and lights the awake ones.
func _refresh_cells() -> void:
	if _cells.is_empty():
		return
	var world := cycle.world
	_awake_cells.clear()
	for i in _cells.size():
		var hex: Vector2i = _center_hex + _cell_offsets[i]
		var cell: Dictionary = _cells[i]
		var c := HexGrid.hex_center(hex, SIZE)
		(cell["node"] as Node3D).position = Vector3(c.x, 0.0, c.y)
		var seen := world.has_hex(hex) and (not world.vertex_fog or world.revealed.has(hex))
		(cell["node"] as Node3D).visible = seen
		if not seen:
			continue
		var tint: Color = TERRAIN_COLORS[clampi(world.terrain_at(hex), 0, 3)]
		var awake := cycle.awake.has(hex)
		var ratio := float(HexGrid.hex_distance(Vector2i.ZERO, _cell_offsets[i])) / float(LABEL_RADIUS)
		var label := cell["label"] as Label3D
		label.text = str(world.number_at(hex))
		label.scale = Vector3.ONE * (1.4 if awake else 1.0)
		var shown := Color.WHITE if awake else tint.darkened(0.3)
		shown.a = 1.0 - pow(ratio, 3.0)
		label.modulate = shown
		var fill := cell["fill"] as MeshInstance3D
		fill.visible = awake
		if awake:
			var mat := cell["mat"] as StandardMaterial3D
			mat.emission = tint
			mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.3).darkened(0.5)
			mat.albedo_color.a = 0.3
			_awake_cells.append(i)
	_refresh_hud()


func _glow_mat(col: Color, energy: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.75)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	return m


# ------------------------------------------------------- roads and rooms

## Brings the road and room models in line with the cycle: adds new ones, drops erased ones.
func _sync_all() -> void:
	if _cam == null:
		return
	for e: Vector3i in cycle.world.roads:
		if not _road_nodes.has(e):
			_road_nodes[e] = _make_road(e)
	for e: Vector3i in _road_nodes.keys():
		if not cycle.world.roads.has(e):
			(_road_nodes[e] as Node).queue_free()
			_road_nodes.erase(e)
	for v: Vector3i in cycle.world.structures:
		_sync_room(v)
	for v: Vector3i in _room_nodes.keys():
		if not cycle.world.structures.has(v):
			(_room_nodes[v] as Node).queue_free()
			_room_nodes.erase(v)
	if selected != HexGrid.NONE and not cycle.world.structures.has(selected):
		selected = HexGrid.NONE
	_refresh_tags()
	_refresh_overlays()
	_refresh_fog_texture()
	_refresh_zone()
	_refresh_known_edges()
	_refresh_frontier()
	_refresh_party()
	_refresh_wild()
	_refresh_panel()


func _road_transform(e: Vector3i) -> Transform3D:
	var ends := HexGrid.edge_ends(e)
	var a := HexGrid.vertex_pos(ends[0], SIZE)
	var b := HexGrid.vertex_pos(ends[1], SIZE)
	var mid := (a + b) * 0.5
	var dir := b - a
	var rot := Basis(Vector3.UP, -atan2(dir.y, dir.x))
	return Transform3D(rot, Vector3(mid.x, 0.05, mid.y))


func _make_road(e: Vector3i) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.06, 0.09)
	node.mesh = box
	node.material_override = _glow_mat(ROAD, 2.0)
	node.transform = _road_transform(e)
	add_child(node)
	return node


func _sync_room(v: Vector3i) -> void:
	if _room_nodes.has(v):
		return
	_room_nodes[v] = _make_room(v, cycle.world.structures[v])


func _make_room(v: Vector3i, tile: TileInstance) -> Node3D:
	var root := Node3D.new()
	var p := HexGrid.vertex_pos(v, SIZE)
	root.position = Vector3(p.x, 0.0, p.y)
	var body := MeshInstance3D.new()
	var col: Color
	var tag_height := 1.0
	if tile.def.is_origin or tile.def.is_exit:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.1
		pillar.bottom_radius = 0.1
		pillar.height = 1.0
		body.mesh = pillar
		body.position.y = 0.5
		col = Color(1.0, 1.0, 1.0)
		tag_height = 1.25
	elif tile.def.clef() == TileDef.Clef.BASS:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.22
		spike.height = 0.6
		spike.radial_segments = 4
		body.mesh = spike
		body.position.y = 0.3
		col = BAD
		tag_height = 0.9
	else:
		var cube := BoxMesh.new()
		cube.size = Vector3(0.32, 0.4, 0.32)
		body.mesh = cube
		body.position.y = 0.2
		col = Color(0.4, 0.85, 1.0)
		tag_height = 0.7
	body.material_override = _glow_mat(col, 1.5)
	root.add_child(body)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.font_size = 36
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.outline_modulate = Color.BLACK
	tag.position = Vector3(0.0, tag_height, 0.0)
	root.add_child(tag)
	add_child(root)
	return root


## Tags above rooms: the gate; a building site's countdown; a dungeon room's waiting enemies,
## size and capacity; a town room's health once raids are on. A star counts upgrades taken.
func _refresh_tags() -> void:
	var sizes := ["Small", "Medium", "Large"]
	for v: Vector3i in _room_nodes:
		var tile: TileInstance = cycle.world.structures.get(v)
		if tile == null:
			continue
		var tag := (_room_nodes[v] as Node).get_node("Tag") as Label3D
		var text := ""
		if tile.def.is_origin or tile.def.is_exit:
			tag.text = "Gate"
			continue
		elif not tile.is_built():
			text = "%s\nBuilding: %d" % [tile.def.display_name, tile.build_left]
		elif tile.def.clef() == TileDef.Clef.BASS:
			var tokens := cycle.spawn_count_at(v) if cycle.phase == HexDayCycle.Phase.PLAN else 0
			var waiting := cycle.room_held(v)
			# x = enemies already waiting; +N = spawn tokens this segment will add (not a head count).
			text = "x%d" % waiting + (" +%d" % tokens if tokens > 0 else "")
			if cycle.raids_enabled() and cycle.is_safe_room(tile):
				text += "\n%s: holds %d, reach %d" % [sizes[cycle.room_size(tile)],
						cycle.room_capacity(tile), cycle.cover_radius(tile)]
		else:
			text = tile.def.display_name
			if cycle.raids_enabled():
				text += "  %d/%d" % [tile.health, cycle.effective_max_health(tile)]
		if not tile.lineage.is_empty():
			text += "  *%d" % tile.lineage.size()
		tag.text = text


# ------------------------------------------------------- raids and zones

func _build_overlays() -> void:
	_overlay_root = Node3D.new()
	add_child(_overlay_root)
	_zone_root = Node3D.new()
	add_child(_zone_root)
	_known_mmi = MultiMeshInstance3D.new()
	_known_mmi.material_override = _glow_mat(LINE, 2.0)
	add_child(_known_mmi)
	_frontier_root = Node3D.new()
	add_child(_frontier_root)
	_party_root = Node3D.new()
	add_child(_party_root)
	_wild_root = Node3D.new()
	add_child(_wild_root)
	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.vertex_color_use_as_albedo = true
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_fwd = _fade_mesh(true)
	_fade_rev = _fade_mesh(false)
	_zone_mat = _glow_mat(ZONE_TINT, 1.2, 0.35)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.32
	disc.bottom_radius = 0.32
	disc.height = 0.02
	disc.radial_segments = 20
	_zone_mesh = disc


func _overlay_label(text: String, tint: Color, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = tint
	label.font_size = 36
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.outline_modulate = Color.BLACK
	label.position = Vector3(0.0, height, 0.0)
	return label


## Raiders (red) and defenders (cyan) standing at each vertex, as a marker and a count.
func _refresh_overlays() -> void:
	if _overlay_root == null:
		return
	for child in _overlay_root.get_children():
		child.queue_free()
	var raiders := {}
	for r in cycle.raiders:
		raiders[r["vertex"]] = int(raiders.get(r["vertex"], 0)) + 1
	var allies := {}
	for a in cycle.allies:
		allies[a["vertex"]] = int(allies.get(a["vertex"], 0)) + 1
	var spots := {}
	for v in raiders:
		spots[v] = true
	for v in allies:
		spots[v] = true
	for v: Vector3i in spots:
		var p := HexGrid.vertex_pos(v, SIZE)
		var spot := Node3D.new()
		spot.position = Vector3(p.x, 0.0, p.y)
		_overlay_root.add_child(spot)
		if raiders.has(v):
			var cone := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = 0.14
			mesh.height = 0.35
			mesh.radial_segments = 3
			cone.mesh = mesh
			cone.material_override = _glow_mat(RAIDER_TINT, 2.0)
			cone.position = Vector3(0.28, 0.18, 0.2)
			spot.add_child(cone)
			spot.add_child(_overlay_label("Raiders x%d" % int(raiders[v]), RAIDER_TINT, 1.45))
		if allies.has(v):
			var orb := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.11
			ball.height = 0.22
			orb.mesh = ball
			orb.material_override = _glow_mat(ALLY_TINT, 2.0)
			orb.position = Vector3(-0.28, 0.14, 0.2)
			spot.add_child(orb)
			spot.add_child(_overlay_label("Defenders x%d" % int(allies[v]), ALLY_TINT, 1.7))


## A flat strip along one edge, bright at one end and clear at the other.
func _fade_mesh(bright_first: bool) -> ArrayMesh:
	var half := SIZE * 0.5
	var width := 0.045
	var near := Color(FRONTIER.r, FRONTIER.g, FRONTIER.b, 0.9)
	var far := Color(FRONTIER.r, FRONTIER.g, FRONTIER.b, 0.0)
	var a := near if bright_first else far
	var b := far if bright_first else near
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-half, 0.0, -width), Vector3(half, 0.0, -width),
			Vector3(half, 0.0, width), Vector3(-half, 0.0, width)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([a, b, b, a])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Edges from the explored world into the unexplored, each fading into the dark. In the
## Walk tool these are what you click.
func _refresh_frontier() -> void:
	if _frontier_root == null:
		return
	for child in _frontier_root.get_children():
		child.queue_free()
	for e in cycle.frontier_edges():
		var far := cycle.unexplored_end(e)
		var ends := HexGrid.edge_ends(e)
		var strip := MeshInstance3D.new()
		strip.mesh = _fade_fwd if far == ends[1] else _fade_rev
		strip.material_override = _fade_mat
		strip.transform = _road_transform(e)
		_frontier_root.add_child(strip)


## The grid under fog: an edge is drawn in full once both its ends are explored. (Edges
## with only one explored end are the fading ones from _refresh_frontier.)
func _refresh_known_edges() -> void:
	if _known_mmi == null:
		return
	var world := cycle.world
	if not world.vertex_fog:
		_known_mmi.visible = false
		return
	if world.explored.size() == _known_count:
		return
	_known_count = world.explored.size()
	var edges := cycle.known_edges()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.015, 0.06)
	mm.mesh = box
	mm.instance_count = edges.size()
	for i in edges.size():
		var t := _road_transform(edges[i])
		t.origin.y = 0.02
		mm.set_instance_transform(i, t)
	_known_mmi.multimesh = mm
	_known_mmi.visible = true


## The party's marker, with the moves it has left and what it is carrying.
func _refresh_party() -> void:
	if _party_root == null:
		return
	for child in _party_root.get_children():
		child.queue_free()
	if cycle.party.is_empty() or cycle.party_vertex == HexGrid.NONE:
		return
	var p := HexGrid.vertex_pos(cycle.party_vertex, SIZE)
	var spot := Node3D.new()
	spot.position = Vector3(p.x, 0.0, p.y)
	_party_root.add_child(spot)
	var pin := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.16
	mesh.height = 0.4
	mesh.radial_segments = 4
	pin.mesh = mesh
	pin.material_override = _glow_mat(PARTY_TINT, 2.2)
	pin.position = Vector3(0.0, 0.3, 0.0)
	spot.add_child(pin)
	var text := "Party  %d/%d moves" % [cycle.party_moves_left, config.party_moves_per_segment]
	if not cycle.party_loot.is_empty():
		text += "\ncarrying %s" % _price_text(cycle.party_loot)
	spot.add_child(_overlay_label(text, PARTY_TINT, 1.0))


## Wild enemy groups on vertices the party has explored. Ones in the dark are not drawn.
func _refresh_wild() -> void:
	if _wild_root == null:
		return
	for child in _wild_root.get_children():
		child.queue_free()
	var mat := _glow_mat(WILD_TINT, 2.0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.13
	mesh.height = 0.32
	mesh.radial_segments = 5
	var labels := cycle.wild.size() <= 150
	for v: Vector3i in cycle.wild:
		if not cycle.world.is_explored(v):
			continue
		var p := HexGrid.vertex_pos(v, SIZE)
		var spot := Node3D.new()
		spot.position = Vector3(p.x, 0.0, p.y)
		_wild_root.add_child(spot)
		var cone := MeshInstance3D.new()
		cone.mesh = mesh
		cone.material_override = mat
		cone.position = Vector3(0.0, 0.18, 0.0)
		spot.add_child(cone)
		if labels:
			spot.add_child(_overlay_label("Wild x%d" % cycle.wild_count_at(v), WILD_TINT, 0.8))


## Lights the selected safe room's zone: every vertex its defenders and its cover reach.
func _refresh_zone() -> void:
	if _zone_root == null:
		return
	for child in _zone_root.get_children():
		child.queue_free()
	if selected == HexGrid.NONE:
		return
	for v in cycle.cover_zone(selected):
		var p := HexGrid.vertex_pos(v, SIZE)
		var disc := MeshInstance3D.new()
		disc.mesh = _zone_mesh
		disc.material_override = _zone_mat
		disc.position = Vector3(p.x, 0.04, p.y)
		_zone_root.add_child(disc)


# --------------------------------------------------------------- hover ghost

func _build_ghosts() -> void:
	_ghost_mat = _glow_mat(LINE, 1.5, 0.55)
	_ghost_room = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.18
	ball.height = 0.36
	_ghost_room.mesh = ball
	_ghost_room.material_override = _ghost_mat
	_ghost_room.visible = false
	add_child(_ghost_room)
	_ghost_road = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.08, 0.14)
	_ghost_road.mesh = box
	_ghost_road.material_override = _ghost_mat
	_ghost_road.visible = false
	add_child(_ghost_road)


func _ground_point(screen: Vector2) -> Variant:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


## What a click at `screen` would do: {kind, key, check} or {} when nothing is there.
func _target_at(screen: Vector2) -> Dictionary:
	var ground: Variant = _ground_point(screen)
	if ground == null:
		return {}
	var p: Vector2 = ground
	match mode:
		Mode.TOWN, Mode.DEN, Mode.POST, Mode.PLACE:
			var v := HexGrid.nearest_vertex(p, SIZE)
			var def := _placing_def()
			return {"kind": "room", "key": v, "def": def, "check": _gate(cycle.can_place(v, def))}
		Mode.SELECT:
			var v := HexGrid.nearest_vertex(p, SIZE)
			if cycle.tile_at(v) != null and HexGrid.vertex_pos(v, SIZE).distance_to(p) < 0.45:
				return {"kind": "select", "key": v, "check": {"ok": true, "reason": ""}}
			return {}
		Mode.WALK:
			# Click a vertex you have explored to walk back to it, or an edge to walk along it:
			# into the dark from a fading edge, or to the far end of an explored one.
			var wv := HexGrid.nearest_vertex(p, SIZE)
			if wv != cycle.party_vertex and cycle.world.is_explored(wv) \
					and HexGrid.vertex_pos(wv, SIZE).distance_to(p) < 0.6:
				return {"kind": "walk_vertex", "key": wv, "to": wv, "check": _gate(cycle.can_travel_to(wv))}
			var e := HexGrid.nearest_edge(p, SIZE)
			var far := cycle.unexplored_end(e)
			if far == HexGrid.NONE:
				if not cycle.world.has_edge(e):
					return {}
				var ends := HexGrid.edge_ends(e)
				if not (cycle.world.is_explored(ends[0]) and cycle.world.is_explored(ends[1])):
					return {}
				if ends[0] == cycle.party_vertex:
					far = ends[1]
				elif ends[1] == cycle.party_vertex:
					far = ends[0]
				elif HexGrid.vertex_pos(ends[0], SIZE).distance_to(p) < HexGrid.vertex_pos(ends[1], SIZE).distance_to(p):
					far = ends[0]
				else:
					far = ends[1]
			return {"kind": "walk", "key": e, "to": far, "check": _gate(cycle.can_travel_to(far))}
		Mode.ERASE:
			var v := HexGrid.nearest_vertex(p, SIZE)
			if cycle.tile_at(v) != null and HexGrid.vertex_pos(v, SIZE).distance_to(p) < 0.45:
				return {"kind": "erase_room", "key": v, "check": _gate(cycle.can_erase(v))}
	return {}


## Overtime locks every building action.
func _gate(check: Dictionary) -> Dictionary:
	if overtime:
		return {"ok": false, "reason": "Overtime: the world is locked."}
	return check


## The room kind the current placing tool builds.
func _placing_def() -> TileDef:
	match mode:
		Mode.DEN:
			return den_def
		Mode.POST:
			return post_def
		Mode.PLACE:
			return _placing_loaded
		_:
			return town_def


func _update_hover(screen: Vector2) -> void:
	_ghost_room.visible = false
	_ghost_road.visible = false
	var target := _target_at(screen)
	if target.is_empty():
		_lbl_status.text = ""
		return
	var check: Dictionary = target["check"]
	var ok := bool(check["ok"])
	var tint := LINE if ok else BAD
	_ghost_mat.emission = tint
	_ghost_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.55).darkened(0.75)
	_ghost_mat.albedo_color.a = 0.55
	var kind: String = target["kind"]
	if kind == "walk":
		_ghost_road.transform = _road_transform(target["key"])
		_ghost_road.transform.origin.y = 0.08
		_ghost_road.visible = true
	else:
		var vp := HexGrid.vertex_pos(target["key"], SIZE)
		_ghost_room.position = Vector3(vp.x, 0.2, vp.y)
		_ghost_room.visible = true
	_lbl_status.text = "%s: %s" % [kind.replace("_", " ").capitalize(), "ok" if ok else String(check["reason"])]


func _apply(screen: Vector2) -> void:
	if cycle.fighting():
		return
	var target := _target_at(screen)
	if mode == Mode.SELECT:
		selected = target["key"] if not target.is_empty() else HexGrid.NONE
		_refresh_zone()
		_refresh_panel()
		return
	if target.is_empty():
		return
	var check: Dictionary = target["check"]
	if not bool(check["ok"]):
		_log(String(check["reason"]))
		return
	match String(target["kind"]):
		"room":
			cycle.place_tile(target["key"], target["def"])
		"erase_room":
			cycle.erase_tile(target["key"])
		"walk", "walk_vertex":
			cycle.travel_party(target["to"])
	_sync_all()
	_refresh_hud()
	_update_hover(screen)


# ------------------------------------------------------------------- input

## Camera controls use _input so they work wherever the cursor is.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		match click.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = click.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = click.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if click.pressed:
					_dist = clampf(_dist - 0.8, 4.0, 24.0)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if click.pressed:
					_dist = clampf(_dist + 0.8, 4.0, 24.0)
					_update_camera()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _rotating:
			_yaw -= motion.relative.x * 0.008
			_pitch = clampf(_pitch + motion.relative.y * 0.006, 0.4, 1.45)
			_update_camera()
		elif _panning:
			var k := _dist * 0.0013
			var shift := -_right() * motion.relative.x * k + _forward() * motion.relative.y * k
			_focus += Vector3(shift.x, 0.0, shift.y)
			_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB and not cycle.fighting():
		_open_party_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_apply(click.position)
	elif key != null:
		if key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_6:
			var index := key.keycode - KEY_1
			_mode_buttons[index].button_pressed = true
			_set_mode(index)


## Finds every room definition on disk. Exits, origins and segnos are left out: the board
## makes its own.
func _load_room_defs() -> void:
	_room_defs.clear()
	_scan_rooms(ROOM_DIR)
	_room_defs.sort_custom(func(a: TileDef, b: TileDef) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name)
	print("[hexboard] %d room definitions found under %s" % [_room_defs.size(), ROOM_DIR])


func _scan_rooms(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_rooms(path.path_join(sub))
	for file in dir.get_files():
		var fname := file.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var res := load(path.path_join(fname))
		if res is TileDef and (res as TileDef).role == TileDef.Role.NORMAL:
			_room_defs.append(res as TileDef)


func _def_tooltip(def: TileDef) -> String:
	var kind: String = String(TileDef.Category.keys()[def.category]).capitalize()
	var text := "%s (%s)\nCost: %d red, %d green, %d blue" % [
			def.display_name, kind, roundi(def.color.x / 10.0), roundi(def.color.y / 10.0),
			roundi(def.color.z / 10.0)]
	if def.build_segments > 0:
		text += "\nBuilds in %d segments" % def.build_segments
	if def.description != "":
		text += "\n" + def.description
	return text


func _pick_room(def: TileDef) -> void:
	_placing_loaded = def
	_set_mode(Mode.PLACE)


func _set_mode(value: int) -> void:
	mode = value as Mode
	_ghost_room.visible = false
	_ghost_road.visible = false
	_lbl_status.text = ""
	if mode != Mode.SELECT and selected != HexGrid.NONE:
		selected = HexGrid.NONE
		_refresh_zone()
		_refresh_panel()


func _keyboard_camera(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += _forward()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= _forward()
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += _right()
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= _right()
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if move == Vector2.ZERO and turn == 0.0:
		return
	if move != Vector2.ZERO:
		var step := move.normalized() * _dist * 0.9 * delta
		_focus += Vector3(step.x, 0.0, step.y)
	_yaw += turn * 1.8 * delta
	_update_camera()


# ------------------------------------------------------------- the loop

func _on_segment_changed(_segment: int) -> void:
	time_left = SEGMENT_SECONDS
	overtime = false
	_sync_all()
	_refresh_hud()


## The run ended (the party fell, or raiders took the origin): show the game-over panel.
func _on_run_ended(reason: String) -> void:
	selected = HexGrid.NONE
	if _over_label != null:
		_over_label.text = reason
	_sync_all()
	_refresh_hud()


## Starts a fresh run on the same board seed and puts the sandbox back to its opening state.
func _restart_run() -> void:
	if cycle.phase != HexDayCycle.Phase.OVER:
		return
	selected = HexGrid.NONE
	overtime = false
	time_left = SEGMENT_SECONDS
	for b in cycle.party:
		b.refill()
	cycle.begin_run()
	_log("A new run begins. The origin grows the roads. Build rooms where they end.")
	_sync_all()
	_refresh_cells()
	_refresh_hud()


func _end_segment() -> void:
	var result := cycle.begin_next_segment()
	if result.is_empty():
		_log("Can't end the segment right now.")
		return
	if result.has("income"):
		var gains: PackedStringArray = []
		var income: Dictionary = result["income"]
		for id in income:
			gains.append("%s +%d" % [String(id).replace("_notes", ""), int(income[id])])
		_log("New day. Income: %s." % (", ".join(gains) if not gains.is_empty() else "none"))
	_sync_all()
	_refresh_hud()


func _process(delta: float) -> void:
	_time += delta
	_keyboard_camera(delta)

	var centre := HexGrid.pixel_to_hex(Vector2(_focus.x, _focus.z), SIZE)
	if centre != _center_hex:
		_center_hex = centre
		_refresh_cells()
	_ground.position = Vector3(_focus.x, 0.0, _focus.z)
	_ground_mat.set_shader_parameter("focus", Vector2(_focus.x, _focus.z))

	if cycle.phase == HexDayCycle.Phase.PLAN and not overtime:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			overtime = true
			_log("Overtime. Building is locked. (The chaser isn't built yet.)")
			_refresh_hud()
	for i in _awake_cells:
		var mat := (_cells[i]["mat"] as StandardMaterial3D)
		mat.emission_energy_multiplier = 0.9 + 0.3 * sin(_time * 3.0 + i * 0.7)
	_lbl_timer.text = "Overtime" if overtime else "Time left: %d s" % ceili(time_left)


# --------------------------------------------------------------------- HUD

func _refresh_hud() -> void:
	if _lbl_title == null:
		return
	var names: Array = HexDayCycle.Segment.keys()
	var parts: PackedStringArray = []
	for i in names.size():
		var seg_name: String = String(names[i]).capitalize()
		parts.append("[%s]" % seg_name if i == cycle.segment else seg_name)
	_lbl_title.text = "Day %d:  %s" % [cycle.day, "  ".join(parts)]
	var rolled: PackedStringArray = []
	for r in cycle.rolls:
		rolled.append(str(r))
	_lbl_roll.text = "Roll: %s    Awake hexes: %d" % [", ".join(rolled), cycle.awake.size()]
	var notes: PackedStringArray = []
	var tags := ["Red", "Green", "Blue"]
	for i in 3:
		notes.append("%s %d" % [tags[i], int(cycle.stock.get(config.note_ids[i], 0))])
	_lbl_stock.text = "Notes: " + "   ".join(notes) + "    Hyle %d / %d  (next segment takes %d of each)" % [
			cycle.hyle, cycle.hyle_cost_of_next_road(), cycle.hyle_draw()]
	var planning := cycle.phase == HexDayCycle.Phase.PLAN
	if _lbl_origin != null:
		var origin_tile: TileInstance = cycle.world.structures.get(cycle.origin_vertex())
		if origin_tile != null and config.frontier_raids_enabled:
			_lbl_origin.text = "Origin: %d / %d    Frontier raiders: %d" % [
					maxi(0, origin_tile.health), cycle.effective_max_health(origin_tile),
					cycle.frontier_raider_count()]
			_lbl_origin.modulate = Color(1.0, 0.45, 0.4) if origin_tile.health < cycle.effective_max_health(origin_tile) else Color.WHITE
		else:
			_lbl_origin.text = ""
	if _over_panel != null:
		_over_panel.visible = cycle.phase == HexDayCycle.Phase.OVER
	_btn_end.disabled = cycle.fighting() or not (planning or cycle.phase == HexDayCycle.Phase.SUMMARY)
	_btn_end.text = "End day" if cycle.segment == HexDayCycle.Segment.DUSK else "End segment"
	for i in _mode_buttons.size():
		_mode_buttons[i].disabled = (not planning or overtime) and i != int(Mode.SELECT)
	_refresh_tags()
	_refresh_panel()


# ------------------------------------------------------ selected-room panel

func _price_text(price: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in price:
		parts.append("%d %s" % [int(price[key]), String(key).replace("_notes", "")])
	return ", ".join(parts) if not parts.is_empty() else "free"


func _panel_line(text: String, dim := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(240.0, 0.0)
	if dim:
		label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	_panel_box.add_child(label)
	return label


## Rebuilds the Select tool's panel: the room's stats, and a button for each building it can
## be upgraded into (greyed with the reason when it can't be bought).
func _refresh_panel() -> void:
	if _panel == null or _panel_box == null:
		return
	for child in _panel_box.get_children():
		_panel_box.remove_child(child)
		child.queue_free()
	var tile: TileInstance = cycle.world.structures.get(selected) if selected != HexGrid.NONE else null
	_panel.visible = tile != null
	if tile == null:
		return
	var sizes := ["Small", "Medium", "Large"]
	var title := _panel_line(tile.def.display_name)
	title.add_theme_font_size_override("font_size", 18)
	if not tile.is_built():
		_panel_line("Under construction: %d segment(s) left." % tile.build_left, true)
		return
	if tile.def.is_origin or tile.def.is_exit:
		_panel_line("The gate.", true)
		return
	_panel_line("Health %d / %d" % [tile.health, cycle.effective_max_health(tile)])
	if tile.def.clef() == TileDef.Clef.BASS:
		_panel_line("Spawn tokens per awake hex: %d" % cycle.effective_spawn_count(tile))
		if cycle.is_safe_room(tile):
			_panel_line("%s room: holds %d, safe zone reach %d. Holding %d now." % [
					sizes[cycle.room_size(tile)], cycle.room_capacity(tile),
					cycle.cover_radius(tile), cycle.room_held(selected)])
	if tile.def.ally != null or cycle.allies_of(selected) > 0:
		var patrol := cycle.ally_behavior_of(tile) == int(TileDef.AllyBehavior.PATROL)
		_panel_line("Defenders: %d (%s)" % [cycle.allies_of(selected), "patrol" if patrol else "guard"])
	if not tile.lineage.is_empty():
		_panel_line("Upgraded %d time(s)." % tile.lineage.size(), true)
	var shown := false
	for up in tile.def.upgrades:
		if up == null or up.into == null:
			continue
		if not shown:
			_panel_line("Can become", true)
			shown = true
		var check := _gate(cycle.can_upgrade(selected, up.id))
		var b := Button.new()
		b.text = "%s  (%s)" % [up.label(), _price_text(cycle.upgrade_cost(up))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not bool(check["ok"])
		b.tooltip_text = up.description if bool(check["ok"]) else "%s\n%s" % [up.description, String(check["reason"])]
		b.pressed.connect(_buy_upgrade.bind(up.id))
		_panel_box.add_child(b)
		if not bool(check["ok"]):
			_panel_line("   " + String(check["reason"]), true)
	if not shown:
		_panel_line("Nothing further to upgrade into.", true)


func _buy_upgrade(id: StringName) -> void:
	if selected == HexGrid.NONE or overtime:
		return
	cycle.upgrade_tile(selected, id)
	_sync_all()
	_refresh_hud()


func _log(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 4:
		_log_lines.pop_front()
	if _lbl_log != null:
		_lbl_log.text = "\n".join(_log_lines)


## Plain Godot controls in containers, so everything stays inside the window at any size.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	layer.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# ---- top: day info on the left, tools on the right
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(info)
	_lbl_title = _label(info)
	_lbl_title.add_theme_font_size_override("font_size", 20)
	_lbl_roll = _label(info)
	_lbl_stock = _label(info)
	_lbl_timer = _label(info)
	_lbl_origin = _label(info)
	var hint := _label(info)
	hint.text = "Right-drag / Q E: rotate    WASD / middle-drag: pan    Wheel: zoom"
	hint.modulate = Color(1.0, 1.0, 1.0, 0.5)
	top.add_child(_spacer(true))
	var tools := VBoxContainer.new()
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tools)
	var group := ButtonGroup.new()
	var entries := [["1  Room", Mode.TOWN], ["2  Dungeon room", Mode.DEN],
			["3  Guard post", Mode.POST], ["4  Erase", Mode.ERASE], ["5  Select", Mode.SELECT],
			["6  Walk", Mode.WALK]]
	for entry: Array in entries:
		var b := Button.new()
		b.text = entry[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = int(entry[1]) == int(mode)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(150.0, 0.0)
		b.pressed.connect(_set_mode.bind(int(entry[1])))
		tools.add_child(b)
		_mode_buttons.append(b)

	# ---- rooms found on disk, one tool each
	if not _room_defs.is_empty():
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(150.0, 180.0)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tools.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for def in _room_defs:
			var rb := Button.new()
			rb.text = def.display_name if def.display_name != "" else String(def.id)
			rb.toggle_mode = true
			rb.button_group = group
			rb.focus_mode = Control.FOCUS_NONE
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rb.tooltip_text = _def_tooltip(def)
			rb.pressed.connect(_pick_room.bind(def))
			list.add_child(rb)
			_mode_buttons.append(rb)

	# ---- the selected room's panel (filled by _refresh_panel)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(260.0, 0.0)
	_panel.visible = false
	tools.add_child(_panel)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	_panel.add_child(pad)
	_panel_box = VBoxContainer.new()
	pad.add_child(_panel_box)

	column.add_child(_spacer(false))

	# ---- bottom: log on the left, the two actions on the right
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(left)
	_lbl_log = _label(left)
	_lbl_log.custom_minimum_size = Vector2(200.0, 0.0)
	_lbl_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_status = _label(left)
	_lbl_status.modulate = Color(1.0, 1.0, 1.0, 0.7)
	var actions := VBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(actions)
	_btn_end = Button.new()
	_btn_end.text = "End segment"
	_btn_end.focus_mode = Control.FOCUS_NONE
	_btn_end.custom_minimum_size = Vector2(150.0, 0.0)
	_btn_end.pressed.connect(_end_segment)
	actions.add_child(_btn_end)
	var party_btn := Button.new()
	party_btn.text = "Party (Tab)"
	party_btn.focus_mode = Control.FOCUS_NONE
	party_btn.custom_minimum_size = Vector2(150.0, 0.0)
	party_btn.pressed.connect(_open_party_menu)
	actions.add_child(party_btn)

	# ---- game over: centred over everything, hidden until the run ends
	_over_panel = PanelContainer.new()
	_over_panel.visible = false
	_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(_over_panel)
	var over_pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		over_pad.add_theme_constant_override("margin_" + side, 24)
	_over_panel.add_child(over_pad)
	var over_box := VBoxContainer.new()
	over_box.add_theme_constant_override("separation", 12)
	over_pad.add_child(over_box)
	var over_title := Label.new()
	over_title.text = "GAME OVER"
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_title.add_theme_font_size_override("font_size", 36)
	over_title.add_theme_color_override("font_color", RAIDER_TINT)
	over_box.add_child(over_title)
	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_label.custom_minimum_size = Vector2(320.0, 0.0)
	over_box.add_child(_over_label)
	var restart_btn := Button.new()
	restart_btn.text = "Start a new run"
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.pressed.connect(_restart_run)
	over_box.add_child(restart_btn)


## Opens the party menu directly. Its own TAB check needs the full game's world layer, which
## the sandbox doesn't have, so the board opens it instead (and the menu closes itself on TAB).
func _open_party_menu() -> void:
	if cycle.fighting():
		_log("Not during a fight.")
		return
	var menu := get_tree().get_first_node_in_group("party_menu") as PartyMenu
	if menu == null:
		_log("The party menu isn't available.")
		return
	if Rules.roster == null:
		_log("There is no roster yet.")
		return
	menu.show_menu()


func _label(parent: Node) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _spacer(horizontal: bool) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
