class_name CurrentPriceLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _current_price: float = 0.0
var _seconds_left: int = 0 # 剩余秒数
var _font: Font
var _active: bool = false # 是否有数据

# --- 配置 ---
const LINE_COLOR = Color(0.5, 0.5, 0.5, 0.8) # 灰色线，避免太抢眼
const TEXT_COLOR = Color.WHITE
const LABEL_BG_COLOR_UP = Color(0.2, 0.6, 0.2, 1.0)   # 涨：绿色背景
const LABEL_BG_COLOR_DOWN = Color(0.8, 0.2, 0.2, 1.0) # 跌：红色背景
const LABEL_BG_COLOR_NEUTRAL = Color(0.3, 0.3, 0.3, 1.0) # 灰背景

# 上一次价格 (用于判断背景红绿)
var _last_price: float = 0.0
var _bg_color: Color = LABEL_BG_COLOR_NEUTRAL

func setup(chart: KLineChart):
	_chart = chart
	_font = ThemeDB.get_fallback_font()
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# 更新价格和倒计时
func update_info(price: float, seconds_left: int):
	# 简单的涨跌变色逻辑
	if price > _last_price:
		_bg_color = LABEL_BG_COLOR_UP
	elif price < _last_price:
		_bg_color = LABEL_BG_COLOR_DOWN
	# 如果相等，保持原色不变，模拟 MT4 闪烁效果
	
	_last_price = _current_price
	_current_price = price
	_seconds_left = seconds_left
	_active = true
	queue_redraw()

func _draw():
	if not _active or not _chart: return
	
	var rect = get_rect()
	var y = _chart.map_price_to_y_public(_current_price)
	
	# 范围检查
	if y < -20 or y > rect.size.y + 20: return
		
	# 1. 绘制水平线
	# MT4 风格：只画到价格标签的箭头处
	var label_width_estimate = 120.0
	draw_line(Vector2(0, y), Vector2(rect.size.x - label_width_estimate, y), LINE_COLOR, 1.0)
	
	# 2. 准备文本
	# 格式: "1.05200  <-- 00:43"
	var min_str = "%02d" % (_seconds_left / 60)
	var sec_str = "%02d" % (_seconds_left % 60)
	var price_text = "%.5f" % _current_price
	var full_text = "%s  <-- %s:%s" % [price_text, min_str, sec_str]
	
	var font_size = 12
	var text_size = _font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	var padding_x = 8.0
	var padding_y = 4.0
	var w = text_size.x + padding_x * 2
	var h = text_size.y + padding_y * 2
	
	# 3. 绘制五边形标签 (箭头指向线条)
	# 坐标计算：靠右贴边
	var right_x = rect.size.x
	var left_x = right_x - w
	var center_y = y
	var top_y = y - h / 2.0
	var bottom_y = y + h / 2.0
	var arrow_depth = 10.0 # 箭头的尖锐程度
	
	# 定义多边形顶点 (逆时针)
	# 形状：[左尖尖, 左上, 右上, 右下, 左下]
	var points = PackedVector2Array([
		Vector2(left_x - arrow_depth, center_y), # 箭头尖端
		Vector2(left_x, top_y),
		Vector2(right_x, top_y),
		Vector2(right_x, bottom_y),
		Vector2(left_x, bottom_y)
	])
	
	draw_colored_polygon(points, _bg_color)
	
	# 4. 绘制文字
	draw_string(_font, Vector2(left_x + padding_x, bottom_y - padding_y), full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
