extends RefCounted
## CoreHandler — 引擎/场景基础信息：get_status / get_hierarchy / get_objects

var tree: SceneTree


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "core.get_status",
			"description": "获取引擎与运行状态：Godot 版本、是否编辑器、当前场景、FPS、节点数",
			"input_schema": {"type": "object", "properties": {}},
			"callable": _get_status,
		},
		{
			"name": "core.get_hierarchy",
			"description": "导出场景树（含 group，节点数上限 200，防爆栈）",
			"input_schema": {
				"type": "object",
				"properties": {
					"max_depth": {"type": "integer", "description": "最大深度，默认 8"},
					"max_nodes": {"type": "integer", "description": "最大节点数，默认 200"},
				},
			},
			"callable": _get_hierarchy,
		},
		{
			"name": "core.get_objects",
			"description": "按名称包含/分组查找节点，返回路径列表",
			"input_schema": {
				"type": "object",
				"properties": {
					"name_contains": {"type": "string"},
					"group": {"type": "string", "description": "如 enemies / squad"},
				},
			},
			"callable": _get_objects,
		},
	]


func _get_status(params: Dictionary) -> Variant:
	var vi: Dictionary = Engine.get_version_info()
	var root := tree.root
	var scene_name := ""
	if tree.current_scene != null:
		scene_name = tree.current_scene.name
	return {
		"engine": "Godot",
		"version": str(vi.get("string", "?")),
		"is_editor": Engine.is_editor_hint(),
		"current_scene": scene_name,
		"fps": int(Engine.get_frames_per_second()),
		"node_count": root.get_child_count(),
		"bridge_id": _bridge_id_or_empty(),
	}


func _get_hierarchy(params: Dictionary) -> Variant:
	var max_depth: int = int(params.get("max_depth", 8))
	var max_nodes: int = int(params.get("max_nodes", 200))
	var out: Array = []
	_walk(tree.root, 0, max_depth, max_nodes, out)
	return {"count": out.size(), "truncated": out.size() >= max_nodes, "nodes": out}


func _walk(node: Node, depth: int, max_depth: int, max_nodes: int, out: Array) -> void:
	if out.size() >= max_nodes or depth > max_depth:
		return
	var entry: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
	}
	if not node.get_groups().is_empty():
		var gs: Array[StringName] = node.get_groups()
		var names: Array = []
		for g in gs:
			names.append(String(g))
		entry["groups"] = names
	out.append(entry)
	for c in node.get_children():
		_walk(c, depth + 1, max_depth, max_nodes, out)


func _get_objects(params: Dictionary) -> Variant:
	var name_contains: String = str(params.get("name_contains", ""))
	var group: String = str(params.get("group", ""))
	var out: Array = []
	if not group.is_empty():
		for n in tree.get_nodes_in_group(group):
			out.append(str(n.get_path()))
		return {"count": out.size(), "objects": out}
	var root := tree.root
	_collect_by_name(root, name_contains, out)
	return {"count": out.size(), "objects": out}


func _collect_by_name(node: Node, needle: String, out: Array) -> void:
	if needle.is_empty() or String(node.name).contains(needle):
		out.append(str(node.get_path()))
	for c in node.get_children():
		_collect_by_name(c, needle, out)


func _bridge_id_or_empty() -> String:
	var mb: Object = tree.root.get_node_or_null("MCPBridge")
	if mb != null:
		return str(mb.get("bridge_id"))
	return ""