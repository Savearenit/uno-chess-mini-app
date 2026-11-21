extends Node3D

const COLORS := [Color("#f04445"), Color("#3187e8"), Color("#2dbb73"), Color("#f0c735")]
const COLOR_NAMES := ["Красная", "Синяя", "Зелёная", "Жёлтая"]
const KIND_COLOR := {"P":0, "N":1, "B":2, "R":3, "Q":-1, "K":-1}
const GLYPH := {"P":"♟", "N":"♞", "B":"♝", "R":"♜", "Q":"♛", "K":"♚"}
var board: Array = []
var turn := 0
var side_for_player := [0, 1]
var card: Dictionary = {}
var pile: Array = []
var discard: Array = []
var bonus_draws := [0, 0]
var skip_opponent := false
var selected := Vector2i(-1, -1)
var over := false
var winner := 0
var playing := false
var ai_pending := false
var game_generation := 0
var board_animating := false
var pending_reversals := 0
var board_tween: Tween
var table: Node3D
var pieces: Node3D
var piece_models := {}
var cam: Camera3D
var tiles: Array = []
var menu_layer: CanvasLayer
var game_layer: CanvasLayer
var menu_ui: Control
var menu_panel: PanelContainer
var rules_label: Label
var game_ui: Control
var status: Label
var player_info: Label
var card_panel: PanelContainer
var side_panel: PanelContainer
var card_name: Label
var card_value: Label
var message: Label
var help_label: Label

func _ready() -> void:
	_make_world()
	_load_piece_models()
	_make_board()
	_make_ui()
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()
	_show_menu()

func _make_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skym := ProceduralSkyMaterial.new()
	skym.sky_top_color = Color("#10213b")
	skym.sky_horizon_color = Color("#8797a5")
	skym.ground_bottom_color = Color("#111723")
	skym.ground_horizon_color = Color("#303a48")
	sky.sky_material = skym
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c3d4e8")
	e.ambient_light_energy = 0.48
	env.environment = e
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -30, 0)
	light.light_energy = 0.72
	light.shadow_enabled = true
	light.shadow_blur = 2.0
	add_child(light)
	cam = Camera3D.new()
	cam.position = Vector3(-1.6, 12, 14)
	cam.fov = 40
	add_child(cam)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -0.55
	ground.material_override = _mat(Color("#17202e"), 0.8)
	add_child(ground)

func _load_piece_models() -> void:
	var files := {"P":"pawn", "N":"knight", "B":"bishop", "R":"rook", "Q":"queen", "K":"king"}
	for kind in files:
		for side in ["w", "b"]:
			var color_name := "orange" if side == "w" else "blue"
			var path := "res://assets/chess/glb/%s-%s.glb" % [files[kind], color_name]
			var scene := load(path) as PackedScene
			if scene != null: piece_models[side + kind] = scene
	if piece_models.size() < 12:
		push_warning("Some chess GLB files could not be imported; fallback geometry will be used.")

func _make_board() -> void:
	for y in range(8):
		var row: Array = []
		for x in range(8): row.append("" )
		board.append(row)
	table = Node3D.new()
	add_child(table)
	var wood := _mat(Color("#35251f"), 0.32)
	_add_box(table, Vector3(9.4, 0.48, 9.4), Vector3(0, -0.28, 0), wood)
	pieces = Node3D.new()
	table.add_child(pieces)
	var cells: Array = []
	for y in range(8):
		var row: Array = []
		for x in range(8):
			var p := _pos(y, x)
			var tile := MeshInstance3D.new()
			var cube := BoxMesh.new()
			cube.size = Vector3(0.99, 0.11, 0.99)
			tile.mesh = cube
			tile.position = Vector3(p.x, 0.35, p.z)
			tile.material_override = _mat(Color("#9b8468") if (x+y)%2==0 else Color("#3b4650"), 0.62)
			tile.visible = true
			table.add_child(tile)
			var body := StaticBody3D.new()
			body.position = Vector3(p.x, 0.35, p.z)
			body.set_meta("y", y)
			body.set_meta("x", x)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1, 0.12, 1)
			shape.shape = box
			body.add_child(shape)
			table.add_child(body)
			row.append(tile)
		tiles.append(row)

func _make_ui() -> void:
	menu_layer = CanvasLayer.new(); menu_layer.layer = 2; add_child(menu_layer)
	menu_ui = Control.new(); menu_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu_layer.add_child(menu_ui)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/menu_background.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_ui.add_child(bg)
	var shade := ColorRect.new(); shade.color = Color(0.015, 0.025, 0.06, 0.52); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; menu_ui.add_child(shade)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu_ui.add_child(center)
	menu_panel = PanelContainer.new(); menu_panel.custom_minimum_size = Vector2(500, 560); menu_panel.add_theme_stylebox_override("panel", _style(Color(0.02,0.045,0.08,0.9), Color("#d9b761"))); center.add_child(menu_panel)
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", 14); menu_panel.add_child(stack)
	var title := Label.new(); title.text = "UNO CHESS"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 48); title.add_theme_color_override("font_color", Color("#fff0c9")); stack.add_child(title)
	var subtitle := Label.new(); subtitle.text = "ДВА МИРА. ОДИН ХОД."; subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; subtitle.add_theme_color_override("font_color", Color("#d5e1ef")); stack.add_child(subtitle)
	var start := _button("НАЧАТЬ ПАРТИЮ", Color("#b63b3e")); start.pressed.connect(_start); stack.add_child(start)
	rules_label = Label.new()
	rules_label.text = "ЦВЕТ: красный — пешка, синий — конь, зелёный — слон, жёлтый — ладья. Дикая карта разрешает любую фигуру.\n\nЦИФРА: для ладьи и слона задаёт максимальную дальность; 0 — без ограничения. Конь не ходит по карте 1, а 0 и 2–9 разрешают прыжок. Пешка может пройти два поля с цифрой 0 или 2–9.\n\nРАЗВОРОТ меняет игроков местами по цветам и поворачивает доску. ПРОПУСК сохраняет ход тебе, соперник пропускает. +2 и +4 дают сопернику дополнительные случайные доборы; действует последняя карта. Нет хода — карта тянется заново."
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rules_label.add_theme_color_override("font_color", Color("#e4ebf4")); rules_label.add_theme_font_size_override("font_size", 15); stack.add_child(rules_label)
	var note := Label.new(); note.text = "Ты играешь против компьютера • цель — взять короля"; note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; note.add_theme_font_size_override("font_size", 12); note.add_theme_color_override("font_color", Color("#b8c4d4")); stack.add_child(note)

	game_layer = CanvasLayer.new(); game_layer.layer = 3; add_child(game_layer)
	game_ui = Control.new(); game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; game_layer.add_child(game_ui)
	side_panel = PanelContainer.new(); side_panel.anchor_left=1; side_panel.anchor_right=1; side_panel.offset_left=-326; side_panel.offset_right=-18; side_panel.offset_top=20; side_panel.offset_bottom=-20; side_panel.add_theme_stylebox_override("panel", _style(Color(0.02,0.04,0.08,0.94), Color("#647d98"))); game_ui.add_child(side_panel)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 10); side_panel.add_child(col)
	var back := _button("←  В МЕНЮ", Color("#364b64")); back.pressed.connect(_show_menu); col.add_child(back)
	var restart := _button("↻  НОВАЯ ПАРТИЯ", Color("#596b52")); restart.pressed.connect(_start); col.add_child(restart)
	status = Label.new(); status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; status.add_theme_font_size_override("font_size",23); status.add_theme_color_override("font_color", Color("#fff0c9")); col.add_child(status)
	player_info = Label.new(); player_info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; player_info.add_theme_color_override("font_color", Color("#cad7e7")); col.add_child(player_info)
	var cap := Label.new(); cap.text="СЛУЧАЙНАЯ КАРТА ХОДА"; cap.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; cap.add_theme_font_size_override("font_size",13); col.add_child(cap)
	card_panel = PanelContainer.new(); card_panel.custom_minimum_size=Vector2(240,145); col.add_child(card_panel)
	var card_stack := VBoxContainer.new(); card_stack.alignment=BoxContainer.ALIGNMENT_CENTER; card_panel.add_child(card_stack)
	card_name = Label.new(); card_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; card_name.add_theme_font_size_override("font_size",16); card_stack.add_child(card_name)
	card_value = Label.new(); card_value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; card_value.add_theme_font_size_override("font_size",52); card_stack.add_child(card_value)
	message = Label.new(); message.custom_minimum_size=Vector2(250,105); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; message.add_theme_color_override("font_color", Color("#f1d897")); col.add_child(message)
	help_label = Label.new(); help_label.text="Золотые кольца отмечают фигуры, которыми можно ходить. Нажми фигуру, затем клетку назначения."; help_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; help_label.add_theme_font_size_override("font_size",13); help_label.add_theme_color_override("font_color", Color("#c5d1e0")); col.add_child(help_label)

func _layout_for_viewport() -> void:
	if not is_instance_valid(side_panel): return
	var view_size := get_viewport().get_visible_rect().size
	var compact := view_size.x < 820.0
	menu_panel.custom_minimum_size = Vector2(maxf(view_size.x - 24.0, 320.0), 560.0) if compact else Vector2(500, 560)
	rules_label.add_theme_font_size_override("font_size", 13 if compact else 15)
	if compact:
		side_panel.anchor_left = 0.0
		side_panel.anchor_right = 1.0
		side_panel.anchor_top = 1.0
		side_panel.anchor_bottom = 1.0
		side_panel.offset_left = 8
		side_panel.offset_right = -8
		side_panel.offset_top = -405
		side_panel.offset_bottom = -8
		card_panel.custom_minimum_size.y = 82
		card_value.add_theme_font_size_override("font_size", 40)
		message.custom_minimum_size.y = 70
		help_label.visible = false
		cam.position = Vector3(-1.6, 19, 23)
	else:
		side_panel.anchor_left = 1.0
		side_panel.anchor_right = 1.0
		side_panel.anchor_top = 0.0
		side_panel.anchor_bottom = 0.0
		side_panel.offset_left = -326
		side_panel.offset_right = -18
		side_panel.offset_top = 20
		side_panel.offset_bottom = -20
		card_panel.custom_minimum_size.y = 145
		card_value.add_theme_font_size_override("font_size", 52)
		message.custom_minimum_size.y = 105
		help_label.visible = true
		cam.position = Vector3(-1.6, 12, 14)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)

func _show_menu() -> void:
	playing = false
	# Keep the 3D table visible; the opaque menu background covers it until play starts.
	table.visible = true
	menu_ui.visible = true
	game_ui.visible = false

func _start() -> void:
	game_generation += 1
	if board_tween != null: board_tween.kill()
	board_animating = false
	pending_reversals = 0
	board.clear()
	for y in range(8):
		var row: Array = []
		for x in range(8): row.append("" )
		board.append(row)
	var back := ["R","N","B","Q","K","B","N","R"]
	for x in range(8):
		board[0][x]="b"+back[x]; board[1][x]="bP"; board[6][x]="wP"; board[7][x]="w"+back[x]
	turn=0; side_for_player=[0,1]; selected=Vector2i(-1,-1); over=false; winner=0; ai_pending=false; board_animating=false; pending_reversals=0; skip_opponent=false; bonus_draws=[0,0]; table.rotation=Vector3.ZERO
	_build_deck()
	discard.clear()
	card=_draw()
	while card.kind != "number": discard.append(card); card=_draw()
	discard.append(card)
	playing=true; table.visible=true; menu_ui.visible=false; game_ui.visible=true
	_begin_turn()

func _build_deck() -> void:
	pile.clear()
	for c in range(4):
		pile.append({"color":c,"value":"0","kind":"number"})
		for n in range(1,10):
			for i in range(2): pile.append({"color":c,"value":str(n),"kind":"number"})
		for i in range(2):
			pile.append({"color":c,"value":"↻","kind":"reverse"}); pile.append({"color":c,"value":"⊘","kind":"skip"}); pile.append({"color":c,"value":"+2","kind":"draw2"})
	for i in range(4): pile.append({"color":-1,"value":"WILD","kind":"wild"}); pile.append({"color":-1,"value":"+4","kind":"wild4"})
	pile.shuffle()

func _draw() -> Dictionary:
	if pile.is_empty():
		pile = discard.duplicate(); discard.clear(); pile.shuffle()
		if pile.is_empty(): _build_deck()
	return pile.pop_back()

func _begin_turn() -> void:
	var loops := 0
	while loops < 150:
		loops += 1
		card = _draw()
		for i in range(bonus_draws[turn]): discard.append(card); card = _draw()
		bonus_draws[turn] = 0
		discard.append(card)
		if card.kind == "reverse":
			side_for_player[0]=1-side_for_player[0]; side_for_player[1]=1-side_for_player[1]; pending_reversals += 1; _animate_next_reverse()
			message.text="РАЗВОРОТ! Игроки сменили цвет фигур и сторону доски."
		elif card.kind == "draw2":
			bonus_draws[1-turn] += 2
			message.text="+2: соперник доберёт две дополнительные карты в начале своего хода."
		elif card.kind == "wild4":
			bonus_draws[1-turn] += 4
			message.text="+4: соперник доберёт четыре дополнительные карты в начале своего хода."
		elif card.kind == "skip": skip_opponent=true; message.text="Пропуск: после твоего хода соперник пропустит."
		elif card.kind == "wild": message.text="Дикая карта: ходить может любая фигура."
		else: message.text="Цвет выбирает тип фигуры. Цифра ограничивает дальность слона и ладьи; 1 запрещает ход коня, а пешка может пройти два поля с цифрой 0 или 2–9."
		if _available().is_empty(): message.text="Нет хода по этой карте — вытягивается следующая."; continue
		break
	if loops >= 150: over=true; winner=0; message.text="Нет допустимых ходов. Ничья."
	selected=Vector2i(-1,-1)
	_refresh()

func _available() -> Array:
	var found: Array=[]
	var side_code := "w" if side_for_player[turn]==0 else "b"
	for y in range(8):
		for x in range(8):
			if board[y][x].begins_with(side_code) and _has_move(y,x): found.append(Vector2i(y,x))
	return found

func _has_move(y:int,x:int) -> bool:
	for ty in range(8):
		for tx in range(8):
			if _legal(y,x,ty,tx): return true
	return false

func _legal(y:int,x:int,ty:int,tx:int) -> bool:
	var p:String=board[y][x]
	if p.is_empty() or (y==ty and x==tx): return false
	var side=p.substr(0,1); var kind=p.substr(1); var dest:String=board[ty][tx]
	if (side=="w") != (side_for_player[turn]==0): return false
	if not dest.is_empty() and dest.substr(0,1)==side: return false
	if card.kind!="wild" and card.kind!="wild4" and int(card.color)!=int(KIND_COLOR[kind]): return false
	var dy=ty-y; var dx=tx-x; var ay=abs(dy); var ax=abs(dx)
	var n=int(card.value) if card.kind=="number" else 0
	match kind:
		"P":
			var dir=-1 if side=="w" else 1; var start=6 if side=="w" else 1
			if dx==0 and dest.is_empty() and dy==dir: return true
			if dx==0 and dest.is_empty() and y==start and dy==2*dir and (n==0 or n>=2) and board[y+dir][x].is_empty(): return true
			if ax==1 and dy==dir and not dest.is_empty(): return true
		"N": return n!=1 and ((ay==2 and ax==1) or (ay==1 and ax==2))
		"B": return ay==ax and ay>0 and (n==0 or ay<=n) and _clear(y,x,ty,tx)
		"R": return (dx==0 or dy==0) and (dx!=0 or dy!=0) and (n==0 or max(ax,ay)<=n) and _clear(y,x,ty,tx)
		"Q": return (ay==ax or dx==0 or dy==0) and (ay+ax)>0 and _clear(y,x,ty,tx)
		"K": return ay<=1 and ax<=1 and (ay+ax)>0
	return false

func _clear(y:int,x:int,ty:int,tx:int) -> bool:
	var sy:int=int(sign(ty-y)); var sx:int=int(sign(tx-x)); var cy=y+sy; var cx=x+sx
	while cy!=ty or cx!=tx:
		if not board[cy][cx].is_empty(): return false
		cy+=sy; cx+=sx
	return true

func _unhandled_input(event:InputEvent) -> void:
	if not playing or over or board_animating or turn == 1: return
	var pointer: Vector2
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pointer = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pointer = event.position
	else:
		return
	var ray_from := table.to_local(cam.project_ray_origin(pointer))
	var ray_to := table.to_local(cam.project_ray_origin(pointer) + cam.project_ray_normal(pointer) * 100.0)
	var direction := ray_to - ray_from
	if absf(direction.y) < 0.0001: return
	var t := (0.42 - ray_from.y) / direction.y
	if t < 0.0: return
	var hit := ray_from + direction * t
	var x := roundi(hit.x + 3.5)
	var y := roundi(3.5 - hit.z)
	if x >= 0 and x < 8 and y >= 0 and y < 8: _click_cell(y, x)

func _click_cell(y:int,x:int) -> void:
	var p:String=board[y][x]; var code="w" if side_for_player[turn]==0 else "b"
	if selected.x<0:
		if p.begins_with(code) and _has_move(y,x): selected=Vector2i(y,x); _refresh()
		return
	if selected==Vector2i(y,x): selected=Vector2i(-1,-1); _refresh(); return
	if _legal(selected.x,selected.y,y,x):
		var taken:String=board[y][x]; var moving:String=board[selected.x][selected.y]
		board[selected.x][selected.y]=""; board[y][x]=moving
		if moving.ends_with("P") and ((moving.begins_with("w") and y==0) or (moving.begins_with("b") and y==7)): board[y][x]=moving.substr(0,1)+"Q"
		if taken.ends_with("K"): over=true; winner=turn+1; message.text="Король взят! Победил игрок %d." % winner; selected=Vector2i(-1,-1); _refresh(); return
		if skip_opponent: skip_opponent=false; message.text="Соперник пропускает. Твой дополнительный ход."
		else: turn=1-turn
		_begin_turn()
	elif p.begins_with(code) and _has_move(y,x): selected=Vector2i(y,x); _refresh()
	else: selected=Vector2i(-1,-1); _refresh()

func _refresh() -> void:
	if not playing: return
	var possible=_available()
	for y in range(8):
		for x in range(8):
			var m:MeshInstance3D=tiles[y][x]; var color=Color("#42bfae")
			var highlighted := false
			if selected.x>=0 and _legal(selected.x,selected.y,y,x): highlighted=true
			elif selected==Vector2i(y,x): color=Color("#efbc53"); highlighted=true
			m.visible=true
			m.material_override=_mat(Color("#a9864c") if selected==Vector2i(y,x) else (Color("#718d78") if highlighted else (Color("#9b8468") if (x+y)%2==0 else Color("#3b4650"))),0.62)
	for c in pieces.get_children(): pieces.remove_child(c); c.queue_free()
	for y in range(8):
		for x in range(8):
			var p:String=board[y][x]
			if p.is_empty(): continue
			var root:=_piece(p); var pos=_pos(y,x); root.position=Vector3(pos.x,0.35,pos.z); pieces.add_child(root)
			if Vector2i(y,x) in possible: _ring_at(pos)
	status.text=("ПОБЕДА КОМПЬЮТЕРА" if winner == 2 else ("ТЫ ПОБЕДИЛ" if winner == 1 else "НИЧЬЯ")) if over else ("ХОД КОМПЬЮТЕРА" if turn == 1 else "ТВОЙ ХОД")
	player_info.text="Партия завершена. Нажми «В меню», чтобы сыграть ещё." if over else ("Компьютер управляет %s фигурами" % ("белыми" if side_for_player[turn]==0 else "чёрными") if turn == 1 else "Управляешь %s фигурами" % ("белыми" if side_for_player[turn]==0 else "чёрными"))
	card_name.text="ДИКАЯ" if int(card.color)<0 else COLOR_NAMES[int(card.color)]
	card_value.text=str(card.value)
	var c:Color=Color("#59657a") if int(card.color)<0 else COLORS[int(card.color)]
	card_panel.visible = not over
	card_panel.add_theme_stylebox_override("panel",_style(c,c.lightened(0.3)))
	card_name.add_theme_color_override("font_color",Color.WHITE if c.get_luminance()<0.55 else Color("#202536"))
	card_value.add_theme_color_override("font_color",Color.WHITE if c.get_luminance()<0.55 else Color("#202536"))
	if turn == 1 and playing and not over and not ai_pending:
		ai_pending = true
		call_deferred("_run_ai_turn")


func _run_ai_turn() -> void:
	var this_game := game_generation
	await get_tree().create_timer(0.65).timeout
	if this_game != game_generation: return
	while board_animating: await get_tree().process_frame
	if not playing or over or turn != 1:
		ai_pending = false
		return
	var candidates: Array[Dictionary] = []
	var best_score := -INF
	var side_code := "w" if side_for_player[turn] == 0 else "b"
	for y in range(8):
		for x in range(8):
			if not board[y][x].begins_with(side_code): continue
			for ty in range(8):
				for tx in range(8):
					if not _legal(y, x, ty, tx): continue
					var target: String = board[ty][tx]
					var score := randf() * 0.8
					if not target.is_empty():
						var values := {"P":1, "N":3, "B":3, "R":5, "Q":9, "K":100}
						score += float(values.get(target.substr(1), 0)) * 10.0
					if board[y][x].ends_with("P") and (ty == 0 or ty == 7): score += 80.0
					score += (3.5 - absf(float(tx) - 3.5) + 3.5 - absf(float(ty) - 3.5)) * 0.25
					if score > best_score:
						best_score = score
						candidates.clear()
						candidates.append({"from_y":y, "from_x":x, "to_y":ty, "to_x":tx})
					elif score >= best_score - 0.8:
						candidates.append({"from_y":y, "from_x":x, "to_y":ty, "to_x":tx})
	if candidates.is_empty():
		ai_pending = false
		return
	var move: Dictionary = candidates.pick_random()
	ai_pending = false
	_click_cell(int(move.from_y), int(move.from_x))
	_click_cell(int(move.to_y), int(move.to_x))
func _animate_next_reverse() -> void:
	if pending_reversals <= 0:
		board_animating = false
		return
	board_animating = true
	pending_reversals -= 1
	if board_tween != null: board_tween.kill()
	board_tween = create_tween()
	board_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	board_tween.tween_property(table, "rotation:y", table.rotation.y + PI, 1.05)
	board_tween.finished.connect(_on_reverse_finished)

func _on_reverse_finished() -> void:
	board_animating = false
	if pending_reversals > 0: _animate_next_reverse()

func _piece(p:String) -> Node3D:
	var root := Node3D.new()
	var white := p.begins_with("w")
	var kind := p.substr(1)
	var main := _mat(Color("#c9c0af") if white else Color("#171d25"), 0.24)
	var ci := int(KIND_COLOR[kind])
	var accent := _mat(Color("#92703f") if white else Color("#527b87"), 0.26)
	_cylinder(root, 0.31, 0.12, 0.06, main)
	_cylinder(root, 0.23, 0.1, 0.17, accent)
	match kind:
		"P":
			_cylinder(root, 0.13, 0.3, 0.36, main)
			_sphere(root, 0.18, 0.62, main)
		"N":
			_cylinder(root, 0.15, 0.46, 0.43, main)
			_ellipsoid(root, 0.2, Vector3(0.72, 1.15, 0.72), Vector3(0, 0.79, 0), main)
			_ellipsoid(root, 0.11, Vector3(0.8, 0.55, 0.7), Vector3(0, 0.7, -0.15), accent)
			_cone(root, 0.08, 0.22, 1.02, main)
		"B":
			_cylinder(root, 0.14, 0.34, 0.4, main)
			_cone(root, 0.18, 0.62, 0.87, main)
			_sphere(root, 0.07, 1.22, accent)
			_add_box(root, Vector3(0.035, 0.32, 0.035), Vector3(0, 0.88, 0), accent)
		"R":
			_add_box(root, Vector3(0.4, 0.18, 0.4), Vector3(0, 0.36, 0), main)
			_add_box(root, Vector3(0.36, 0.44, 0.36), Vector3(0, 0.66, 0), main)
			_add_box(root, Vector3(0.42, 0.12, 0.42), Vector3(0, 0.94, 0), accent)
			for dx in [-0.13, 0.13]:
				for dz in [-0.13, 0.13]: _add_box(root, Vector3(0.12, 0.16, 0.12), Vector3(dx, 1.06, dz), main)
		"Q":
			_cylinder(root, 0.15, 0.48, 0.47, main)
			_cone(root, 0.2, 0.38, 0.91, accent)
			_sphere(root, 0.13, 1.16, main)
			for a in range(5):
				var angle := TAU * float(a) / 5.0
				_ellipsoid(root, 0.055, Vector3.ONE, Vector3(cos(angle) * 0.18, 1.03, sin(angle) * 0.18), accent)
		"K":
			_cylinder(root, 0.16, 0.54, 0.5, main)
			_cone(root, 0.19, 0.38, 0.96, accent)
			_add_box(root, Vector3(0.09, 0.34, 0.09), Vector3(0, 1.23, 0), main)
			_add_box(root, Vector3(0.3, 0.08, 0.09), Vector3(0, 1.27, 0), main)
	return root

func _ellipsoid(parent:Node3D, radius:float, shape_scale:Vector3, pos:Vector3, mat:Material) -> void:
	var i := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radial_segments = 32
	m.rings = 16
	m.radius = radius
	m.height = radius * 2.0
	i.mesh = m
	i.position = pos
	i.scale = shape_scale
	i.material_override = mat
	parent.add_child(i)
func _ring_at(pos:Vector3) -> void:
	var m := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.34
	tor.outer_radius = 0.42
	m.mesh = tor
	m.position = Vector3(pos.x, 0.425, pos.z)
	var mat := _mat(Color("#b18b45"), 0.42)
	mat.emission_enabled = true
	mat.emission = Color("#9c772f")
	mat.emission_energy_multiplier = 0.3
	m.material_override = mat
	pieces.add_child(m)


func _pos(y:int,x:int) -> Vector3: return Vector3(float(x)-3.5,0,3.5-float(y))
func _mat(color:Color,rough:float) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new(); m.albedo_color=color; m.roughness=rough; m.metallic=0.08; return m
func _add_box(parent:Node3D,size:Vector3,pos:Vector3,mat:Material) -> void:
	var i:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=size; i.mesh=mesh; i.position=pos; i.material_override=mat; parent.add_child(i)
func _cylinder(parent:Node3D,radius:float,height:float,y:float,mat:Material) -> void:
	var i:=MeshInstance3D.new(); var m:=CylinderMesh.new(); m.radial_segments=48; m.rings=8; m.top_radius=radius*0.75; m.bottom_radius=radius; m.height=height; i.mesh=m; i.position.y=y; i.material_override=mat; parent.add_child(i)
func _cone(parent:Node3D,radius:float,height:float,y:float,mat:Material) -> void:
	var i:=MeshInstance3D.new(); var m:=CylinderMesh.new(); m.radial_segments=48; m.rings=8; m.top_radius=0.025; m.bottom_radius=radius; m.height=height; i.mesh=m; i.position.y=y; i.material_override=mat; parent.add_child(i)
func _sphere(parent:Node3D,radius:float,y:float,mat:Material) -> void:
	var i:=MeshInstance3D.new(); var m:=SphereMesh.new(); m.radial_segments=32; m.rings=16; m.radius=radius; m.height=radius*2; i.mesh=m; i.position.y=y; i.material_override=mat; parent.add_child(i)
func _style(bg:Color,border:Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new(); s.bg_color=bg; s.border_color=border; s.set_border_width_all(1); s.set_corner_radius_all(18); s.set_content_margin_all(18); s.shadow_color=Color(0,0,0,0.35); s.shadow_size=12; return s
func _button(text:String,color:Color) -> Button:
	var b:=Button.new(); b.text=text; b.custom_minimum_size=Vector2(0,52); b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; b.add_theme_font_size_override("font_size",17); b.add_theme_color_override("font_color",Color.WHITE); b.add_theme_stylebox_override("normal",_style(color,color.lightened(0.2))); b.add_theme_stylebox_override("hover",_style(color.lightened(0.15),Color("#f0cf7c"))); return b
