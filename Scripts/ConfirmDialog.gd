class_name ModifyConfirmDialog
extends ConfirmationDialog

# --- 信号 ---
signal confirmed_modification(ticket: int, sl: float, tp: float)

# --- UI 节点引用 ---
var _lbl_info: Label
var _data: Dictionary = {}

func _init():
	title = "Modify Order Confirmation"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	size = Vector2(400, 250)
	dialog_hide_on_ok = true
	
	# 构建内部 UI
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	_lbl_info = Label.new()
	_lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_info.custom_minimum_size = Vector2(380, 200)
	_lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_info)
	
	confirmed.connect(_on_confirmed)

# --- 设置并显示 ---
func popup_order(order: OrderData, new_sl: float, new_tp: float, contract_size: float):
	_data = {
		"ticket": order.ticket_id,
		"sl": new_sl,
		"tp": new_tp
	}
	
	# 计算预计盈亏 (用于展示给用户看)
	var sl_profit = 0.0
	var tp_profit = 0.0
	
	if new_sl > 0:
		sl_profit = _calc_profit(order, new_sl, contract_size)
	if new_tp > 0:
		tp_profit = _calc_profit(order, new_tp, contract_size)
	
	# 构建富文本提示
	var type_str = "BUY" if order.type == OrderData.Type.BUY else "SELL"
	var text = "Modify Order #%d (%s %.2f lots)\n\n" % [order.ticket_id, type_str, order.lots]
	
	text += "Open Price: %.5f\n" % order.open_price
	text += "================================\n\n"
	
	if new_sl > 0:
		text += "🔴 STOP LOSS: %.5f\n" % new_sl
		text += "   Expected Loss: $%.2f\n\n" % sl_profit
	else:
		text += "🔴 STOP LOSS: [CANCELLED]\n\n"
		
	if new_tp > 0:
		text += "🟢 TAKE PROFIT: %.5f\n" % new_tp
		text += "   Expected Profit: $%.2f\n" % tp_profit
	else:
		text += "🟢 TAKE PROFIT: [CANCELLED]\n"
		
	_lbl_info.text = text
	
	# 弹窗
	popup_centered()

func _on_confirmed():
	# 用户点了 OK，发射信号回传数据
	confirmed_modification.emit(_data.ticket, _data.sl, _data.tp)

# 简单的利润预估公式
func _calc_profit(order: OrderData, target_price: float, contract_size: float) -> float:
	var diff = 0.0
	if order.type == OrderData.Type.BUY:
		diff = target_price - order.open_price
	else:
		diff = order.open_price - target_price
	return diff * order.lots * contract_size
