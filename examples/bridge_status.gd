extends Node
## Standalone 演示：打印桥状态（编译冒烟用）
## 运行: Godot --headless --path . --quit-after 60

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t > 10.0:
		_t = 0.0
		var mb: Node = get_node_or_null("/root/MCPBridge")
		if mb == null:
			print("[Status] MCPBridge autoload 未加载")
		else:
			var peer: Variant = mb.get("peer")
			var state := "null"
			if peer is WebSocketPeer:
				state = str(peer.get_ready_state())
			print("[Status] bridge_id=%s ws_state=%s tools=%s" % [str(mb.get("bridge_id")), state, str(mb.get("registry")._tools.size())])