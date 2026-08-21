extends RefCounted
## UiHandler — 扫描代码构建的 UI（Control 树）并合成点击
## ui.list:   {filter?(文本包含), max?}  → 全部 Control 的 类型/文本/可见性/矩形
## ui.click:  {path? 或 text?, button?}  → 定位 Control 并合成 移动+按下+释放

var tree: SceneTree


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "ui.list",
			"description": "扫描场景所有 Control（Label/Button/…）：类型/文本/可见性/全局矩形，支持按文本过滤",
			"input_schema": {
				"type": "object",
				"properties": {
					"filter": {"type": "string", "description": "文本包含过滤（可选）"},
					"max": {"type": "integer", "description": "最大返回数，默认 100"},
					"include_hidden": {"type": "boolean", "description": "是否包含不可见节点，默认 false"},
				},
			},
			"callable": _list,
		},
		{
			"name": "ui.click",
			"description": "定位 Control（按 path 或首次匹配 text）并合成鼠标点击（移动→按下→释放）",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "节点路径，如 /root/Main/...，与 text 二选一"},
					"text": {"type": "string", "description": "按控件文本查找（优先 path）"},
					"button": {"type": "integer", "description": "鼠标键 1=左 2=右，默认 1"},
				},
			},
			"callable": _click,
		},
	]


func _list(params: Dictionary) -> Variant:
	var filter_text: String = str(params.get("filter", ""))
	var max_count: int = int(params.get("max", 100))
	var include_hidden: bool = bool(params.get("include_hidden", false))
	var out: Array = []
	_walk_controls(tree.root, filter_text, max_count, include_hidden, out)
	return {"count": out.size(), "controls": out}


func _walk_controls(node: Node, filter_text: String, max_count: int, include_hidden: bool, out: Array) -> void:
	if out.size() >= max_count:
		return
	for c in node.get_children():
		if c is Control:
			var ctrl := c as Control
			if include_hidden or ctrl.is_visible_in_tree():
				var e: Dictionary = _snapshot(ctrl)
				if filter_text.is_empty() or str(e.get("text", "")).contains(filter_text):
					out.append(e)
		_walk_controls(c, filter_text, max_count, include_hidden, out)


func _snapshot(c: Control) -> Dictionary:
	var e: Dictionary = {
		"type": c.get_class(),
		"name": str(c.name),
		"path": str(c.get_path()),
		"visible": c.is_visible_in_tree(),
	}
	var r: Rect2 = c.get_global_rect()
	e["rect"] = [r.position.x, r.position.y, r.size.x, r.size.y]
	if "text" in c:
		var tv: Variant = c.get("text")
		if tv is String:
			e["text"] = tv
	if c is BaseButton:
		e["disabled"] = (c as BaseButton).disabled
	if c is LineEdit:
		e["text"] = (c as LineEdit).text
	return e


func _click(params: Dictionary) -> Variant:
	var target: Control = null
	var path_str: String = str(params.get("path", ""))
	if not path_str.is_empty():
		target = _resolve(path_str)
		if target == null:
			return {"error": "未找到控件: %s" % path_str}
	else:
		var text: String = str(params.get("text", ""))
		if text.is_empty():
			return {"error": "需要 path 或 text 参数"}
		target = _find_by_text(text)
		if target == null:
			return {"error": "未找到文本含 '%s' 的控件" % text}
	if not target.is_visible_in_tree():
		return {"error": "控件不可见: %s" % str(target.get_path())}
	var button: int = int(params.get("button", 1))
	var center: Vector2 = target.get_global_rect().get_center()
	_click_at(center, button)
	var result: Dictionary = {"ok": true, "clicked": str(target.get_path()), "type": target.get_class()}
	if target is BaseButton:
		result["base_button"] = true
		result["disabled"] = (target as BaseButton).disabled
	return result


func _resolve(path_str: String) -> Control:
	var n: Node = tree.root.get_node_or_null(NodePath(path_str))
	if n == null:
		# 允许省略 /root 前缀
		n = tree.root.get_node_or_null(NodePath("/root" + (path_str if path_str.begins_with("/") else "/" + path_str)))
	if n is Control:
		return n as Control
	return null


func _find_by_text(text: String) -> Control:
	var found: Array[Control] = []
	_collect_by_text(tree.root, text, found, 1)
	if found.is_empty():
		return null
	return found[0]


func _collect_by_text(node: Node, text: String, out: Array[Control], limit: int) -> void:
	if out.size() >= limit:
		return
	if node is Control:
		var c := node as Control
		if "text" in c:
			var tv: Variant = c.get("text")
			if tv is String and str(tv).contains(text):
				out.append(c)
				return
	for ch in node.get_children():
		_collect_by_text(ch, text, out, limit)


# ---------- 合成输入 ----------

func _click_at(pos: Vector2, button: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	tree.root.push_input(motion)
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