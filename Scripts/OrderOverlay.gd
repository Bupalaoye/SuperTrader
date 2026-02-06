class_name OrderOverlay
extends Control

# --- 信号 ---
# 不再直接发给后端，而是发给 Controller 去弹窗
signal request_confirm_window(order_obj: OrderData, new_sl: float, new_tp: float)

# --- 依赖 ---
var _chart: KLineChart 
var _active_orders: Array[OrderData] = []
var _history_orders: Array[OrderData] = []
var _font: Font

# --- 状态机 ---
enum State { IDLE, HOVERING, DRAGGING }
var _state: State = State.IDLE

# --- 交互数据 ---
var _hover_ticket: int = -1
var _hover_line_type: String = "" 
var _drag_start_y: float = 0.0
var _drag_current_price: float = 0.0 

const HOVER_THRESHOLD = 8.0 # 把容差稍微调大一点，更容易选中

func _ready():
	_font = ThemeDB.get_fallback_font()
	# 必须是 PASS，否则会阻断十字光标
	mouse_filter = MouseFilter.MOUSE_FILTER_PASS 
	set_anchors_preset(Control.PRESET_FULL_RECT)
	print("[DEBUG] OrderOverlay 就绪，鼠标过滤器状态: PASS")

func setup(chart_node: KLineChart):
	_chart = chart_node

func update_orders(active: Array[OrderData], history: Array[OrderData]):
	_active_orders = active
	_history_orders = history
	queue_redraw()

# --- 核心输入处理 ---
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

func _handle_mouse_move(event: InputEventMouseMotion):
	var m_pos = event.position
	
	if _state == State.DRAGGING:
		_drag_current_price = _chart.get_price_at_y(m_pos.y)
		queue_redraw()
	else:
		_check_hover(m_pos)

func _handle_mouse_down(event):
	# 只有在悬停状态下按下，才开始拖拽
	if _state == State.HOVERING and _hover_ticket != -1:
		print("[DEBUG] 开始拖拽订单 #%d | 类型: %s" % [_hover_ticket, _hover_line_type])
		_state = State.DRAGGING
		_drag_start_y = event.position.y
		_drag_current_price = _chart.get_price_at_y(event.position.y) 
		accept_event() # 关键！吞掉事件，不让 DrawingLayer 或 Chart 抢走

func _handle_mouse_up(event):
	if _state == State.DRAGGING:
		print("[DEBUG] 拖拽释放 -> 提交修改")
		_finish_dragging()
		_state = State.IDLE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		_check_hover(event.position) # 松手后立即检测是否还悬停
		queue_redraw()

# --- 悬停检测算法 ---
func _check_hover(mouse_pos: Vector2):
	var found = false
	var best_dist = HOVER_THRESHOLD
	
	# 遍历所有订单
	for order in _active_orders:
		if order.state != OrderData.State.OPEN: continue
		
		# 算出屏幕 Y 坐标
		var y_open = _chart.map_price_to_y_public(order.open_price)
		var y_sl = -9999.0
		var y_tp = -9999.0
		
		if order.stop_loss > 0: y_sl = _chart.map_price_to_y_public(order.stop_loss)
		if order.take_profit > 0: y_tp = _chart.map_price_to_y_public(order.take_profit)
		
		# 检测 SL
		if order.stop_loss > 0 and abs(mouse_pos.y - y_sl) < best_dist:
			found = true; _hover_ticket = order.ticket_id; _hover_line_type = "SL"; best_dist = abs(mouse_pos.y - y_sl)
			
		# 检测 TP
		elif order.take_profit > 0 and abs(mouse_pos.y - y_tp) < best_dist:
			found = true; _hover_ticket = order.ticket_id; _hover_line_type = "TP"; best_dist = abs(mouse_pos.y - y_tp)
			
		# 检测 开仓价 (最关键！初始没有 SL/TP 时全靠这个)
		elif abs(mouse_pos.y - y_open) < best_dist:
			found = true; _hover_ticket = order.ticket_id; _hover_line_type = "OPEN"; best_dist = abs(mouse_pos.y - y_open)
	
	if found:
		if _state != State.HOVERING:
			print("[DEBUG] 鼠标悬停到订单 #%d 线条: %s" % [_hover_ticket, _hover_line_type])
		_state = State.HOVERING
		# 设置垂直调整的光标
		mouse_default_cursor_shape = Control.CURSOR_VSIZE
	else:
		if _state == State.HOVERING:
			# print("[DEBUG] 离开悬停") # 防止刷屏，只在离开时打印
			pass
		_state = State.IDLE
		_hover_ticket = -1
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _finish_dragging():
	var order = _get_order_by_ticket(_hover_ticket)
	if not order: 
		print("[ERR] 找不到订单数据")
		return
	
	var new_p = _drag_current_price
	var open_p = order.open_price
	var old_sl = order.stop_loss
	var old_tp = order.take_profit
	
	var final_sl = old_sl
	var final_tp = old_tp
	
	# --- 智能判定逻辑 ---
	# 规则：
	# 1. Buy单：价格 > Open 为 TP，价格 < Open 为 SL
	# 2. Sell单：价格 < Open 为 TP，价格 > Open 为 SL
	# 3. 无论你拖的是原来的 SL 线还是 TP 线，只要松手，就按当前位置重新分配角色
	# 4. 如果新位置的角色(如 TP)已经有人了，覆盖它
	
	var is_buy = (order.type == OrderData.Type.BUY)
	var is_profit_zone = false
	
	if is_buy:
		is_profit_zone = (new_p > open_p)
	else:
		is_profit_zone = (new_p < open_p)
		
	if is_profit_zone:
		# 落在了盈利区 -> 这是新的 TP
		final_tp = new_p
		# 如果我原本拖的是 SL 线，现在变成了 TP，那 SL 就要清空
		# 如果我原本拖的就有 TP 线，那就覆盖旧 TP，SL 保持不变
		if _hover_line_type == "SL":
			final_sl = 0.0 # 原来的 SL 没了，因为被我拖到盈利区变成了 TP
			
	else:
		# 落在了亏损区 -> 这是新的 SL
		final_sl = new_p
		# 同理，如果我原本拖的是 TP 线，现在变成了 SL，那 TP 就要清空
		if _hover_line_type == "TP":
			final_tp = 0.0

	# 特殊情况：如果是从 OPEN 线拖出来的，只需设置新值，保留旧的另一半
	if _hover_line_type == "OPEN":
		# 如果落在盈利区，设置 TP，SL 不动
		# 如果落在亏损区，设置 SL，TP 不动
		if is_profit_zone:
			final_tp = new_p
			final_sl = old_sl # 保持原样
		else:
			final_sl = new_p
			final_tp = old_tp # 保持原样

	print("[DEBUG] 拖拽请求: Order #%d | SL: %.5f | TP: %.5f" % [order.ticket_id, final_sl, final_tp])
	
	# [修改] 不直接改，而是请求弹窗
	request_confirm_window.emit(order, final_sl, final_tp)

func _get_order_by_ticket(ticket: int) -> OrderData:
	for o in _active_orders: if o.ticket_id == ticket: return o
	return null

# --- 绘图 --- (保持之前优化过的绘图逻辑)
func _draw():
	if not _chart: return
	var rect_size = _chart.get_rect().size
	
	# 绘制历史
	for o in _history_orders: _draw_history_arrow(o)
	# 绘制活跃
	for o in _active_orders: _draw_active_order_lines(o, rect_size.x)
	
	# 绘制拖拽时的虚线 (智能变色)
	if _state == State.DRAGGING:
		var order = _get_order_by_ticket(_hover_ticket)
		if order:
			var y = _chart.map_price_to_y_public(_drag_current_price)
			
			# 智能计算颜色：如果在这个位置松手，是赚钱(TP)还是亏钱(SL)？
			# Buy: Above=TP(Blue/Green), Below=SL(Red)
			# Sell: Above=SL(Red), Below=TP(Blue/Green)
			var is_profit = false
			if order.type == OrderData.Type.BUY:
				is_profit = _drag_current_price > order.open_price
			else:
				is_profit = _drag_current_price < order.open_price
			
			var color = Color.DODGER_BLUE if is_profit else Color.ORANGE_RED
			var type_str = "TP" if is_profit else "SL"
			
			# 画线
			draw_dashed_line(Vector2(0, y), Vector2(rect_size.x, y), color, 1.5, 4.0)
			
			# 显示金额预估
			var profit = _calc_projected_profit(order, _drag_current_price)
			var info = "%s: %.5f ($%.2f)" % [type_str, _drag_current_price, profit]
			
			var text_pos = get_local_mouse_position() + Vector2(25, -10)
			draw_string(_font, text_pos, info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _draw_active_order_lines(order: OrderData, width: float):
	var y_open = _chart.map_price_to_y_public(order.open_price)
	_draw_price_line(y_open, width, Color(0, 0.8, 0), "Buy" if order.type == 0 else "Sell", order.ticket_id)
	if order.stop_loss > 0:
		_draw_price_line(_chart.map_price_to_y_public(order.stop_loss), width, Color(0.8, 0.2, 0.2), "sl")
	if order.take_profit > 0:
		_draw_price_line(_chart.map_price_to_y_public(order.take_profit), width, Color(0.2, 0.4, 0.8), "tp")

func _draw_price_line(y: float, width: float, color: Color, label: String, ticket: int = -1):
	if y < -50 or y > get_rect().size.y + 50: return
	draw_line(Vector2(0, y), Vector2(width, y), color * 0.4, 1.0)
	draw_dashed_line(Vector2(0, y), Vector2(width, y), color, 1.0, 6.0)
	var txt = label.to_upper()
	if ticket != -1: txt += " #%d" % ticket
	var sz = _font.get_string_size(txt)
	draw_rect(Rect2(0, y - sz.y, sz.x + 5, sz.y), color)
	draw_string(_font, Vector2(2, y - 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_history_arrow(order: OrderData):
	var x1 = _chart.get_x_by_time(order.open_time)
	var x2 = _chart.get_x_by_time(order.close_time)
	
	if x1 == -1 or x2 == -1: return
	
	var screen_w = _chart.size.x
	if (x1 < -50 and x2 < -50) or (x1 > screen_w + 50 and x2 > screen_w + 50):
		return
		
	var y1 = _chart.map_price_to_y_public(order.open_price)
	var y2 = _chart.map_price_to_y_public(order.close_price)
	
	var start = Vector2(x1, y1)
	var end = Vector2(x2, y2)
	
	var color = Color.DODGER_BLUE if order.type == OrderData.Type.BUY else Color.ORANGE_RED
	
	draw_dashed_line(start, end, color, 1.5, 4.0)
	
	var dir = (end - start).normalized()
	if start.distance_to(end) < 1.0:
		dir = Vector2.RIGHT
		
	var arrow_size = 8.0
	var p_arrow_1 = end + dir.rotated(deg_to_rad(150)) * arrow_size
	var p_arrow_2 = end + dir.rotated(deg_to_rad(-150)) * arrow_size
	
	var colors = PackedColorArray([color, color, color])
	draw_polygon(PackedVector2Array([end, p_arrow_1, p_arrow_2]), colors)
	
	draw_circle(start, 3.0, color)

func _calc_projected_profit(order: OrderData, target_price: float) -> float:
	var contract = 100000.0 
	var diff = target_price - order.open_price if order.type == OrderData.Type.BUY else order.open_price - target_price
	return diff * order.lots * contract