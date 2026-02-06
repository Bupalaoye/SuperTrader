class_name DrawingObject
extends RefCounted

# --- 基础属性 ---
var color: Color = Color.WHITE
var width: float = 2.0
var selected: bool = false

# 关键点列表：每个点是 {"t": time_str, "p": price}
var points: Array[Dictionary] = []

# --- 虚函数 (子类必须实现) ---

# 绘制逻辑
func draw(control: Control, chart: KLineChart):
	pass

# 检测鼠标是否点击到了该对象
func is_hit(mouse_pos: Vector2, chart: KLineChart) -> bool:
	return false

# 获取最近的控制点索引 (用于拖拽修改)
# 返回 -1 表示没点中任何手柄
func get_handle_at(mouse_pos: Vector2, chart: KLineChart) -> int:
	return -1
