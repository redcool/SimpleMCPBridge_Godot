extends RefCounted
## 工具注册表：汇总各 Handler 的工具列表，按名分派调用
## Handler 接口：_init(tree, registry) + tools() -> Array[Dictionary]
##   工具条目: {"name","description","input_schema","callable"}
##   约定：handler 出错时返回 {"error": "..."} 单键字典，MCPBridge 会转成 JSON-RPC error
## 类别：按工具名前缀推断（"." 前），支持 tools.enable/disable 动态裁剪注册面

const CoreHandler := preload("res://addons/simple_mcp_bridge/Handlers/CoreHandler.gd")
const GameHandler := preload("res://addons/simple_mcp_bridge/Handlers/GameHandler.gd")
const InputHandler := preload("res://addons/simple_mcp_bridge/Handlers/InputHandler.gd")
const DataHandler := preload("res://addons/simple_mcp_bridge/Handlers/DataHandler.gd")
const CameraHandler := preload("res://addons/simple_mcp_bridge/Handlers/CameraHandler.gd")
const UiHandler := preload("res://addons/simple_mcp_bridge/Handlers/UiHandler.gd")
const SceneHandler := preload("res://addons/simple_mcp_bridge/Handlers/SceneHandler.gd")
const ToolsHandler := preload("res://addons/simple_mcp_bridge/Handlers/ToolsHandler.gd")

var _tools: Array = []          # [{name, description, inputSchema, category, enabled}]
var _routers: Dictionary = {}   # name -> Callable
var _handlers: Array = []       # 保活：Handler 是 RefCounted，不持有会被释放
var _tree: SceneTree = null
var _enabled: Array = []        # 空数组 = 全部启用；非空 = 只启用这些类别


func setup(tree: SceneTree) -> void:
	_tree = tree
	_register(CoreHandler.new(tree, self))
	_register(GameHandler.new(tree, self))
	_register(InputHandler.new(tree, self))
	_register(DataHandler.new(tree, self))
	_register(CameraHandler.new(tree, self))
	_register(UiHandler.new(tree, self))
	_register(SceneHandler.new(tree, self))
	_register(ToolsHandler.new(tree, self))


func _register(handler: Object) -> void:
	_handlers.append(handler)  # 关键：持有 handler，防止其被释放
	var tools: Array = handler.tools()
	for t in tools:
		if not (t is Dictionary):
			continue
		var td: Dictionary = t as Dictionary
		if not td.has("name") or not td.has("callable"):
			continue
		var name: String = str(td.get("name"))
		_routers[name] = td.get("callable")
		_tools.append({
			"name": name,
			"description": str(td.get("description", "")),
			"inputSchema": td.get("input_schema", {"type": "object", "properties": {}}),
			"category": _category(name),
			"enabled": true,
		})


func shutdown() -> void:
	# 打破 registry ⇄ handler 循环引用（RefCounted 互相强引用会泄漏），退出时显式释放
	for h in _handlers:
		if h != null and h is Object and h.has_method("release_backref"):
			h.call("release_backref")
	_handlers.clear()
	_routers.clear()
	_tools.clear()


func _category(name: String) -> String:
	return name.get_slice(".", 0)


# ---------- 类别管理（tools.enable/disable/reset） ----------

func set_enabled_categories(cats: Array) -> void:
	_enabled = []
	for c in cats:
		_enabled.append(str(c))


func enabled_categories() -> Array:
	return _enabled


func all_categories() -> Array:
	var out: Array = []
	for t in _tools:
		var cat: String = str(t.get("category"))
		if not out.has(cat):
			out.append(cat)
	return out


func _category_enabled(cat: String) -> bool:
	if _enabled.is_empty():
		return true
	return _enabled.has(cat)


func tools_with_state() -> Variant:
	var out: Array = []
	for t in _tools:
		var cat: String = str(t.get("category"))
		out.append({
			"name": str(t.get("name")),
			"category": cat,
			"enabled": _category_enabled(cat),
		})
	var cat_counts: Dictionary = {}
	var cats: Array = all_categories()
	for c in cats:
		var n: int = 0
		for t in _tools:
			if str(t.get("category")) == c:
				n += 1
		cat_counts[c] = n
	return {"tools": out, "categories": cat_counts, "enabled_set": enabled_categories()}


# ---------- 注册 / 调用 ----------

func registration_message(bridge_id: String) -> String:
	var visible: Array = []
	for t in _tools:
		if _category_enabled(str(t.get("category"))):
			visible.append(t)
	return JSON.stringify({"type": "register_tools", "bridgeId": bridge_id, "tools": visible})


func call_tool(method: String, params: Dictionary) -> Variant:
	if not _routers.has(method):
		return {"error": "unknown tool: %s（已注册 %d 个工具）" % [method, _routers.size()]}
	# 执行路径同样受类别门控（tools.enable/disable 不只是裁剪列表）
	if not _category_enabled(_category(method)):
		return {"error": "工具类别已禁用: %s（可用 tools.enable 重新启用）" % _category(method)}
	var cb: Callable = _routers[method] as Callable
	return cb.call(params)