class_name OrderOverlay
extends Control

# --- 外部依赖 ---
# 需要引用父节点 KLineChart 来获取价格对应的 Y 轴坐标
var _chart: KLineChart 
var _orders: Array[OrderData] = []
var _font: Font

func _ready():
	_font = ThemeDB.get_fallback_font()
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE # 点击穿透
	set_anchors_preset(Control.PRESET_FULL_RECT) # 铺满全屏

func setup(chart_node: KLineChart):
	_chart = chart_node

# 更新数据并重绘
func update_orders(orders: Array[OrderData]):
	_orders = orders
	queue_redraw()

func _draw():
	if not _chart or _orders.is_empty():
		return
		
	var rect = get_rect()
	var right_edge = rect.size.x
	var font_size = 12
	
	for order in _orders:
		# 只绘制 OPEN 状态的单子
		if order.state != OrderData.State.OPEN:
			continue
			
		# 1. 绘制开仓线 (Open Price) - 绿色
		_draw_price_line(order.open_price, Color(0, 0.8, 0, 0.8), "Buy" if order.type == 0 else "Sell", order.ticket_id)
		
		# 2. 绘制止损线 (SL) - 红色
		if order.stop_loss > 0:
			_draw_price_line(order.stop_loss, Color(0.9, 0.2, 0.2, 0.8), "sl")
			
		# 3. 绘制止盈线 (TP) - 蓝色
		if order.take_profit > 0:
			_draw_price_line(order.take_profit, Color(0.2, 0.4, 1.0, 0.8), "tp")

# 通用画线函数
func _draw_price_line(price: float, color: Color, label_text: String, ticket: int = -1):
	var y = _chart.map_price_to_y_public(price) # 调用 Chart 的公开转换方法
	
	# 如果 Y 坐标超出屏幕范围太远，就不画了，节省性能
	# (预留 50px 缓冲，避免文字被截断)
	if y < -50 or y > size.y + 50:
		return
	
	var start_x = 0.0
	var end_x = size.x
	
	# 绘制虚线 (Godot 4 提供了 draw_dashed_line)
	# 参数: 起点, 终点, 颜色, 宽度, 虚线步长, 是否抗锯齿
	draw_dashed_line(Vector2(start_x, y), Vector2(end_x, y), color, 1.0, 10.0)
	
	# 绘制最左侧的文字标签 (Ticket #Buy 1.0)
	var display_text = label_text.to_upper()
	if ticket != -1:
		display_text += " #%d" % ticket
	
	# 画个小背景块让文字看清楚
	var text_size = _font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_bg_rect = Rect2(2, y - text_size.y, text_size.x + 4, text_size.y)
	draw_rect(label_bg_rect, color, true)
	
	# 画文字 (白色)
	draw_string(_font, Vector2(4, y - 2), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	
	# 右侧画价格
	var price_str = "%.5f" % price
	var price_size = _font.get_string_size(price_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_rect(Rect2(size.x - price_size.x - 4, y - price_size.y, price_size.x + 4, price_size.y), color, true)
	draw_string(_font, Vector2(size.x - price_size.x - 2, y - 2), price_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)