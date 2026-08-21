extends RefCounted
## ToolsHandler — 工具类别管理（对齐 Unity 桥 tools.enable/disable）：动态裁剪注册面，省 token
## 类别按工具名前缀推断（core/game/input/data/camera/ui/scene/tools）

var tree: SceneTree
var reg: RefCounted = null


func _init(t: SceneTree, registry: RefCounted = null) -> void:
	tree = t
	reg = registry


## 退出清理：断开对 registry 的反向引用（registry.shutdown 调用），避免 RefCounted 循环泄漏
func release_backref() -> void:
	reg = null


func tools() -> Array:
	return [
		{
			"name": "tools.list",
			"description": "列出全部已注册工具及其类别与启用状态",
			"input_schema": {"type": "object", "properties": {}},
			"callable": _list,
		},
		{
			"name": "tools.enable",
			"description": "启用指定类别（传空数组 = 启用全部）；只上报启用类别的工具给服务端",
			"input_schema": {
				"type": "object",
				"properties": {
					"categories": {"type": "array", "items": {"type": "string"}},
				},
			},
			"callable": _enable,
		},
		{
			"name": "tools.disable",
			"description": "停用指定类别（传空数组 = 停用全部）",
			"input_schema": {
				"type": "object",
				"properties": {
					"categories": {"type": "array", "items": {"type": "string"}},
				},
			},
			"callable": _disable,
		},
		{
			"name": "tools.reset",
			"description": "恢复默认：全部类别启用",
			"input_schema": {"type": "object", "properties": {}},
			"callable": _reset,
		},
	]


func _list(_params: Dictionary) -> Variant:
	if reg == null:
		return {"error": "registry 未注入"}
	return reg.tools_with_state()


func _enable(params: Dictionary) -> Variant:
	if reg == null:
		return {"error": "registry 未注入"}
	var cats: Array = params.get("categories", [])
	reg.set_enabled_categories(cats)
	return {"ok": true, "enabled_categories": reg.enabled_categories()}


func _disable(params: Dictionary) -> Variant:
	if reg == null:
		return {"error": "registry 未注入"}
	var cats: Array = params.get("categories", [])
	var current: Array = reg.enabled_categories()
	if current.is_empty():
		current = reg.all_categories()
	for c in cats:
		current.erase(c)
	reg.set_enabled_categories(current)
	return {"ok": true, "enabled_categories": reg.enabled_categories()}


func _reset(_params: Dictionary) -> Variant:
	if reg == null:
		return {"error": "registry 未注入"}
	reg.set_enabled_categories([])
	return {"ok": true, "enabled_categories": []}