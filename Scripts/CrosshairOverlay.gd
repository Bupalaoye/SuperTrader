extends Control
class_name CrosshairOverlay

var _mouse_pos: Vector2 = Vector2.ZERO
var _data: Dictionary = {} # 存储传过来的 {price_str, time_str}
var _is_active: bool = false
var _font: Font

func _ready():
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	# 获取系统默认字体，用来画字
	_font = ThemeDB.get_fallback_font()

func _draw():
	if not _is_active:
		return

	var rect = get_rect()
	var line_color = Color(0.5, 0.5, 0.5, 0.8) # 灰色
	var label_bg_color = Color(0.1, 0.1, 0.1, 1.0) # 深黑背景
	var text_color = Color.WHITE

	# --- 1. 画十字线 ---
	# 垂直线
	draw_line(Vector2(_mouse_pos.x, 0), Vector2(_mouse_pos.x, rect.size.y), line_color, 1.0)
	# 水平线
	draw_line(Vector2(0, _mouse_pos.y), Vector2(rect.size.x, _mouse_pos.y), line_color, 1.0)

	# --- 2. 画 Y 轴价格标签 (右侧) ---
	if _data.has("price_str"):
		var price_text = _data["price_str"]
		var text_size = _font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12) # 字体大小12
		var padding = 4.0
		
		# 标签框的位置：靠最右边
		var label_w = text_size.x + padding * 2
		var label_h = text_size.y + padding * 2
		var label_x = rect.size.x - label_w
		var label_y = _mouse_pos.y - label_h / 2
		
		# 为了不让标签跑出屏幕上下边界，限制一下
		label_y = clamp(label_y, 0, rect.size.y - label_h)

		# 画黑底
		draw_rect(Rect2(label_x, label_y, label_w, label_h), label_bg_color, true)
		# 画文字 (注意 centered vertical alignment 需要手动算 offset)
		draw_string(_font, Vector2(label_x + padding, label_y + label_h - padding), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)

	# --- 3. 画 X 轴时间标签 (底部) ---
	if _data.has("time_str") and _data["time_str"] != "":
		var time_text = _data["time_str"]
		var text_size = _font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var padding = 4.0
		
		var label_w = text_size.x + padding * 2
		var label_h = text_size.y + padding * 2
		var label_x = _mouse_pos.x - label_w / 2
		# 靠最底部
		var label_y = rect.size.y - label_h 
		
		# 限制左右不跑出去
		label_x = clamp(label_x, 0, rect.size.x - label_w)
		
		draw_rect(Rect2(label_x, label_y, label_w, label_h), label_bg_color, true)
		draw_string(_font, Vector2(label_x + padding, label_y + label_h - padding), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)

# 更新数据接口升级
func update_crosshair(mouse_pixel_pos: Vector2, data: Dictionary):
	_mouse_pos = mouse_pixel_pos
	_data = data
	queue_redraw()

func set_active(active: bool):
	_is_active = active
	visible = active
	queue_redraw()
