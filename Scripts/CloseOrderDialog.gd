class_name CloseOrderDialog
extends ConfirmationDialog

# --- 信号 ---
# 用户确认平仓时发出 (Order对象, 是否平仓)
signal request_close_order(order: OrderData)

# --- 内部状态 ---
var _current_order: OrderData
var _lbl_info: Label
var _btn_close: Button # 自定义一个显眼的平仓按钮

func _init():
	title = "Order"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	size = Vector2(350, 250)
	
	# MT4 风格：平仓通常是一个特别显眼的黄色长条按钮
	# 我们用自定义布局替换默认的 OK/Cancel
	get_ok_button().visible = false 
	# get_cancel_button().text = "Close Window" # 可以保留 Cancel 作为关闭
	
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	_lbl_info = Label.new()
	_lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_info.custom_minimum_size = Vector2(330, 120)
	vbox.add_child(_lbl_info)
	
	# 分隔线
	vbox.add_child(HSeparator.new())
	
	# 显眼的黄色平仓按钮
	_btn_close = Button.new()
	_btn_close.custom_minimum_size = Vector2(0, 40)
	_btn_close.add_theme_color_override("font_color", Color.BLACK)
	_btn_close.add_theme_color_override("font_hover_color", Color.BLACK)
	# 设置背景色为黄色 (MT4 经典色: #FFD700)
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color.GOLD
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	_btn_close.add_theme_stylebox_override("normal", style_normal)
	_btn_close.add_theme_stylebox_override("hover", style_normal)
	_btn_close.add_theme_stylebox_override("pressed", style_normal)
	
	_btn_close.pressed.connect(_on_close_pressed)
	vbox.add_child(_btn_close)

func popup_order(order: OrderData, current_price: float):
	_current_order = order
	
	# 构建信息文本
	var type_str = "Buy" if order.type == OrderData.Type.BUY else "Sell"
	var text = "Ticket: #%d\n" % order.ticket_id
	text += "Type: %s  Size: %.2f\n" % [type_str, order.lots]
	text += "Open Price: %.5f\n" % order.open_price
	text += "Current Price: %.5f\n" % current_price
	
	# 计算当前利润
	var profit = order.profit # 这里假设 OrderData 的 profit 已经被 Controller 实时更新了
	text += "\nProfit: $%.2f" % profit
	
	_lbl_info.text = text
	
	# 更新按钮文本
	_btn_close.text = "Close #%d %s %.2f at Market" % [order.ticket_id, type_str, order.lots]
	
	popup_centered()

func _on_close_pressed():
	if _current_order:
		request_close_order.emit(_current_order)
	hide()
