class_name OrderWindow
extends PanelContainer

# --- 信号 ---
# 点击 Buy/Sell 后发出，由 GameController 接收并处理
signal market_order_requested(type: OrderData.Type, lots: float, sl: float, tp: float)
# 预留信号：关闭窗口
signal window_closed

# --- UI 节点引用 ---
var _opt_type: OptionButton
var _spin_lots: SpinBox
var _spin_sl: SpinBox
var _spin_tp: SpinBox
var _lbl_ask: Label
var _lbl_bid: Label
var _btn_sell: Button
var _btn_buy: Button
var _lbl_symbol: Label

# --- 内部数据 ---
var _current_ask: float = 0.0
var _current_bid: float = 0.0

func _init():
	# 1. 基础窗口设置
	name = "OrderWindow"
	# 设置窗口样式：深色背景，带一点圆角
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.15, 0.15, 0.15) # MT4 深灰色
	style_bg.border_width_left = 2; style_bg.border_width_top = 2
	style_bg.border_width_right = 2; style_bg.border_width_bottom = 2
	style_bg.border_color = Color(0.3, 0.3, 0.3)
	style_bg.corner_radius_top_left = 6; style_bg.corner_radius_top_right = 6
	style_bg.corner_radius_bottom_left = 6; style_bg.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", style_bg)
	
	custom_minimum_size = Vector2(320, 400)
	
	# 2. 构建布局
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	# 内边距
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.add_child(main_vbox)
	add_child(margin)
	
	# --- A. 顶部标题栏 ---
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	_lbl_symbol = Label.new()
	_lbl_symbol.text = "EURUSD" # 默认占位
	_lbl_symbol.add_theme_font_size_override("font_size", 18)
	_lbl_symbol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_lbl_symbol)
	
	var btn_close = Button.new()
	btn_close.text = " X "
	btn_close.flat = true
	btn_close.pressed.connect(func(): hide(); window_closed.emit())
	header_hbox.add_child(btn_close)
	
	main_vbox.add_child(HSeparator.new())
	
	# --- B. 类型选择 (Type) ---
	var type_hbox = HBoxContainer.new()
	main_vbox.add_child(type_hbox)
	var lbl_type = Label.new()
	lbl_type.text = "Type:"
	lbl_type.custom_minimum_size.x = 80
	type_hbox.add_child(lbl_type)
	
	_opt_type = OptionButton.new()
	_opt_type.add_item("Market Execution")
	_opt_type.add_item("Pending Order (Coming Soon)")
	_opt_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_hbox.add_child(_opt_type)

	# --- C. 参数输入区 (Grid) ---
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	main_vbox.add_child(grid)
	
	# 1. Volume (手数)
	_create_row(grid, "Volume:", "_spin_lots", 1.0, 0.01, 100.0, 0.01)
	
	# 2. Stop Loss (止损) - 红色提示
	var sl_box = _create_row(grid, "Stop Loss:", "_spin_sl", 0.0, 0.0, 99999.0, 0.00001)
	sl_box.get_line_edit().add_theme_color_override("font_color", Color(1, 0.4, 0.4)) # 淡红
	
	# 3. Take Profit (止盈) - 绿色提示
	var tp_box = _create_row(grid, "Take Profit:", "_spin_tp", 0.0, 0.0, 99999.0, 0.00001)
	tp_box.get_line_edit().add_theme_color_override("font_color", Color(0.4, 1, 0.4)) # 淡绿
	
	main_vbox.add_child(HSeparator.new())
	
	# --- D. 报价显示区 ---
	# 模仿 MT4: Sell按钮(Bid)  <-- 动态图 -->  Buy按钮(Ask)
	# 这里简化为直接放两个大按钮
	
	var trade_hbox = HBoxContainer.new()
	trade_hbox.add_theme_constant_override("separation", 15)
	trade_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL # 撑满剩余高度
	main_vbox.add_child(trade_hbox)
	
	# === SELL 按钮 (红色) ===
	_btn_sell = _create_big_button(Color(0.8, 0.2, 0.2), "Sell by Market")
	_btn_sell.pressed.connect(func(): _on_market_click(OrderData.Type.SELL))
	trade_hbox.add_child(_btn_sell)
	
	# 在按钮内部找 Label 引用 (稍微有点 hack，但有效)
	_lbl_bid = _btn_sell.get_node("VBox/Price")
	
	# === BUY 按钮 (蓝色) ===
	_btn_buy = _create_big_button(Color(0.2, 0.4, 0.8), "Buy by Market")
	_btn_buy.pressed.connect(func(): _on_market_click(OrderData.Type.BUY))
	trade_hbox.add_child(_btn_buy)
	
	_lbl_ask = _btn_buy.get_node("VBox/Price")

# --- 辅助构建函数 ---

func _create_row(parent, label_text, var_name, def_val, min_v, max_v, step):
	var lbl = Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = def_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	
	# 通过 set 动态赋值给成员变量
	set(var_name, spin)
	return spin

func _create_big_button(base_color: Color, title: String) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	# 样式
	var style = StyleBoxFlat.new()
	style.bg_color = base_color
	style.corner_radius_top_left = 5; style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5; style.corner_radius_bottom_right = 5
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	
	# 内部垂直布局: [Sell by Market] \n [1.0520]
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # 让点击穿透到 Button
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vbox)
	
	var l1 = Label.new()
	l1.text = title.to_upper()
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.add_theme_color_override("font_color", Color.WHITE)
	l1.add_theme_font_size_override("font_size", 12)
	vbox.add_child(l1)
	
	var l2 = Label.new() # 价格标签
	l2.name = "Price"
	l2.text = "0.00000"
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.add_theme_color_override("font_color", Color.WHITE)
	l2.add_theme_font_size_override("font_size", 20)
	l2.add_theme_constant_override("outline_size", 2) # 字体轮廓，更清晰
	vbox.add_child(l2)
	
	return btn

# --- 公开接口 ---

# 1. 更新实时报价
func update_market_data(bid: float, ask: float):
	_current_bid = bid
	_current_ask = ask
	
	if _lbl_bid: _lbl_bid.text = "%.5f" % bid
	if _lbl_ask: _lbl_ask.text = "%.5f" % ask

# 2. 设置默认数值 (例如点击图表价格时自动填入)
func setup_values(lots: float = 0.1, sl: float = 0.0, tp: float = 0.0):
	_spin_lots.value = lots
	_spin_sl.value = sl
	_spin_tp.value = tp

# --- 内部逻辑 ---

func _on_market_click(type: OrderData.Type):
	var lots = _spin_lots.value
	var sl = _spin_sl.value
	var tp = _spin_tp.value
	
	# 这里可以加简单的校验
	if lots <= 0:
		print("Invalid Lots")
		return
	
	market_order_requested.emit(type, lots, sl, tp)
	hide() # 下单后自动隐藏
