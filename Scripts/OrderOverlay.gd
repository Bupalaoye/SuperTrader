class_name OrderOverlay
extends Control

# --- 外部依赖 ---
var _chart: KLineChart 
var _active_orders: Array[OrderData] = []
var _history_orders: Array[OrderData] = [] # [新增] 历史订单列表
var _font: Font

func _ready():
	_font = ThemeDB.get_fallback_font()
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE 
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(chart_node: KLineChart):
	_chart = chart_node

# [修改] 接口现在接收两个数组
func update_orders(active: Array[OrderData], history: Array[OrderData]):
	_active_orders = active
	_history_orders = history
	# print("UI调试: Overlay 重绘 | 活跃: %d | 历史: %d" % [_active_orders.size(), _history_orders.size()])
	queue_redraw()

func _draw():
	if not _chart: return
	
	var rect_size = _chart.get_rect().size # 使用图表真实尺寸
	if rect_size.x <= 0: return

	# --- 1. 绘制历史订单 (连线 + 箭头) ---
	for order in _history_orders:
		_draw_history_arrow(order)

	# --- 2. 绘制活跃订单 (水平线) ---
	for order in _active_orders:
		if order.state != OrderData.State.OPEN: continue
		
		var y = _chart.map_price_to_y_public(order.open_price)
		
		# 开仓线 (绿)
		_draw_price_line(y, rect_size.x, Color(0, 0.8, 0, 1.0), "Buy" if order.type == 0 else "Sell", order.ticket_id)
		
		# 止损 (红)
		if order.stop_loss > 0:
			var sl_y = _chart.map_price_to_y_public(order.stop_loss)
			_draw_price_line(sl_y, rect_size.x, Color(0.9, 0.2, 0.2, 1.0), "sl")
			
		# 止盈 (蓝)
		if order.take_profit > 0:
			var tp_y = _chart.map_price_to_y_public(order.take_profit)
			_draw_price_line(tp_y, rect_size.x, Color(0.2, 0.4, 1.0, 1.0), "tp")

# [新增] 绘制历史箭头逻辑
func _draw_history_arrow(order: OrderData):
	# 1. 获取坐标
	var x1 = _chart.get_x_by_time(order.open_time)
	var x2 = _chart.get_x_by_time(order.close_time)
	
	# 如果时间找不到(可能数据还没加载到那，或者数据不匹配)，就不画
	if x1 == -1 or x2 == -1: return
	
	# 简单视锥剔除：如果两个点都在屏幕外太远，就不画
	var screen_w = _chart.size.x
	if (x1 < -50 and x2 < -50) or (x1 > screen_w + 50 and x2 > screen_w + 50):
		return
		
	var y1 = _chart.map_price_to_y_public(order.open_price)
	var y2 = _chart.map_price_to_y_public(order.close_price)
	
	var start = Vector2(x1, y1)
	var end = Vector2(x2, y2)
	
	# 2. 颜色设定 (盈利金/蓝，亏损红，或者按照 MT4 风格 Buy蓝 Sell红)
	# MT4 风格：
	# Buy 单：蓝色箭头，虚线连接
	# Sell 单：红色箭头，虚线连接
	var color = Color.DODGER_BLUE if order.type == OrderData.Type.BUY else Color.ORANGE_RED
	
	# 3. 画连线 (虚线)
	draw_dashed_line(start, end, color, 1.5, 4.0)
	
	# 4. 画箭头
	# 箭头方向：如果是 Buy，箭头向上指？
	# 其实 MT4 的逻辑是：箭头画在平仓点。
	# Buy单平仓是卖出，通常画一个向下的三角或者就是 connecting line 的终点。
	# 我们这里画一个标准的三角形箭头指向 End 点
	
	var dir = (end - start).normalized()
	# 如果距离太近，dir 可能会异常，处理一下
	if start.distance_to(end) < 1.0:
		dir = Vector2.RIGHT
		
	var arrow_size = 8.0
	# 逆推箭头尾部两个点
	# 旋转 150 度和 -150 度
	var p_arrow_1 = end + dir.rotated(deg_to_rad(150)) * arrow_size
	var p_arrow_2 = end + dir.rotated(deg_to_rad(-150)) * arrow_size
	
	# 画实心三角形
	var colors = PackedColorArray([color, color, color])
	draw_polygon(PackedVector2Array([end, p_arrow_1, p_arrow_2]), colors)
	
	# (可选) 在开仓点也画个小圆点
	draw_circle(start, 3.0, color)


# 通用画线函数 (保持上一步的修复)
func _draw_price_line(y: float, width: float, color: Color, label_text: String, ticket: int = -1):
	if y < -50 or y > get_parent().size.y + 50: return
	
	var start_pos = Vector2(0, y)
	var end_pos = Vector2(width, y)
	
	# 实线打底
	draw_line(start_pos, end_pos, color * 0.3, 2.0)
	# 虚线在上
	draw_dashed_line(start_pos, end_pos, color, 1.0, 6.0)
	
	var display_text = label_text.to_upper()
	if ticket != -1: display_text += " #%d" % ticket
	
	var text_size = _font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_rect = Rect2(2, y - text_size.y, text_size.x + 10, text_size.y)
	draw_rect(label_rect, color, true)
	draw_string(_font, Vector2(5, y - 2), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)