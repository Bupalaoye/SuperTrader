class_name GridLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _font: Font
var _bg_color: Color = Color(0.1, 0.1, 0.1, 1.0) # 默认背景色

# --- 样式配置 ---
const GRID_COLOR = Color(0.2, 0.2, 0.2, 1.0) # 深灰色虚线
const TEXT_COLOR = Color(0.6, 0.6, 0.6, 1.0) # 浅灰色文字
const FONT_SIZE = 10

# [修改] setup 接收背景色
func setup(chart: KLineChart, bg_color: Color):
	_chart = chart
	_bg_color = bg_color
	_font = ThemeDB.get_fallback_font()
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw():
	if not _chart: return
	
	var rect_size = get_rect().size
	if rect_size.x <= 0 or rect_size.y <= 0: return

	# [新增] 1. 先绘制背景底色 (画在最底层)
	draw_rect(get_rect(), _bg_color)

	# 获取图表当前的视口数据
	var min_p = _chart.get_min_visible_price()
	var max_p = _chart.get_max_visible_price()
	var price_range = max_p - min_p
	
	if price_range <= 0: return

	# ------------------------------------------------------------------
	# 2. 绘制价格网格 (水平线)
	# ------------------------------------------------------------------
	
	# 智能计算步长
	var raw_step = price_range / 10.0
	# 防止 log(0) 错误
	if raw_step <= 0: raw_step = 0.0001
	
	var magnitude = pow(10, floor(log(raw_step) / log(10))) 
	var normalized = raw_step / magnitude 
	
	var step = 0.0
	if normalized < 1.5: step = 1.0 * magnitude
	elif normalized < 3.0: step = 2.0 * magnitude
	elif normalized < 7.0: step = 5.0 * magnitude
	else: step = 10.0 * magnitude
	
	# 计算起始价格
	var start_p = floor(min_p / step) * step
	
	var current_p = start_p
	# 循环画线
	# 增加安全限制，防止死循环导致卡死
	var safety_counter = 0
	while current_p <= max_p + step and safety_counter < 100:
		safety_counter += 1
		if current_p >= min_p:
			var y = _chart.map_price_to_y_public(current_p)
			
			# 扩大一点绘制范围，保证边缘也能看到线
			if y >= -20 and y <= rect_size.y + 20:
				# 画横向虚线
				draw_dashed_line(Vector2(0, y), Vector2(rect_size.x, y), GRID_COLOR, 1.0, 4.0)
				
				# 画右侧价格标签
				var p_str = _format_price(current_p)
				var text_size = _font.get_string_size(p_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
				# 靠右绘制
				draw_string(_font, Vector2(rect_size.x - text_size.x - 5, y - 2), p_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		
		current_p += step

	# ------------------------------------------------------------------
	# 3. 绘制时间网格 (垂直线)
	# ------------------------------------------------------------------
	
	var start_idx = _chart.get_first_visible_index()
	var end_idx = _chart.get_last_visible_index()
	var total_visible = end_idx - start_idx
	
	if total_visible <= 0: return
	
	# 目标：屏幕横向大约显示 5-8 条竖线
	var idx_step = int(float(total_visible) / 5.0)
	if idx_step < 1: idx_step = 1
	
	var offset = start_idx % idx_step 
	var current_idx = start_idx + (idx_step - offset)
	
	safety_counter = 0
	while current_idx <= end_idx and safety_counter < 100:
		safety_counter += 1
		var x = _chart.get_x_by_index_public(current_idx)
		
		# 画纵向虚线
		draw_dashed_line(Vector2(x, 0), Vector2(x, rect_size.y), GRID_COLOR, 1.0, 4.0)
		
		# 获取时间文字
		var time_str = _chart.get_time_by_index_public(current_idx)
		# 粗略截取时间
		if time_str.length() > 5:
			# 如果是日期+时间 "2023.01.01 12:00"
			# 简单逻辑：如果这就刚好是00:00，显示日期，否则显示时间
			if time_str.ends_with("00:00") or time_str.ends_with("00"):
				time_str = time_str.split(" ")[0] # 取日期部分
			else:
				time_str = time_str.split(" ")[-1] # 取时间部分
		
		draw_string(_font, Vector2(x + 5, rect_size.y - 5), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		
		current_idx += idx_step

# 辅助：价格格式化 (去除浮点误差)
func _format_price(price: float) -> String:
	# 这里假设外汇 5 位小数
	return "%.5f" % price
