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
	if img.is_empty():
		return {"error": "视口无渲染画面（headless 不可截图，请窗口化运行）"}
	var out_path: String = str(params.get("path", ""))
	if out_path.is_empty():
		var dir := "user://mcp_screenshots"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var scene_name: String = "unknown"
		if tree.current_scene != null:
			scene_name = String(tree.current_scene.name)
		out_path = "%s/%s_%d.png" % [dir, scene_name, Time.get_unix_time_from_system()]
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