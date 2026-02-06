extends Control
class_name CrosshairOverlay

# --- 内部状态 ---
var _mouse_pos: Vector2 = Vector2.ZERO
var _data: Dictionary = {} 
var _is_active: bool = false
var _font: Font

func _ready():
	# 关键：忽略鼠标输入，让底下的 KLineChart 能收到事件
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	# 获取系统默认字体
	_font = ThemeDB.get_fallback_font()
	# 确保全屏布局
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw():
	if not _is_active:
		return

	var rect = get_rect()
	# 样式定义 (对标 MT4)
	var line_color = Color(0.5, 0.5, 0.5, 0.8)     # 十字线：灰色
	var ruler_color = Color(1.0, 1.0, 1.0, 0.9)    # 量尺线：亮白
	var label_bg_color = Color(0.1, 0.1, 0.1, 1.0) # 标签背景：深黑
	var text_color = Color.WHITE                   # 文字：白色
	var font_size = 12

	# ---------------------------------------------------------
	# 1. 绘制基础十字线 (始终存在)
	# ---------------------------------------------------------
	# 垂直线
	draw_line(Vector2(_mouse_pos.x, 0), Vector2(_mouse_pos.x, rect.size.y), line_color, 1.0)
	# 水平线
	draw_line(Vector2(0, _mouse_pos.y), Vector2(rect.size.x, _mouse_pos.y), line_color, 1.0)

	# ---------------------------------------------------------
	# 2. 绘制轴标签 (Axis Labels)
	# ---------------------------------------------------------
	
	# Y 轴价格标签 (右侧)
	if _data.has("price_str"):
		var price_text = _data["price_str"]
		var text_size = _font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var padding = 4.0
		
		# 位置计算：靠最右边
		var w = text_size.x + padding * 2
		var h = text_size.y + padding * 2
		var x = rect.size.x - w
		var y = clamp(_mouse_pos.y - h / 2, 0, rect.size.y - h) # 垂直居中且防溢出

		draw_rect(Rect2(x, y, w, h), label_bg_color, true)
		draw_string(_font, Vector2(x + padding, y + h - padding), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# X 轴时间标签 (底部)
	if _data.has("time_str") and _data["time_str"] != "":
		var time_text = _data["time_str"]
		var text_size = _font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var padding = 4.0
		
		# 位置计算：靠底部，水平居中于鼠标
		var w = text_size.x + padding * 2
		var h = text_size.y + padding * 2
		var x = clamp(_mouse_pos.x - w / 2, 0, rect.size.x - w) # 水平居中且防溢出
		var y = rect.size.y - h

		draw_rect(Rect2(x, y, w, h), label_bg_color, true)
		draw_string(_font, Vector2(x + padding, y + h - padding), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# ---------------------------------------------------------
	# 3. 绘制量尺系统 (The Ruler) - 仅在 MEASURE 模式下绘制
	# ---------------------------------------------------------
	if _data.get("is_measuring", false):
		
		# A. 获取数据
		var start_pos = _data.get("start_pos", Vector2.ZERO)
		var start_idx = _data.get("start_index", 0)
		var curr_idx = _data.get("index", 0)
		
		var start_price = _data.get("start_price", 0.0)
		var curr_price = _data.get("price", 0.0)
		
		# B. 画连接线
		draw_line(start_pos, _mouse_pos, ruler_color, 1.0)
		
		# C. 准备显示文本 "Bars, Diff, Price"
		var bar_diff = abs(curr_idx - start_idx)
		var price_diff = abs(curr_price - start_price)
		
		# 格式化文本：例如 "12 bars, 0.00500, 1.02500"
		var info_text = "%d bars, %.5f, %.5f" % [bar_diff, price_diff, curr_price]
		
		# D. 计算浮窗 UI
		var text_size = _font.get_string_size(info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var padding = 5.0
		var box_w = text_size.x + padding * 2
		var box_h = text_size.y + padding * 2
		var offset = Vector2(15, 15) # 默认显示在鼠标右下方
		
		var box_x = _mouse_pos.x + offset.x
		var box_y = _mouse_pos.y + offset.y
		
		# 智能防溢出：如果右边出屏幕了，改到左边显示
		if box_x + box_w > rect.size.x:
			box_x = _mouse_pos.x - box_w - offset.x
			
		# 如果下边出屏幕了，改到上边显示
		if box_y + box_h > rect.size.y:
			box_y = _mouse_pos.y - box_h - offset.y

		# E. 画浮窗
		var box_rect = Rect2(box_x, box_y, box_w, box_h)
		# 背景 (可以用稍微亮一点的灰，或者带边框)
		draw_rect(box_rect, Color(0.2, 0.2, 0.2, 0.9), true) 
		# 边框
		draw_rect(box_rect, Color.WHITE, false, 1.0) 
		# 文字
		draw_string(_font, Vector2(box_x + padding, box_y + box_h - padding), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

# --- 对外接口 ---

func update_crosshair(mouse_pixel_pos: Vector2, data: Dictionary):
	_mouse_pos = mouse_pixel_pos
	_data = data
	queue_redraw()

func set_active(active: bool):
	_is_active = active
	visible = active
	if not active:
		_data = {} 
	queue_redraw()
