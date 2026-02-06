class_name CurrentPriceLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _current_price: float = 0.0
var _font: Font
var _active: bool = false # 是否有数据

# --- 配置 ---
const LINE_COLOR = Color(0.9, 0.9, 0.9, 0.9) # 亮白/浅灰
const LABEL_BG_COLOR = Color(0.3, 0.3, 0.3, 1.0) # 标签背景色
const TEXT_COLOR = Color.WHITE

func setup(chart: KLineChart):
	_chart = chart
	_font = ThemeDB.get_fallback_font()
	# 同样忽略鼠标，不阻挡交互
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# 外部调用的更新接口
func update_price(price: float):
	_current_price = price
	_active = true
	queue_redraw()

func _draw():
	if not _active or not _chart: return
	
	var rect = get_rect()
	var y = _chart.map_price_to_y_public(_current_price)
	
	# 如果价格超出了屏幕范围太远，就不画，或者是画在边缘提示（仿MT4逻辑，这里先简单通过隐藏处理）
	if y < -20 or y > rect.size.y + 20:
		return
		
	# 1. 绘制贯穿全屏的水平线
	draw_line(Vector2(0, y), Vector2(rect.size.x, y), LINE_COLOR, 1.0)
	
	# 2. 绘制右侧价格标签
	var price_text = "%.5f" % _current_price
	var font_size = 12
	var text_size = _font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	var padding = 4.0
	var label_w = text_size.x + padding * 2
	var label_h = text_size.y + padding * 2
	
	# 标签位置：靠右，Y居中
	var label_x = rect.size.x - label_w
	var label_y = y - label_h / 2.0
	
	var label_rect = Rect2(label_x, label_y, label_w, label_h)
	
	# 画背景 (圆角看起来高级点，MT4是直角，这里用直角)
	draw_rect(label_rect, LABEL_BG_COLOR, true)
	# 画文字
	draw_string(_font, Vector2(label_x + padding, label_y + label_h - padding), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
