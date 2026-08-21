extends RefCounted
## InputHandler — 进程内合成输入（AI 可直接"按键/鼠标/手柄"驱动游戏）
## input.key:    {key:"w", action:"tap"|"hold"|"release"}   key 用 Godot 键名（w/a/s/d/escape 等）
## input.action: {action:"move_up", state:"press"|"release"} 直接操作 InputMap 动作
## input.mouse:  {x, y, action:"move"|"click"|"press"|"release", button:1..8} 视口坐标
## input.gamepad:{button:"a"|"b"|"x"|"y"|"lb"|"rb"|"start"|"back"|"l3"|"r3"|"dpad_*", action} 或 {axis_x, axis_y, action}
## input.get_state: 当前按下的动作列表 + 鼠标位置

var tree: SceneTree

# Godot InputMap 手柄按钮编号：dpad 11-14 = move_*，start 6 = ui_cancel
const GAMEPAD_BUTTONS := {
	"a": 0, "b": 1, "x": 2, "y": 3,
	"lb": 4, "rb": 5, "start": 6, "back": 7,
	"l3": 8, "r3": 9,
	"dpad_up": 11, "dpad_down": 12, "dpad_left": 13, "dpad_right": 14,
}


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "input.key",
			"description": "模拟键盘按键：tap=按下并释放, hold=持续按住, release=释放。key 用 Godot 键名如 w/a/s/d/escape/space",
			"input_schema": {
				"type": "object",
				"properties": {
					"key": {"type": "string"},
					"action": {"type": "string", "enum": ["tap", "hold", "release"]},
				},
				"required": ["key", "action"],
			},
			"callable": _key,
		},
		{
			"name": "input.action",
			"description": "直接按项目 InputMap 动作：press=按住, release=松开（如 move_up / ui_cancel）",
			"input_schema": {
				"type": "object",
				"properties": {
					"action": {"type": "string"},
					"state": {"type": "string", "enum": ["press", "release"]},
				},
				"required": ["action", "state"],
			},
			"callable": _action,
		},
		{
			"name": "input.mouse",
			"description": "合成鼠标：move=移动指针, click=按下并释放, press/release=单步。坐标为视口坐标",
			"input_schema": {
				"type": "object",
				"properties": {
					"x": {"type": "number"},
					"y": {"type": "number"},
					"action": {"type": "string", "enum": ["move", "click", "press", "release"]},
					"button": {"type": "integer", "description": "1=左 2=右，默认 1"},
				},
				"required": ["action"],
			},
			"callable": _mouse,
		},
		{
			"name": "input.gamepad",
			"description": "合成手柄输入：button 走按键（dpad 对应 move_* 动作，start=ui_cancel），或 axis_x/axis_y(-1..1) 走摇杆轴",
			"input_schema": {
				"type": "object",
				"properties": {
					"button": {"type": "string", "description": "a/b/x/y/lb/rb/start/back/l3/r3/dpad_up/dpad_down/dpad_left/dpad_right"},
					"action": {"type": "string", "enum": ["tap", "press", "release"]},
					"axis_x": {"type": "number", "description": "左摇杆 X -1..1（与 button 二选一）"},
					"axis_y": {"type": "number", "description": "左摇杆 Y -1..1"},
				},
			},
			"callable": _gamepad,
		},
		{
			"name": "input.get_state",
			"description": "查询当前按下的动作列表 + 鼠标位置",
			"input_schema": {"type": "object", "properties": {}},
			"callable": _get_state,
		},
	]


func _key(params: Dictionary) -> Variant:
	var key_name: String = str(params.get("key", "")).to_lower()
	var action: String = str(params.get("action", "tap"))
	if key_name.is_empty():
		return {"error": "缺少 key 参数"}
	var kc: int = OS.find_keycode_from_string(key_name)
	if kc == 0 and key_name != "":
		return {"error": "未知键名: %s" % key_name}
	match action:
		"hold":
			Input.parse_input_event(_make_key_event(kc, true))
		"release":
			Input.parse_input_event(_make_key_event(kc, false))
		_:
			Input.parse_input_event(_make_key_event(kc, true))
			Input.parse_input_event(_make_key_event(kc, false))
	return {"ok": true, "key": key_name, "action": action}


func _action(params: Dictionary) -> Variant:
	var action_name: String = str(params.get("action", ""))
	var state: String = str(params.get("state", "press"))
	if action_name.is_empty() or not InputMap.has_action(action_name):
		return {"error": "动作不存在: %s" % action_name}
	if state == "release":
		Input.action_release(action_name)
	else:
		Input.action_press(action_name)
	return {"ok": true, "action": action_name, "state": state}


func _mouse(params: Dictionary) -> Variant:
	var action: String = str(params.get("action", "move"))
	var pos := Vector2(float(params.get("x", 0.0)), float(params.get("y", 0.0)))
	var button: int = int(params.get("button", 1))
	match action:
		"move":
			var motion := InputEventMouseMotion.new()
			motion.position = pos
			motion.global_position = pos
			tree.root.push_input(motion)
		"press", "release":
			var e := InputEventMouseButton.new()
			e.button_index = button
			e.pressed = (action == "press")
			e.position = pos
			e.global_position = pos
			tree.root.push_input(e)
		"click":
			var motion2 := InputEventMouseMotion.new()
			motion2.position = pos
			motion2.global_position = pos
			tree.root.push_input(motion2)
			var press := InputEventMouseButton.new()
			press.button_index = button
			press.pressed = true
			press.position = pos
			press.global_position = pos
			tree.root.push_input(press)
			var release := InputEventMouseButton.new()
			release.button_index = button
			release.pressed = false
			release.position = pos
			release.global_position = pos
			tree.root.push_input(release)
		_:
			return {"error": "未知 action: %s" % action}
	return {"ok": true, "action": action, "pos": [pos.x, pos.y]}


func _gamepad(params: Dictionary) -> Variant:
	var act: String = str(params.get("action", "tap"))
	if params.has("button"):
		var name: String = str(params.get("button", "")).to_lower()
		if not GAMEPAD_BUTTONS.has(name):
			return {"error": "未知手柄键: %s" % name}
		var idx: int = GAMEPAD_BUTTONS[name]
		match act:
			"hold", "press":
				Input.parse_input_event(_make_pad_event(idx, true))
			"release":
				Input.parse_input_event(_make_pad_event(idx, false))
			_:
				Input.parse_input_event(_make_pad_event(idx, true))
				Input.parse_input_event(_make_pad_event(idx, false))
		return {"ok": true, "button": name, "button_index": idx, "action": act}
	if params.has("axis_x") or params.has("axis_y"):
		var ax: float = clampf(float(params.get("axis_x", 0.0)), -1.0, 1.0)
		var ay: float = clampf(float(params.get("axis_y", 0.0)), -1.0, 1.0)
		Input.parse_input_event(_make_axis_event(0, ax))
		Input.parse_input_event(_make_axis_event(1, ay))
		return {"ok": true, "axis": [ax, ay]}
	return {"error": "需要 button 或 axis_x/axis_y"}


func _get_state(_params: Dictionary) -> Variant:
	var pressed: Array = []
	for a in InputMap.get_actions():
		var name: String = String(a)
		if Input.is_action_pressed(name):
			pressed.append(name)
	return {
		"pressed_actions": pressed,
		"mouse_position": [DisplayServer.mouse_get_position().x, DisplayServer.mouse_get_position().y],
	}


# ================= 事件构造 =================

func _make_key_event(kc: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = kc as Key
	ev.physical_keycode = kc as Key
	ev.pressed = pressed
	return ev


func _make_pad_event(idx: int, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = idx as JoyButton
	ev.pressed = pressed
	return ev


func _make_axis_event(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis as JoyAxis
	ev.axis_value = value
	return ev