extends Control
class_name CrosshairOverlay

# --- 内部状态 ---
var _mouse_pos: Vector2 = Vector2.ZERO
var _is_active: bool = false

func _ready():
	# 关键设置：忽略鼠标事件，让事件穿透到底下的 KLineChart
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE

func _draw():
	# 如果没激活，什么都不画
	if not _is_active:
		return

	var rect = get_rect()
	
	# 定义十字线颜色 (仿 MT4 灰色虚线风格，用实线代替即可，性能更好)
	var line_color = Color(0.6, 0.6, 0.6, 0.8)
	var line_width = 1.0

	# 1. 绘制垂直线 (时间轴)
	# 从顶部到底部，X坐标不变
	draw_line(Vector2(_mouse_pos.x, 0), Vector2(_mouse_pos.x, rect.size.y), line_color, line_width)

	# 2. 绘制水平线 (价格轴)
	# 从左侧到右侧，Y坐标不变
	draw_line(Vector2(0, _mouse_pos.y), Vector2(rect.size.x, _mouse_pos.y), line_color, line_width)

# --- 外部调用接口 ---

# 更新光标位置并重绘
# 注意：这里只负责接收像素坐标，不负责计算价格/时间（那是第二阶段的事）
func update_crosshair(mouse_pixel_pos: Vector2):
	_mouse_pos = mouse_pixel_pos
	queue_redraw() # 只重绘这一层，不影响 K 线

# 设置显隐状态
func set_active(active: bool):
	_is_active = active
	visible = active # 这一层平时可以直接隐藏
	queue_redraw()
