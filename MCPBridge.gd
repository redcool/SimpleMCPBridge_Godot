extends Node
## SimpleMCPBridge — Godot 侧 MCP 桥（对齐 H:\ai_works\SimpleMcpServer 的 wire protocol）
##
## 连接流程：
##   Server → 桥: {"type":"server_info","encryption":bool}
##   Server → 桥: {"type":"request_tools"}            （连上即发，定期重复）
##   桥 → Server: {"type":"register_tools","bridgeId":"...","tools":[{name,description,inputSchema},...]}
##   Server → 桥: {"id":"req_...","method":"<工具名>","paramsJson":"<JSON 字符串>"}
##   桥 → Server: {"id":"req_...","result":<任意值>}   或  {"id":"...","error":"消息"}
##
## 用法：作为 autoload（project.godot [autoload] MCPBridge="*res://addons/simple_mcp_bridge/MCPBridge.gd"）
## 配置：user://bridge-config.json 或 res://addons/simple_mcp_bridge/bridge-config.json
##       {"serverIp":"127.0.0.1","serverPort":45678,"encryptionKey":""}
## 骨架阶段仅支持透传（encryptionKey 为空）；加密留待下一步（对齐 server crypto.ts 的 #ENC# 格式）。

const ToolRegistryScript := preload("res://addons/simple_mcp_bridge/ToolRegistry.gd")
const CryptoHelper := preload("res://addons/simple_mcp_bridge/CryptoHelper.gd")

var registry: RefCounted = null
var bridge_id: String = ""
var peer: WebSocketPeer = null
var _reconnect_in: float = 0.0
var _cfg: Dictionary = {}
var _enc_key: String = ""  # 非空则启用 #ENC# AES-256-CBC（对齐 server crypto.ts）

const RECONNECT_DELAY := 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停期间桥仍须收发（game.pause 依赖）
	_cfg = _load_config()
	_enc_key = str(_cfg.get("encryptionKey", ""))
	bridge_id = _make_bridge_id()
	registry = ToolRegistryScript.new()
	registry.setup(get_tree())
	print("[MCPBridge] bridge=%s → ws://%s:%d 加密=%s" % [bridge_id, str(_cfg.get("serverIp", "127.0.0.1")), int(_cfg.get("serverPort", 45678)), "on" if not _enc_key.is_empty() else "off"])
	_connect()


func _exit_tree() -> void:
	# 显式清理：断开 WS + 释放 registry（打破 handler 循环引用），退出零泄漏
	if peer != null:
		peer.close()
		peer = null
	if registry != null and registry.has_method("shutdown"):
		registry.call("shutdown")
	registry = null


func _process(delta: float) -> void:
	if peer == null:
		if _reconnect_in > 0.0:
			_reconnect_in -= delta
			if _reconnect_in <= 0.0:
				_connect()
		return
	peer.poll()
	var state := peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = peer.get_packet()
			_on_message(pkt.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		peer = null
		_reconnect_in = RECONNECT_DELAY
		print("[MCPBridge] 连接断开，%ds 后重连" % int(RECONNECT_DELAY))


# ================= 消息处理 =================

func _on_message(raw: String) -> void:
	var plain: String = CryptoHelper.decrypt(raw, _enc_key) if not _enc_key.is_empty() else raw
	var parsed: Variant = JSON.parse_string(plain)
	if not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed as Dictionary
	if msg.has("type"):
		_handle_typed(msg)
	elif msg.has("id") and msg.has("method"):
		_handle_call(msg)


func _handle_typed(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"server_info":
			var enc: bool = bool(msg.get("encryption", false))
			if enc and _enc_key.is_empty():
				push_warning("[MCPBridge] 服务端要求加密但本桥 encryptionKey 为空，将无法解密服务端消息。")
			elif not enc and not _enc_key.is_empty():
				push_warning("[MCPBridge] 本桥配置了加密密钥但服务端未开启加密，将以明文通信。")
		"request_tools":
			_send(registry.registration_message(bridge_id))
		"ai_request":
			push_warning("[MCPBridge] ai_request 未实现（骨架阶段）。")
		_:
			print("[MCPBridge] 未知 type 消息: %s" % str(msg.get("type")))


func _handle_call(msg: Dictionary) -> void:
	var id: String = str(msg.get("id", ""))
	if id.is_empty():
		return
	var method: String = str(msg.get("method", ""))
	var params: Dictionary = {}
	var pj: Variant = msg.get("paramsJson", "")
	if pj is String:
		var parsed: Variant = JSON.parse_string(pj as String)
		if parsed is Dictionary:
			params = parsed as Dictionary
	var result: Variant = registry.call_tool(method, params)
	if result is Dictionary and (result as Dictionary).has("error") and (result as Dictionary).size() == 1:
		_send(JSON.stringify({"id": id, "error": str((result as Dictionary).get("error"))}))
	else:
		_send(JSON.stringify({"id": id, "result": result}))


func _send(text: String) -> void:
	if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(CryptoHelper.encrypt(text, _enc_key) if not _enc_key.is_empty() else text)


# ================= 连接 =================

func _connect() -> void:
	var host: String = str(_cfg.get("serverIp", "127.0.0.1"))
	var port: int = int(_cfg.get("serverPort", 45678))
	peer = WebSocketPeer.new()
	var err := peer.connect_to_url("ws://%s:%d" % [host, port])
	if err != OK:
		push_warning("[MCPBridge] connect_to_url 失败 err=%d" % err)
		peer = null
		_reconnect_in = RECONNECT_DELAY


# ================= 工具函数 =================

func _make_bridge_id() -> String:
	# 三段式：<engine>-<project>-<guid>；project 段 = bridge-config.json projectName 优先，
	# 否则回退引擎项目名（slug 化）；guid 段 32 hex 保证唯一
	return "%s-%s-%s" % ["godot", _project_slug(), _random_guid()]


func _project_slug() -> String:
	var override_name: String = str(_cfg.get("projectName", ""))
	var pname: String = override_name if not override_name.is_empty() else str(ProjectSettings.get_setting("application/config/name", ""))
	if pname.is_empty():
		return "unknown"
	var slug: String = _slugify(pname)
	return slug if not slug.is_empty() else "unknown"


func _slugify(s: String) -> String:
	var out := PackedStringArray()
	for i in s.length():
		var ch: String = s.substr(i, 1)
		var code: int = ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			out.append(ch)
		elif code >= 65 and code <= 90:
			out.append(ch.to_lower())
		else:
			out.append("-")
	var slug: String = "".join(out)
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	return slug.trim_prefix("-").trim_suffix("-")


func _random_guid() -> String:
	var parts := PackedStringArray()
	for i in range(4):
		parts.append("%08x" % randi())
	return "".join(parts)


func _load_config() -> Dictionary:
	var cfg: Dictionary = {"serverIp": "127.0.0.1", "serverPort": 45678, "encryptionKey": "", "projectName": ""}
	var paths: Array[String] = [
		"res://addons/simple_mcp_bridge/bridge-config.json",
		"user://bridge-config.json",
	]
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			for k in cfg.keys():
				var key: String = k as String
				if (parsed as Dictionary).has(key):
					cfg[key] = (parsed as Dictionary).get(key)
		break
	return cfg