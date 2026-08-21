extends RefCounted
## SceneHandler — 场景树白名单操作（dev 调试用，安全性优先：属性/方法都用白名单）

var tree: SceneTree

# 允许读写/调用的白名单
const SAFE_PROPERTIES := [
	"visible", "position", "global_position", "rotation", "rotation_degrees",
	"scale", "modulate", "z_index", "disabled", "text",
]
const ALLOWED_METHODS := [
	"hide", "show", "grab_focus", "release_focus", "queue_redraw", "reset_size",
]


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "scene.get_node",
			"description": "按路径读取节点快照（类型/可见/位置/子节点数等白名单属性）",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "节点路径，如 /root/Main/..."},
				},
				"required": ["path"],
			},
			"callable": _get_node,
		},
		{
			"name": "scene.set_property",
			"description": "设置节点白名单属性（visible/position/rotation/scale/modulate/z_index/disabled/text）",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"property": {"type": "string"},
					"value": {"description": "position/scale 传 [x,y]，modulate 传 [r,g,b,a]，其余标量"},
				},
				"required": ["path", "property", "value"],
			},
			"callable": _set_property,
		},
		{
			"name": "scene.call_method",
			"description": "调用节点白名单方法（hide/show/grab_focus/release_focus/queue_redraw/reset_size）",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"method": {"type": "string"},
					"args": {"type": "array", "items": {}},
				},
				"required": ["path", "method"],
			},
			"callable": _call_method,
		},
	]


func _get_node(params: Dictionary) -> Variant:
	var path_str: String = str(params.get("path", ""))
	if path_str.is_empty():
		return {"error": "缺少 path"}
	var n: Node = _resolve(path_str)
	if n == null:
		return {"error": "节点不存在: %s" % path_str}
	var e: Dictionary = {
		"name": str(n.name),
		"type": n.get_class(),
		"path": str(n.get_path()),
		"child_count": n.get_child_count(),
	}
	var pos: Variant = _prop(n, "global_position")
	if pos is Vector2:
		e["position"] = [pos.x, pos.y]
	e["visible"] = _prop(n, "visible")
	return e


func _set_property(params: Dictionary) -> Variant:
	var path_str: String = str(params.get("path", ""))
	var prop: String = str(params.get("property", ""))
	if path_str.is_empty() or prop.is_empty():
		return {"error": "缺少 path/property"}
	if not SAFE_PROPERTIES.has(prop):
		return {"error": "属性不在白名单: %s（可用: %s）" % [prop, ", ".join(SAFE_PROPERTIES)]}
	var n: Node = _resolve(path_str)
	if n == null:
		return {"error": "节点不存在: %s" % path_str}
	var value = _convert_value(prop, params.get("value"))
	if value == null and params.get("value") != null:
		return {"error": "值转换失败"}
	n.set(prop, value)
	return {"ok": true, "path": str(n.get_path()), "property": prop, "value": value}


func _call_method(params: Dictionary) -> Variant:
	var path_str: String = str(params.get("path", ""))
	var method: String = str(params.get("method", ""))
	if path_str.is_empty() or method.is_empty():
		return {"error": "缺少 path/method"}
	if not ALLOWED_METHODS.has(method):
		return {"error": "方法不在白名单: %s（可用: %s）" % [method, ", ".join(ALLOWED_METHODS)]}
	var n: Node = _resolve(path_str)
	if n == null:
		return {"error": "节点不存在: %s" % path_str}
	var args: Array = params.get("args", [])
	var result: Variant = n.callv(method, args)
	return {"ok": true, "result": result}


func _convert_value(prop: String, value: Variant) -> Variant:
	if value is Array:
		var arr: Array = value
		if prop in ["position", "global_position", "scale"] and arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
		if prop == "modulate" and arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	if prop == "disabled" or prop == "visible":
		return bool(value)
	return value


func _resolve(path_str: String) -> Node:
	var n: Node = tree.root.get_node_or_null(NodePath(path_str))
	if n == null:
		n = tree.root.get_node_or_null(NodePath("/root" + (path_str if path_str.begins_with("/") else "/" + path_str)))
	return n


func _prop(n: Node, name: String) -> Variant:
	if "prop" == "":
		return null
	for p in n.get_property_list():
		if str(p.get("name")) == name:
			return n.get(name)
	return null