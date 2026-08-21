extends RefCounted
## DataHandler — 只读访问 DataManager 数据表（面向 废土中的正义 项目）
## data.get_table: {table:"weapons"|"enemies"|"recruits"|...} 返回整表
## data.get_by_id: {table, id} 返回单条

var tree: SceneTree


func _init(t: SceneTree, _reg: RefCounted = null) -> void:
	tree = t


func tools() -> Array:
	return [
		{
			"name": "data.get_table",
			"description": "读取 DataManager 数据表（weapons/enemies/bosses/recruits/items/helmets/armors/classes/difficulty/system/stats/proficiency/routes），传入表名",
			"input_schema": {
				"type": "object",
				"properties": {"table": {"type": "string"}},
				"required": ["table"],
			},
			"callable": _get_table,
		},
		{
			"name": "data.get_by_id",
			"description": "按 id 读取数据表单条记录",
			"input_schema": {
				"type": "object",
				"properties": {
					"table": {"type": "string"},
					"id": {"type": "string"},
				},
				"required": ["table", "id"],
			},
			"callable": _get_by_id,
		},
	]


func _get_table(params: Dictionary) -> Variant:
	var dm: Node = tree.root.get_node_or_null("DataManager")
	if dm == null:
		return {"error": "DataManager autoload 未找到（本工具面向 cyber_blade_2_prj）"}
	var table_name: String = str(params.get("table", ""))
	if table_name.is_empty() or not (table_name in dm):
		return {"error": "表不存在: %s" % table_name}
	var data: Variant = dm.get(table_name)
	return JSON.parse_string(JSON.stringify(data))


func _get_by_id(params: Dictionary) -> Variant:
	var dm: Node = tree.root.get_node_or_null("DataManager")
	if dm == null:
		return {"error": "DataManager autoload 未找到（本工具面向 cyber_blade_2_prj）"}
	var table_name: String = str(params.get("table", ""))
	var row_id: String = str(params.get("id", ""))
	if table_name.is_empty() or not (table_name in dm):
		return {"error": "表不存在: %s" % table_name}
	var data: Variant = dm.get(table_name)
	if not (data is Dictionary):
		return {"error": "表 %s 不是 ID 映射表" % table_name}
	var row: Variant = (data as Dictionary).get(row_id, null)
	if row == null:
		return {"error": "id 不存在: %s" % row_id}
	return JSON.parse_string(JSON.stringify(row))