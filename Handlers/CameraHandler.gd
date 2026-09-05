extends RefCounted
## CameraHandler — 视口截图（辅助验证用；按设计理念，状态感知主路径是结构化读取而非截图）
## camera.screenshot: {path?}  path 为空时输出到 user://mcp_screenshots/<场景>_<时间戳>.png

var tree: SceneTree


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "camera.screenshot",
			"description": "截取当前视口画面存 PNG；path 为空时写入 user://mcp_screenshots/。注意：headless 模式下无渲染画面，需窗口化运行",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "输出 PNG 绝对路径（可选）"},
				},
			},
			"callable": _screenshot,
		},
	]


func _screenshot(params: Dictionary) -> Variant:
	var vp: Viewport = tree.root
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return {"error": "视口无渲染画面（headless 不可截图，请窗口化运行）"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mcp_screenshots"))
	var out_path: String = _screen_path(str(params.get("path", "")))
	if out_path.is_empty():
		return {"error": "截图路径仅允许 user://mcp_screenshots/ 目录内"}
	var err := img.save_png(out_path)
	if err != OK:
		return {"error": "保存 PNG 失败 err=%d: %s" % [err, out_path]}
	var global_path: String = ProjectSettings.globalize_path(out_path)
	var size_bytes: int = 0
	var f := FileAccess.open(out_path, FileAccess.READ)
	if f != null:
		size_bytes = f.get_length()
		f.close()
	return {
		"path": global_path,
		"width": img.get_width(),
		"height": img.get_height(),
		"bytes": size_bytes,
	}


## 规范化截图输出路径：只允许 user://mcp_screenshots/ 下（防远程写盘），并去除 .. 逃逸
func _screen_path(p: String) -> String:
	var base := "user://mcp_screenshots/"
	if p.is_empty():
		var scene_name: String = "unknown"
		if tree.current_scene != null:
			scene_name = String(tree.current_scene.name)
		return "%s/%s_%d.png" % ["user://mcp_screenshots", scene_name, Time.get_unix_time_from_system()]
	var s := p
	if s.begins_with(base):
		s = s.substr(base.length())
	elif s.begins_with("user://"):
		s = s.substr("user://".length()).trim_prefix("/")
		if s.begins_with("mcp_screenshots/"):
			s = s.substr("mcp_screenshots/".length())
	s = s.replace("\\", "/").replace("..", "")
	if s.is_empty() or s.begins_with("/") or s.contains(":"):
		return ""
	return base + s