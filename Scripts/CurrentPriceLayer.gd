class_name CurrentPriceLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _current_price: float = 0.0
var _seconds_left: int = 0
var _font: Font
var _active: bool = false 

# --- 颜色配置 ---
const LINE_COLOR = Color(0.9, 0.9, 0.9, 0.6) # 浅白色虚线
const TEXT_COLOR = Color.WHITE
const BG_COLOR_UP = Color(0.0, 0.6, 0.0, 0.9)   # 涨 Green
const BG_COLOR_DOWN = Color(0.8, 0.0, 0.0, 0.9) # 跌 Red
const BG_COLOR_NEUTRAL = Color(0.3, 0.3, 0.3, 0.9)

var _last_price: float = 0.0
var _bg_color: Color = BG_COLOR_NEUTRAL

func setup(chart: KLineChart):
	_chart = chart
	_font = ThemeDB.get_fallback_font()
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func update_info(price: float, seconds_left: int):
	# 价格变动变色逻辑
	if price > _last_price: _bg_color = BG_COLOR_UP
	elif price < _last_price: _bg_color = BG_COLOR_DOWN
    
	_last_price = _current_price
	_current_price = price
	_seconds_left = seconds_left
	_active = true
	queue_redraw()

func _draw():
	if not _active or not _chart: return
    
	var rect = get_rect()
	var y = _chart.map_price_to_y_public(_current_price)
    
	# 边界检查
	if y < -20 or y > rect.size.y + 20: return
    
	# --- 1. 获取位置 ---
	# 关键：获取最后一根K线的X坐标
	var candle_x = _chart.get_last_candle_visual_x()
	var candle_half_w = _chart.get_candle_width() / 2.0
    
	# 标签起始 X 坐标 = K线中心 + 半宽 + 间距
	var label_start_x = candle_x + candle_half_w + 5.0
    
	# --- 2. 绘制水平引导线 ---
	# 从 K线中心向左画一点，向右画到屏幕边缘
	# 这里模仿 MT4：画一条贯穿全屏的线，但在 K 线处被标签盖住
	draw_dashed_line(Vector2(0, y), Vector2(rect.size.x, y), LINE_COLOR, 1.0, 4.0)
    
	# --- 3. 准备文本 ---
	var min_str = "%02d" % (_seconds_left / 60)
	var sec_str = "%02d" % (_seconds_left % 60)
	var p_str = "%.5f" % _current_price
	var text = "%s ← %s:%s" % [p_str, min_str, sec_str]
    
	var font_size = 12
	var text_size = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad_x = 6.0
	var pad_y = 4.0
    
	# --- 4. 绘制动态标签 (Tag) ---
	var w = text_size.x + pad_x * 2
	var h = text_size.y + pad_y * 2
    
	# 顶点计算
	var tip_x = label_start_x
	var body_x = label_start_x + 6.0 # 箭头的根部
	var end_x = body_x + w
	var top_y = y - h/2.0
	var bot_y = y + h/2.0
    
	var points = PackedVector2Array([
		Vector2(tip_x, y),       # 尖尖
		Vector2(body_x, top_y),  # 左上
		Vector2(end_x, top_y),   # 右上
		Vector2(end_x, bot_y),   # 右下
		Vector2(body_x, bot_y)   # 左下
	])
    
	# 绘制背景
	draw_colored_polygon(points, _bg_color)
	# 绘制边框(可选)
	draw_polyline(points, Color.WHITE, 1.0) 
	# 闭合线
	draw_line(points[4], points[0], Color.WHITE) 
    
	# --- 5. 绘制文字 ---
	draw_string(_font, Vector2(body_x + pad_x, y + h/2.0 - pad_y - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
