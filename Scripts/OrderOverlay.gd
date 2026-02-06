class_name OrderOverlay
extends Control

# --- 信号定义 ---
# 请求修改订单：(Ticket ID, 新SL, 新TP)
signal request_modify_order(ticket: int, sl: float, tp: float)

# --- 外部依赖 ---
var _chart: KLineChart 
var _active_orders: Array[OrderData] = []
var _history_orders: Array[OrderData] = []
var _font: Font

# --- 交互状态机 ---
enum State { IDLE, HOVERING, DRAGGING }
var _state: State = State.IDLE

# --- 交互数据 ---
var _hover_ticket: int = -1       # 当前鼠标悬停的订单号
var _hover_line_type: String = "" # 悬停的线类型: "OPEN", "SL", "TP"
var _drag_start_y: float = 0.0
var _drag_current_price: float = 0.0 # 拖拽时的预览价格

# 配置参数
const HOVER_THRESHOLD = 6.0 # 鼠标吸附像素距离

func _ready():
	_font = ThemeDB.get_fallback_font()
	# [重要] 允许鼠标事件通过，以便检测悬停和拖拽
	mouse_filter = MouseFilter.MOUSE_FILTER_PASS 
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(chart_node: KLineChart):
	_chart = chart_node

func update_orders(active: Array[OrderData], history: Array[OrderData]):
	_active_orders = active
	_history_orders = history
	queue_redraw()

# --- 输入事件处理 (核心逻辑) ---
func _gui_input(event):
	if not _chart or _active_orders.is_empty(): return
	
	if event is InputEventMouseMotion:
		_handle_mouse_move(event)
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_mouse_down(event)
			else:
				_handle_mouse_up(event)

# --- 状态逻辑 ---

func _handle_mouse_move(event: InputEventMouseMotion):
	var m_pos = event.position
	
	if _state == State.DRAGGING:
		# 1. 拖拽中：计算新价格并重绘
		_drag_current_price = _chart.get_price_at_y(m_pos.y)
		queue_redraw()
		
	else:
		# 2. 空闲/悬停：检测是否碰撞到了某条线
		_check_hover(m_pos)

func _handle_mouse_down(event):
	if _state == State.HOVERING and _hover_ticket != -1:
		_state = State.DRAGGING
		_drag_start_y = event.position.y
		# 初始拖拽价格设为当前鼠标位置的价格，防止突变
		_drag_current_price = _chart.get_price_at_y(event.position.y) 
		# 吞噬事件，防止拖拽时触发 K线图的平移
		accept_event()

func _handle_mouse_up(event):
	if _state == State.DRAGGING:
		_finish_dragging()
		_state = State.IDLE
		# 恢复鼠标指针
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		# 再次检查悬停，防止松手后直接没选中
		_check_hover(event.position)
		queue_redraw()

# --- 辅助逻辑 ---

func _check_hover(mouse_pos: Vector2):
	var found = false
	var best_dist = HOVER_THRESHOLD
	
	# 遍历所有活跃订单的线
	for order in _active_orders:
		if order.state != OrderData.State.OPEN: continue
		
		# 计算三条线的 Y 轴位置
		var y_open = _chart.map_price_to_y_public(order.open_price)
		var y_sl = -9999
		var y_tp = -9999
		
		if order.stop_loss > 0: y_sl = _chart.map_price_to_y_public(order.stop_loss)
		if order.take_profit > 0: y_tp = _chart.map_price_to_y_public(order.take_profit)
		
		# 检测 SL (优先级最高，因为容易重叠)
		if order.stop_loss > 0 and abs(mouse_pos.y - y_sl) < best_dist:
			found = true
			_hover_ticket = order.ticket_id
			_hover_line_type = "SL"
			best_dist = abs(mouse_pos.y - y_sl)
			
		# 检测 TP
		elif order.take_profit > 0 and abs(mouse_pos.y - y_tp) < best_dist:
			found = true
			_hover_ticket = order.ticket_id
			_hover_line_type = "TP"
			best_dist = abs(mouse_pos.y - y_tp)
			
		# 检测 开仓线 (允许从开仓线拖出 SL/TP)
		elif abs(mouse_pos.y - y_open) < best_dist:
			found = true
			_hover_ticket = order.ticket_id
			_hover_line_type = "OPEN"
			best_dist = abs(mouse_pos.y - y_open)
	
	if found:
		_state = State.HOVERING
		# 设置鼠标变手型 (或垂直调整图标)
		mouse_default_cursor_shape = Control.CURSOR_VSIZE
	else:
		_state = State.IDLE
		_hover_ticket = -1
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _finish_dragging():
	# 找到对应的订单
	var order = _get_order_by_ticket(_hover_ticket)
	if not order: return
	
	var final_sl = order.stop_loss
	var final_tp = order.take_profit
	var new_price = _drag_current_price
	
	# 下面的逻辑决定了：拖动什么线，改变什么值
	if _hover_line_type == "SL":
		final_sl = new_price
	elif _hover_line_type == "TP":
		final_tp = new_price
	elif _hover_line_type == "OPEN":
		# 如果拖动的是开仓线：根据价格是在上方还是下方，以及由于买卖方向，智能判定是 SL 还是 TP
		# 逻辑：
		# Buy:  Below -> SL, Above -> TP
		# Sell: Above -> SL, Below -> TP
		var is_buy = (order.type == OrderData.Type.BUY)
		var is_above = (new_price > order.open_price)
		
		if is_buy:
			if is_above: final_tp = new_price
			else: final_sl = new_price
		else: # Sell
			if is_above: final_sl = new_price
			else: final_tp = new_price
	
	print("UI 操作: 拖拽结束，请求修改订单 -> ", final_sl, final_tp)
	request_modify_order.emit(_hover_ticket, final_sl, final_tp)

func _get_order_by_ticket(ticket: int) -> OrderData:
	for o in _active_orders:
		if o.ticket_id == ticket: return o
	return null

# --- 绘图 ---

func _draw():
	if not _chart: return
	var rect_size = _chart.get_rect().size
	
	# 1. 绘制正常订单
	for order in _history_orders:
		_draw_history_arrow(order)
		
	for order in _active_orders:
		_draw_active_order_lines(order, rect_size.x)
	
	# 2. 绘制拖拽交互线 (Ghost Line)
	if _state == State.DRAGGING:
		var y = _chart.map_price_to_y_public(_drag_current_price)
		
		# 计算预计盈亏
		var order = _get_order_by_ticket(_hover_ticket)
		if order:
			var profit_cash = _calc_projected_profit(order, _drag_current_price)
			var profit_str = "%.2f" % profit_cash
			var label = "MODIFY %.5f | Profit: %s" % [_drag_current_price, profit_str]
			var color = Color.YELLOW
			
			if profit_cash > 0: color = Color.GREEN
			elif profit_cash < 0: color = Color.RED
			
			# 画虚线
			draw_dashed_line(Vector2(0, y), Vector2(rect_size.x, y), color, 1.5, 4.0)
			
			# 画左侧或鼠标旁边的提示框
			var text_pos = get_local_mouse_position() + Vector2(15, -15)
			draw_string(_font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
			
# 剥离出来的原绘制逻辑
func _draw_active_order_lines(order: OrderData, width: float):
	var y_open = _chart.map_price_to_y_public(order.open_price)
	_draw_price_line(y_open, width, Color(0, 0.8, 0), "Buy" if order.type == 0 else "Sell", order.ticket_id)
	
	if order.stop_loss > 0:
		var y = _chart.map_price_to_y_public(order.stop_loss)
		_draw_price_line(y, width, Color(0.8, 0.2, 0.2), "sl")
		
	if order.take_profit > 0:
		var y = _chart.map_price_to_y_public(order.take_profit)
		_draw_price_line(y, width, Color(0.2, 0.4, 0.8), "tp")

# 辅助画线
func _draw_price_line(y: float, width: float, color: Color, label: String, ticket: int = -1):
	if y < -50 or y > get_rect().size.y + 50: return
	
	draw_line(Vector2(0, y), Vector2(width, y), color * 0.4, 1.0) # 暗色底线
	draw_dashed_line(Vector2(0, y), Vector2(width, y), color, 1.0, 6.0) # 亮色虚线
	
	var txt = label.to_upper()
	if ticket != -1: txt += " #%d" % ticket
	var str_size = _font.get_string_size(txt)
	draw_rect(Rect2(0, y - str_size.y, str_size.x + 5, str_size.y), color)
	draw_string(_font, Vector2(2, y - 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

# 辅助绘制历史箭头
func _draw_history_arrow(order: OrderData):
	# 1. 获取坐标
	var x1 = _chart.get_x_by_time(order.open_time)
	var x2 = _chart.get_x_by_time(order.close_time)
	
	# 如果时间找不到，就不画
	if x1 == -1 or x2 == -1: return
	
	# 简单视锥剔除
	var screen_w = _chart.size.x
	if (x1 < -50 and x2 < -50) or (x1 > screen_w + 50 and x2 > screen_w + 50):
		return
		
	var y1 = _chart.map_price_to_y_public(order.open_price)
	var y2 = _chart.map_price_to_y_public(order.close_price)
	
	var start = Vector2(x1, y1)
	var end = Vector2(x2, y2)
	
	var color = Color.DODGER_BLUE if order.type == OrderData.Type.BUY else Color.ORANGE_RED
	
	# 画连线 (虚线)
	draw_dashed_line(start, end, color, 1.5, 4.0)
	
	var dir = (end - start).normalized()
	if start.distance_to(end) < 1.0:
		dir = Vector2.RIGHT
		
	var arrow_size = 8.0
	var p_arrow_1 = end + dir.rotated(deg_to_rad(150)) * arrow_size
	var p_arrow_2 = end + dir.rotated(deg_to_rad(-150)) * arrow_size
	
	# 画实心三角形
	var colors = PackedColorArray([color, color, color])
	draw_polygon(PackedVector2Array([end, p_arrow_1, p_arrow_2]), colors)
	
	# 在开仓点也画个小圆点
	draw_circle(start, 3.0, color)

# 预计盈亏计算
func _calc_projected_profit(order: OrderData, target_price: float) -> float:
	# 合约单位，假设 AccountManager 里是 100000
	var contract = 100000.0 
	var diff = 0.0
	if order.type == OrderData.Type.BUY:
		diff = target_price - order.open_price
	else:
		diff = order.open_price - target_price
	return diff * order.lots * contract