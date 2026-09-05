extends RefCounted
## GameHandler — 游戏状态读写 + 多步序列（面向 废土中的正义 项目，缺字段时优雅降级）
## 读：game.get_state / game.get_entities
## 写（dev 门槛）：game.set_materials / game.set_difficulty / game.start_run / game.pause
## 序列：game.do_sequence / game.sequence_status / game.sequence_cancel

var tree: SceneTree
var reg: RefCounted = null

var _seq_next_id: int = 0
var _sequences: Dictionary = {}   # seq_id -> {running, steps, current, done, last, error, finished_at}
const MAX_SEQUENCE_ENTRIES := 100
const SEQUENCE_TTL_SEC := 60.0


func _init(t: SceneTree, registry: RefCounted = null) -> void:
	tree = t
	reg = registry


## 退出清理：断开对 registry 的反向引用（registry.shutdown 调用），避免 RefCounted 循环泄漏
func release_backref() -> void:
	reg = null


func tools() -> Array:
	return [
		{
			"name": "game.get_state",
			"description": "获取 GameState 快照（关卡/物资/成员数/击杀/难度/试炼模式）与当前场景名",
			"input_schema": {"type": "object", "properties": {}},
			"callable": _get_state,
		},
		{
			"name": "game.get_entities",
			"description": "批量读取敌人(enemies)或队友(squad)组实体的关键状态：hp/max_hp/位置/行为等",
			"input_schema": {
				"type": "object",
				"properties": {
					"group": {"type": "string", "description": "enemies 或 squad，默认 enemies"},
					"max": {"type": "integer", "description": "最大数量，默认 40"},
				},
			},
			"callable": _get_entities,
		},
		{
			"name": "game.set_materials",
			"description": "设置物资数量（绝对赋值，dev 用）",
			"input_schema": {
				"type": "object",
				"properties": {"amount": {"type": "number"}},
				"required": ["amount"],
			},
			"callable": _set_materials,
		},
		{
			"name": "game.set_difficulty",
			"description": "设置难度（0-5）",
			"input_schema": {
				"type": "object",
				"properties": {"difficulty": {"type": "integer"}},
				"required": ["difficulty"],
			},
			"callable": _set_difficulty,
		},
		{
			"name": "game.start_run",
			"description": "开局新一局（清空小队重建初始队员）",
			"input_schema": {
				"type": "object",
				"properties": {
					"difficulty": {"type": "integer", "description": "难度 0-5，默认 0"},
					"class_id": {"type": "string", "description": "职业 shooting/melee/medic，默认 shooting"},
					"family": {"type": "string", "description": "开局武器族特长（可选）"},
				},
			},
			"callable": _start_run,
		},
		{
			"name": "game.pause",
			"description": "暂停/继续整棵树（tree.paused + 同步 Game 场景暂停 UI）",
			"input_schema": {
				"type": "object",
				"properties": {"paused": {"type": "boolean"}},
				"required": ["paused"],
			},
			"callable": _pause,
		},
		{
			"name": "game.do_sequence",
			"description": "按脚本序列依次执行若干工具调用（fire-and-forget）：steps=[{tool, params, delay(秒)}]，用 game.sequence_status 轮询",
			"input_schema": {
				"type": "object",
				"properties": {
					"steps": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"tool": {"type": "string"},
								"params": {"type": "object"},
								"delay": {"type": "number", "description": "执行前延迟秒数"},
							},
						},
					},
				},
				"required": ["steps"],
			},
			"callable": _do_sequence,
		},
		{
			"name": "game.sequence_status",
			"description": "查询序列执行状态（sequence_id 可选，缺省返回全部）",
			"input_schema": {
				"type": "object",
				"properties": {"sequence_id": {"type": "integer"}},
			},
			"callable": _sequence_status,
		},
		{
			"name": "game.sequence_cancel",
			"description": "取消指定/全部进行中的序列",
			"input_schema": {
				"type": "object",
				"properties": {"sequence_id": {"type": "integer", "description": "缺省取消全部"}},
			},
			"callable": _sequence_cancel,
		},
	]


# ================= 读 =================

func _get_state(_params: Dictionary) -> Variant:
	var scene_name := ""
	if tree.current_scene != null:
		scene_name = str(tree.current_scene.name)
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return {"error": "GameState autoload 未找到（本工具面向 废土中的正义）"}
	var out: Dictionary = {"scene": scene_name}
	for key in ["stage_index", "materials", "kills", "scenario_mode", "in_run", "difficulty_id", "wave"]:
		if key in gs:
			out[key] = gs.get(key)
	if "members" in gs:
		var members: Variant = gs.get("members")
		if members is Array:
			out["member_count"] = (members as Array).size()
	return out


func _get_entities(params: Dictionary) -> Variant:
	var group: String = str(params.get("group", "enemies"))
	var max: int = clampi(int(params.get("max", 40)), 1, 200)
	var out: Array = []
	for n in tree.get_nodes_in_group(group):
		if out.size() >= max:
			break
		if not is_instance_valid(n):
			continue
		var e: Dictionary = {
			"name": str(n.name),
			"path": str(n.get_path()),
			"hp": _propf(n, "hp"),
			"max_hp": _propf(n, "max_hp"),
			"position": _pos(n),
			"velocity": _vel(n),
		}
		var behavior: Variant = _prop(n, "behavior")
		if behavior != null:
			e["behavior"] = behavior
		var is_boss: Variant = _prop(n, "is_boss")
		if is_boss != null:
			e["is_boss"] = is_boss
		var radius: Variant = _prop(n, "radius")
		if radius != null:
			e["radius"] = radius
		var member: Variant = _prop(n, "member")
		if member != null and member is Object:
			e["member_class"] = _prop_string(member, "class_id")
			e["family_prof"] = _prop_families(member)
		out.append(e)
	return {"count": out.size(), "entities": out}


# ================= 写（dev） =================

func _set_materials(params: Dictionary) -> Variant:
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return {"error": "GameState autoload 未找到"}
	var amount: float = float(params.get("amount", 0.0))
	gs.set("materials", amount)
	if "materials_changed" in gs:
		var sig: Variant = gs.get("materials_changed")
		if sig is Signal:
			(sig as Signal).emit(amount)
	return {"ok": true, "materials": amount}


func _set_difficulty(params: Dictionary) -> Variant:
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return {"error": "GameState autoload 未找到"}
	gs.set("difficulty_id", int(params.get("difficulty", 0)))
	return {"ok": true, "difficulty": gs.get("difficulty_id")}


func _start_run(params: Dictionary) -> Variant:
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return {"error": "GameState autoload 未找到"}
	var diff: int = int(params.get("difficulty", 0))
	var cls: String = str(params.get("class_id", "shooting"))
	var family: String = str(params.get("family", ""))
	if gs.has_method("start_run"):
		gs.call("start_run", diff, cls, family)
	return {"ok": true, "in_run": gs.get("in_run"), "member_count": _member_count(gs)}


func _pause(params: Dictionary) -> Variant:
	var paused: bool = bool(params.get("paused", false))
	tree.paused = paused
	var scene: Node = tree.current_scene
	if scene != null:
		if "is_paused" in scene:
			scene.set("is_paused", paused)
		if "_pause_ui" in scene:
			var ui: Variant = scene.get("_pause_ui")
			if ui != null and ui is CanvasLayer:
				(ui as CanvasLayer).visible = paused
	return {"ok": true, "paused": tree.paused}


# ================= 序列 =================

## 清理已结束序列：TTL 过期清理 + 超上限时清最旧的已结束条目（防 _sequences 无限增长）
func _prune_sequences() -> void:
	var now: float = Time.get_unix_time_from_system()
	var finished: Array = []
	for sid in _sequences:
		if not bool((_sequences[sid] as Dictionary).get("running", false)):
			finished.append(sid)
	var over: int = _sequences.size() - MAX_SEQUENCE_ENTRIES
	if over > 0 and not finished.is_empty():
		finished.sort_custom(func(a, b):
			return float((_sequences[a] as Dictionary).get("finished_at", 0.0)) < float((_sequences[b] as Dictionary).get("finished_at", 0.0)))
		for i in range(mini(over, finished.size())):
			_sequences.erase(finished[i])
	for sid in finished:
		var st: Dictionary = _sequences[sid]
		var fa: float = float(st.get("finished_at", 0.0))
		if fa > 0.0 and now - fa > SEQUENCE_TTL_SEC:
			_sequences.erase(sid)


func _do_sequence(params: Dictionary) -> Variant:
	var steps: Array = params.get("steps", [])
	if steps.is_empty():
		return {"error": "steps 为空"}
	_prune_sequences()
	_seq_next_id += 1
	var seq_id: int = _seq_next_id
	_sequences[seq_id] = {
		"running": true,
		"steps": steps.size(),
		"current": 0,
		"done": 0,
		"last": {},
		"error": "",
	}
	_run_steps(seq_id, steps)
	return {"ok": true, "sequence_id": seq_id, "started": true, "steps": steps.size()}


func _run_steps(seq_id: int, steps: Array) -> void:
	var state: Dictionary = _sequences[seq_id]
	var index: int = 0
	for step in steps:
		if not bool(state.get("running", true)):  # cancelled
			state["running"] = false
			state["finished_at"] = Time.get_unix_time_from_system()
			state["error"] = "cancelled"
			return
		state["current"] = index
		var s: Dictionary = step if step is Dictionary else {}
		var delay: float = float(s.get("delay", 0.0))
		if delay > 0.0:
			await tree.create_timer(delay).timeout
		if not bool(state.get("running", true)):
			state["running"] = false
			state["finished_at"] = Time.get_unix_time_from_system()
			state["error"] = "cancelled"
			return
		var tool: String = str(s.get("tool", ""))
		var p: Dictionary = {}
		var pv: Variant = s.get("params", {})
		if pv is Dictionary:
			p = pv
		var result: Variant = null
		if not tool.is_empty() and reg != null:
			result = reg.call_tool(tool, p)
		state["last"] = {"index": index, "tool": tool, "result": result}
		state["done"] = index + 1
		index += 1
	state["running"] = false
	state["finished_at"] = Time.get_unix_time_from_system()


func _sequence_status(params: Dictionary) -> Variant:
	var wanted: int = int(params.get("sequence_id", -1))
	var out: Array = []
	for sid in _sequences:
		if wanted > 0 and sid != wanted:
			continue
		var st: Dictionary = _sequences[sid]
		out.append({
			"sequence_id": sid,
			"running": st.get("running"),
			"steps": st.get("steps"),
			"current": st.get("current"),
			"done": st.get("done"),
			"last": st.get("last"),
			"error": st.get("error", ""),
		})
	return {"sequences": out}


func _sequence_cancel(params: Dictionary) -> Variant:
	var wanted: int = int(params.get("sequence_id", -1))
	var cancelled: Array = []
	for sid in _sequences:
		if wanted > 0 and sid != wanted:
			continue
		var st: Dictionary = _sequences[sid]
		if bool(st.get("running", false)):
			st["running"] = false
			st["finished_at"] = Time.get_unix_time_from_system()
			st["error"] = "cancelled"
			cancelled.append(sid)
	return {"ok": true, "cancelled": cancelled}


# ================= 安全取值（不产生 noise error） =================

func _member_count(gs: Node) -> int:
	var members: Variant = gs.get("members")
	if members is Array:
		return (members as Array).size()
	return 0


func _prop(node: Object, name: String) -> Variant:
	if node == null:
		return null
	for p in node.get_property_list():
		if str(p.get("name")) == name:
			return node.get(name)
	return null


func _propf(node: Object, name: String) -> float:
	var v: Variant = _prop(node, name)
	if v == null:
		return 0.0
	return float(v)


func _prop_string(node: Object, name: String) -> String:
	var v: Variant = _prop(node, name)
	if v == null:
		return ""
	return str(v)


func _prop_families(member: Object) -> Dictionary:
	var v: Variant = _prop(member, "family_prof")
	if v is Dictionary:
		return v as Dictionary
	return {}


func _pos(n: Node) -> Array:
	if n is Node2D:
		var pos: Vector2 = (n as Node2D).global_position
		return [pos.x, pos.y]
	return []


func _vel(n: Node) -> Array:
	if n is CharacterBody2D:
		var v: Vector2 = (n as CharacterBody2D).velocity
		return [v.x, v.y]
	return []