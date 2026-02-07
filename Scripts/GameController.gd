extends Node

# --- 节点引用 (UI 与 组件) ---
# %符号代表 Unique Name，请确保场景里已设置
@onready var chart: KLineChart = %KLineChart 
@onready var file_dialog: FileDialog = %FileDialog
@onready var playback_timer: Timer = %Timer

# 交易 UI 引用
@onready var lbl_balance: Label = %LblBalance
@onready var lbl_equity: Label = %LblEquity
@onready var btn_buy: Button = %BtnBuy
@onready var btn_sell: Button = %BtnSell
@onready var btn_close_all: Button = %BtnCloseAll
@onready var terminal: TerminalPanel = %TerminalPanel 

# 原有的回放 UI
@onready var btn_load: Button = %BtnLoad 
@onready var btn_play: Button = %BtnPlay

# 绘图工具 UI
@onready var btn_trendline: Button = %BtnTrendLine

# 指标 UI
@onready var btn_add_ma: Button = %BtnAddMA

# --- 核心子系统 ---
var account: AccountManager # 账户核心

# [Stage 4 新增] 音效播放器
var sfx_player: AudioStreamPlayer

# [NEW] 订单修改确认弹窗
var confirm_dialog: ModifyConfirmDialog

# [NEW] 平仓弹窗引用
var close_dialog: CloseOrderDialog

# [NEW] 订单窗口系统
var order_window: OrderWindow
var order_window_overlay: Control

# [Stage 5 新增] HUD 显示
var hud_display: MarketHUD

# --- 布林带配置参数 ---
var _bb_period: int = 21     # 默认周期
var _bb_k: float = 0.5       # 默认倍数 (标准差)
var _bb_config_dialog: ConfirmationDialog
var _spin_period: SpinBox
var _spin_k: SpinBox

# --- 噪声生成 (Perlin Noise) ---
var _noise: FastNoiseLite
var _noise_offset: float = 0.0 # 噪声的滚动偏移量

# --- 核心数据 ---
var full_history_data: Array = [] 
var current_playback_index: int = 0 
var is_playing: bool = false
var _cached_last_candle: Dictionary = {} # 缓存当前K线，防止空数据
var _history_ema200: Array = [] # [新增] 存储全量 EMA 数据

# 修改: 增加 tick 间隔控制
var tick_delay: float = 0.05 # 每个微 Tick 之间的间隔 (秒)

# --- 回放跳转控制 ---
var _playback_slider: HSlider
var _playback_label: Label
var _is_dragging_slider: bool = false # 标记用户是否正在拖拽
var _current_tick_generation: int = 0  # [关键] 异步任务的代数ID，用于中断旧的协程

func _ready():
	print("正在初始化控制器...")
	
	# --- 初始化音效 ---
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	# 如果你有资源，可以取消注释并加载
	# sfx_player.stream = load("res://Assets/Sounds/close.wav")
	
	# [新增] 初始化噪声生成器
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.2   # 频率越高，抖动越剧烈
	_noise.fractal_octaves = 3 
	
	# [新增] 初始化确认弹窗
	confirm_dialog = ModifyConfirmDialog.new()
	add_child(confirm_dialog)
	
	# [新增] 初始化平仓弹窗
	close_dialog = CloseOrderDialog.new()
	add_child(close_dialog)
	
	# 连接平仓确认信号 -> 执行平仓
	close_dialog.request_close_order.connect(func(order):
		# 获取当前价格 (用于记录平仓价)
		var price = 0.0
		var time_str = ""
		if not _cached_last_candle.is_empty():
			price = _cached_last_candle.c
			time_str = _cached_last_candle.t
		
		# 调用账户接口执行平仓
		account.close_market_order(order.ticket_id, price, time_str)
	)
	
	# 1. 初始化账户系统
	account = AccountManager.new()
	account.name = "AccountManager"
	add_child(account) # 挂载到树上，成为 GameController 的子节点
	
	# 2. 连接账户信号
	account.balance_updated.connect(_on_account_balance_updated)
	account.equity_updated.connect(_on_account_equity_updated)
	account.order_opened.connect(func(o): 
		print("UI通知: 开仓成功 #", o.ticket_id)
		# 传递 active 和 history
		chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
	)
	# [Stage 4 修复] 订单修改：刷新图表
	account.order_modified.connect(func(o):
		print("UI通知: 订单修改 #", o.ticket_id)
		chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
	)
	account.order_closed.connect(func(o): 
		print("UI通知: 平仓完成 #", o.ticket_id)
		# 传递 active 和 history
		chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
		# [Stage 4 新增] 平仓时播放音效
		_play_trade_sound()
	)

	# 3. 连接 UI 交互信号
	_setup_ui_signals()
	
	# [新增] 设置图表控制按钮
	_setup_chart_controls()
	
	# [修改] 连接订单层的弹窗信号，而不是直接修改订单
	var order_layer = chart.get_node("OrderOverlay")
	if order_layer:
		# 连接弹窗的确认信号 -> 账户修改
		confirm_dialog.confirmed_modification.connect(func(ticket, sl, tp):
			account.modify_order(ticket, sl, tp)
		)
		
		# 连接 OrderOverlay 的请求信号 -> 弹窗显示
		order_layer.request_confirm_window.connect(func(order_obj, new_sl, new_tp):
			# 弹出确认框
			confirm_dialog.popup_order(order_obj, new_sl, new_tp, account.contract_size)
		)
	else:
		printerr("警告: 无法在控制器中连接 OrderOverlay")
	
	# 4. 初始化基础参数
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.csv ; MT4 History", "*.txt"]
	
	# 修改: Timer 时间可以设长一点，以便容纳内部的 tick 动画
	playback_timer.wait_time = 1.0 
	# 5. 初始化终端面板
	if terminal:
		terminal.setup(account)
		# 连接双击事件
		terminal.order_double_clicked.connect(func(order):
			# 获取当前价格用于展示
			var cur_price = 0.0
			if not _cached_last_candle.is_empty():
				cur_price = _cached_last_candle.c
				
			# 弹出窗口
			close_dialog.popup_order(order, cur_price)
		)
	else:
		printerr("警告：未找到 TerminalPanel 节点")

	# --- 初始化交易窗口系统 ---
	# 1. 创建半透明遮罩 (Overlay)
	order_window_overlay = Control.new()
	order_window_overlay.set_anchors_preset(Control.PRESET_FULL_RECT) # 全屏
	order_window_overlay.visible = false
	# 创建一个黑色背景（改为透明）
	var bg = ColorRect.new()
	# [关键修改] Alpha 改为 0，完全透明，不再变暗
	bg.color = Color(0, 0, 0, 0.0) 
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	order_window_overlay.add_child(bg)
	# 点击背景关闭窗口
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			order_window_overlay.visible = false
	)
	# 添加到 CanvasLayer 保证在最上层
	add_child(order_window_overlay)
	
	# 2. 创建订单窗口
	order_window = OrderWindow.new()
	# 居中显示
	order_window.set_anchors_preset(Control.PRESET_CENTER) 
	# 将窗口添加到遮罩层里
	order_window_overlay.add_child(order_window)
	
	# 3. 连接信号：窗口请求下单 -> 控制器执行
	order_window.market_order_requested.connect(_on_order_window_submit)
	order_window.window_closed.connect(func(): order_window_overlay.visible = false)

	# [新增] 初始化 HUD
	hud_display = MarketHUD.new()
	add_child(hud_display)
	# 定位到屏幕左上角
	hud_display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud_display.position = Vector2(20, 20) # 留点边距

	# --- 初始化 实时布林带 ---
	# 参数：开启=True, 周期=变量, 倍数=变量, 颜色=青色(CYAN)
	if chart:
		# 使用变量 _bb_period 和 _bb_k，而不是写死 20 和 2.0
		chart.set_bollinger_visible(true, _bb_period, _bb_k, Color.CYAN)
		print(">> 系统初始化: 布林带已激活 (Period=%d, K=%.2f)" % [_bb_period, _bb_k])
	else:
		print(">> 错误: 未找到 KLineChart 节点 <<")
	
	# [新增] 初始化布林带配置 UI
	_setup_bb_config_ui()
	
	# [新增] 启动时先应用一次默认值 (确保图表上有线)
	_apply_bb_settings()
	
	# [新增] 初始化跳转控制条（放在 _ready 末尾）
	_setup_playback_controls()


func _setup_ui_signals():
	# 文件与回放
	if btn_load: btn_load.pressed.connect(func(): file_dialog.popup_centered(Vector2(800, 600)))
	if btn_play: btn_play.pressed.connect(_toggle_play)
	if file_dialog: file_dialog.file_selected.connect(_on_file_selected)
	if playback_timer: playback_timer.timeout.connect(_on_timer_tick)
	
	# 交易控制
	# 点击 BUY -> 打开订单窗口
	if btn_buy: 
		btn_buy.pressed.connect(func(): _open_order_window(OrderData.Type.BUY))
	
	# 点击 SELL -> 打开订单窗口
	if btn_sell: 
		btn_sell.pressed.connect(func(): _open_order_window(OrderData.Type.SELL))
		
	# 点击 Close All -> 平掉所有单子
	if btn_close_all:
		btn_close_all.pressed.connect(func():
			if _cached_last_candle.is_empty(): return
			var price = _cached_last_candle.c
			var time_str = _cached_last_candle.t
			account.close_market_order(-1, price, time_str)
		)
	
	# 绘图工具
	if btn_trendline:
		btn_trendline.pressed.connect(func():
			chart.start_drawing("TrendLine")
		)
	
	# 指标工具
	if btn_add_ma:
		btn_add_ma.pressed.connect(func():
			print("计算并添加 MA14...")
			chart.calculate_and_add_ma(14, Color.CYAN)
			chart.calculate_and_add_ma(30, Color.MAGENTA) # 顺便加个 MA30
			# 同时添加分型
			chart.calculate_and_add_fractals()
		)

# [新增] 图表控制按钮设置
func _setup_chart_controls():
	# 创建容器放在右上角
	var hbox = HBoxContainer.new()
	hbox.position = Vector2(250, 60)  # 放在工具栏旁边
	hbox.add_theme_constant_override("separation", 10)
	chart.add_child(hbox)
	
	# 1. Auto Scroll 开关
	var btn_auto = CheckButton.new()
	btn_auto.text = "Auto"
	btn_auto.button_pressed = true  # 默认开启
	btn_auto.focus_mode = Control.FOCUS_NONE
	hbox.add_child(btn_auto)
	
	btn_auto.toggled.connect(func(on):
		print("Auto Scroll:", "ON" if on else "OFF")
		chart.set_auto_scroll(on)
	)
	
	# 2. Chart Shift 开关 (留白)
	var btn_shift = CheckButton.new()
	btn_shift.text = "Shift"
	btn_shift.button_pressed = true  # 默认开启留白
	btn_shift.focus_mode = Control.FOCUS_NONE
	hbox.add_child(btn_shift)
	
	btn_shift.toggled.connect(func(on):
		print("Chart Shift:", "ON" if on else "OFF")
		chart.toggle_chart_shift(on)
	)

# [修复版] 动态构建回放进度条 UI (使用 CanvasLayer 确保可见性)
func _setup_playback_controls():
	# 1. 创建独立的 CanvasLayer
	# 这能保证进度条始终悬浮在画面最上层，不会被图表或底板遮挡
	var ui_layer = CanvasLayer.new()
	ui_layer.layer = 5 # 层级设为 5，高于普通 UI，但低于弹窗(通常是100)
	ui_layer.name = "PlaybackUILayer"
	add_child(ui_layer)

	# 2. 创建底部的 Panel 容器
	var panel = PanelContainer.new()
	# 设置锚点为底部全宽
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# 显式设置偏移量：距离底部 60px 的高度
	panel.offset_top = -60 
	panel.offset_bottom = 0
	
	# [关键] 添加背景样式，确保你能看清它，而不是透明的
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 1.0) # 深灰色背景，完全不透明
	style.border_width_top = 2
	style.border_color = Color(0.3, 0.3, 0.3) # 顶部加一条亮边
	panel.add_theme_stylebox_override("panel", style)
	
	ui_layer.add_child(panel)

	# 3. 布局容器
	var hbox = HBoxContainer.new()
	# 增加一些内边距，不要贴边
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	
	panel.add_child(margin)
	margin.add_child(hbox)

	# 4. 进度条 (Slider)
	_playback_slider = HSlider.new()
	_playback_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 撑满宽度
	_playback_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_playback_slider.min_value = 0
	_playback_slider.scrollable = false # 禁止滚轮防止误触
	
	# 稍微美化一下 Slider (可选)
	_playback_slider.modulate = Color(0.0, 0.8, 1.0) # 青蓝色高亮
	hbox.add_child(_playback_slider)

	# 5. 时间显示标签 (Label)
	# 加一个分割占位
	var spacer = Control.new()
	spacer.custom_minimum_size.x = 20
	hbox.add_child(spacer)

	_playback_label = Label.new()
	_playback_label.text = "Waiting for data..."
	_playback_label.custom_minimum_size.x = 200
	_playback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_playback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_playback_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(_playback_label)

	# --- 连接信号 (保持不变) ---

	# 拖拽开始：暂停播放
	_playback_slider.drag_started.connect(func():
		_is_dragging_slider = true
		if is_playing:
			_toggle_play() # 暂停
	)

	# 拖拽过程：实时更新预览时间
	_playback_slider.value_changed.connect(func(val):
		_update_time_label(int(val))
	)

	# 拖拽结束：执行跳转
	_playback_slider.drag_ended.connect(func(value_changed):
		_is_dragging_slider = false
		# 注意：drag_ended 的 value_changed 参数有时可能为 false，
		# 但我们仍然希望在松手时跳转，所以直接取 value
		jump_to_index(int(_playback_slider.value))
	)
	
	print(">> 进度条 UI 已创建 (CanvasLayer)")


# [新增] 辅助更新时间标签
func _update_time_label(idx: int):
	if full_history_data.is_empty(): return
	var safe_idx = clamp(idx, 0, full_history_data.size() - 1)
	var time_str = full_history_data[safe_idx].t
	# 显示格式：Index / Total [Time]
	_playback_label.text = "%s (%d/%d)" % [time_str, safe_idx + 1, full_history_data.size()]


# [新增] 核心跳转逻辑
func jump_to_index(target_index: int):
	if full_history_data.is_empty(): return

	print(">> 跳转至索引: ", target_index)

	# 1. [关键] 安全检查与状态重置
	target_index = clamp(target_index, 0, full_history_data.size() - 1)

	# 2. [关键] 增加代数 ID，这将使得正在运行的 _simulate_candle_ticks 立即失效
	_current_tick_generation += 1

	# 3. 停止定时器
	playback_timer.stop()
	is_playing = false
	if btn_play: btn_play.text = "Play"

	# 4. 更新当前索引
	current_playback_index = target_index

	# 5. 重置账户数据 (因为时间变了，旧订单不再有效)
	account.reset_data()

	# 6. 重组图表数据
	# 取出 0 到 target_index 的所有数据
	var new_history = full_history_data.slice(0, current_playback_index + 1)

	# 7. 刷新图表
	chart.set_history_data(new_history)
	chart.scroll_to_end() # 确保视图在最右边

	# 8. 更新缓存 (非常重要，否则后续逻辑会崩溃)
	_cached_last_candle = new_history.back().duplicate()

	# 9. 强制刷新一次 UI 和 辅助线
	# 因为 reset_data 清空了账户，我们需要通知图表清除画线
	chart.update_visual_orders([], [])
	# 更新现价线
	chart.update_current_price(_cached_last_candle.c, 0)
	# 更新 HUD
	_analyze_market_structure()

	print("<< 跳转完成. 当前时间: ", _cached_last_candle.t)


# --- 交易执行包装器 ---
func _execute_trade(type: OrderData.Type):
	if _cached_last_candle.is_empty():
		print("错误: 当前没有价格数据，无法交易")
		return
	
	# 获取当前最新的价格和时间
	# 注意：实际交易最好用 Bid/Ask，模拟器简化为用 Close 价格成交
	var price = _cached_last_candle.c 
	var time_str = _cached_last_candle.t
	
	# 下单: 类型, 手数0.1, 现价, 时间
	account.open_market_order(type, 0.1, price, time_str)

# --- 订单窗口接口 ---

# 打开订单窗口 (集成 ATR 自动止损计算)
func _open_order_window(default_type: OrderData.Type):
	if _cached_last_candle.is_empty():
		print("没有数据，无法交易")
		return
		
	var price = _cached_last_candle.c
	
	# --- 智能风控计算 (ATR) ---
	var suggested_sl = 0.0
	var suggested_tp = 0.0
	
	# 1. 获取最近的 ATR (周期 14)
	# 注意：为了性能，这里我们简单计算，或者如果已经有缓存最好。
	# 由于计算整个历史的 ATR 很快，直接算即可。
	var atr_values = IndicatorCalculator.calculate_atr(full_history_data, 14)
	var current_idx = current_playback_index
	
	# 安全检查：确保索引不越界
	if current_idx < atr_values.size():
		var current_atr = atr_values[current_idx]
		if not is_nan(current_atr) and current_atr > 0:
			print("当前 ATR(14): %.5f" % current_atr)
			
			# 策略：止损 = 1.5倍 ATR, 止盈 = 2.0倍 ATR (盈亏比 1:1.3)
			var sl_dist = current_atr * 1.5
			var tp_dist = current_atr * 2.5 # 稍微贪婪一点
			
			if default_type == OrderData.Type.BUY:
				suggested_sl = price - sl_dist
				suggested_tp = price + tp_dist
			else:
				suggested_sl = price + sl_dist
				suggested_tp = price - tp_dist
	
	# 显式显示遮罩和窗口
	order_window_overlay.visible = true
	order_window.visible = true
	order_window_overlay.move_to_front() 
	
	# 2. 填入智能计算的数值
	order_window.setup_values(0.1, suggested_sl, suggested_tp)
	
	# 立即刷新一次价格
	order_window.update_market_data(price, price)

# 接收窗口的下单请求
func _on_order_window_submit(type: OrderData.Type, lots: float, sl: float, tp: float):
	if _cached_last_candle.is_empty(): return
	
	var price = _cached_last_candle.c
	var time_str = _cached_last_candle.t
	
	# 调用账户开仓，传入完整的 SL/TP
	account.open_market_order(type, lots, price, time_str, sl, tp)


# --- 回放逻辑 ---

func _on_file_selected(path: String):
	print("加载 CSV: ", path)
	is_playing = false
	playback_timer.stop()
	
	var data = CsvLoader.load_mt4_csv(path)
	if data.is_empty(): return
	
	full_history_data = data
	
	# 初始化前 100 根
	var init_count = min(100, full_history_data.size())
	current_playback_index = init_count
	
	var init_data = full_history_data.slice(0, current_playback_index)
	chart.set_history_data(init_data)
	chart.jump_to_index(init_data.size() - 1)
	
	# 更新缓存
	if not init_data.is_empty():
		_cached_last_candle = init_data.back()
		# 初始化时也更新一次账户净值（虽然此时应该没单子）
		account.update_equity(_cached_last_candle.c)
		# 在初始化完历史数据后，手动更新一次现价线
		chart.update_current_price(_cached_last_candle.c)

	# [新增] 初始化进度条范围
	if _playback_slider:
		_playback_slider.max_value = full_history_data.size() - 1
		_playback_slider.set_value_no_signal(current_playback_index)

	# === [新增开始] 计算 EMA 200 趋势线 ===
	print(">> 正在计算 EMA 200 趋势过滤器...")
	var closes = []
	for candle in full_history_data:
		closes.append(candle.c)
		
	# 计算全量数据
	_history_ema200 = IndicatorCalculator.calculate_ema(closes, 200)
	
	# 立即绘制到图表上 (橙色，线宽 2.0)
	chart.add_trend_line_data(_history_ema200, Color.ORANGE, 2.0)
	# === [新增结束] ===

func _toggle_play():
	if full_history_data.is_empty(): return
	is_playing = !is_playing
	if is_playing:
		playback_timer.start()
		if btn_play: btn_play.text = "Pause"
	else:
		playback_timer.stop()
		if btn_play: btn_play.text = "Play"

func _on_timer_tick():
	if current_playback_index >= full_history_data.size():
		is_playing = false
		playback_timer.stop()
		print("回放结束")
		return
	
	# 如果用户正在拖拽，暂停自动逻辑，防止抢夺控制权
	if _is_dragging_slider: return

	# 1. 暂停定时器！！绝对不能让定时器打断我们的 await 表演
	playback_timer.stop()
	
	var target_candle = full_history_data[current_playback_index]

	# [新增] 同步更新 Slider 的值 (但不触发信号)
	if _playback_slider:
		_playback_slider.set_value_no_signal(current_playback_index)
		_update_time_label(current_playback_index)

	# 2. 等待表演结束 (这会花好几秒)
	await _simulate_candle_ticks(target_candle)
	
	current_playback_index += 1
	
	# 3. 表演完了，再开启定时器准备下一根
	if is_playing:
		# 这里可以设置 wait_time 为 0.1，因为所有的延迟都在 simulate 内部控制了
		playback_timer.start(0.1)

# --- 账户回调 (UI 更新) ---

func _on_account_balance_updated(bal: float):
	if lbl_balance:
		lbl_balance.text = "Balance: $%.2f" % bal

func _on_account_equity_updated(equity: float, floating: float):
	if lbl_equity:
		var color_hex = "00ff00" if floating >= 0 else "ff0000"
		# 使用 BBCode 染色 (需确保 Label 开启 RichText, 如未开启则去掉 bbcode tags)
		# 这里为了安全起见，暂时用纯文本，你可以根据喜好开启 RichTextLabel
		lbl_equity.text = "Equity: $%.2f (%.2f)" % [equity, floating]
		# 简单的颜色变幻
		if floating >= 0:
			lbl_equity.modulate = Color.GREEN
		else:
			lbl_equity.modulate = Color.RED

# [Stage 4 新增] 音效播放逻辑 (简单的占位符)
func _play_trade_sound():
	if sfx_player.stream != null:
		sfx_player.play()
	else:
		# 如果没有音频文件，打印日志代替
		print(">> [SOUND] Cash Register/Close Sound <<")

#  带详细 Log 的慢速 K 线生成器
func _simulate_candle_ticks(final_data: Dictionary):
	# [新增] 记录当前的代数 ID
	var my_generation = _current_tick_generation

	var t_str = final_data.t
	var o = final_data.o

	# 1. 胚胎状态：初始 K 线只是一条横线
	var current_sim_candle = {
		"t": t_str,
		"o": o,
		"h": o, # 刚开盘 High = Open
		"l": o, # 刚开盘 Low = Open
		"c": o  
	}

	# 先画第一笔，确保屏幕上出现 Dash
	_process_tick(current_sim_candle, o, 60)

	# 2. 生成剧本
	var ticks = _generate_tick_path(o, final_data.h, final_data.l, final_data.c)
	var total_steps = ticks.size()

	# 3. 开始表演 (Tick 循环)
	for i in range(total_steps):
		# [修改] 关键检查点 1：如果用户停止播放，或者发生了跳转(代数变了)，立即终止
		if not is_playing or my_generation != _current_tick_generation:
			# print("协程中断: Generation mismatch or Stopped") 
			return
			
		var price = ticks[i]
		
		# --- 核心生长逻辑 ---
		current_sim_candle.c = price
		# 如果价格冲高，把 High 顶上去
		if price > current_sim_candle.h: 
			current_sim_candle.h = price
		# 如果价格杀跌，把 Low 踩下去
		if price < current_sim_candle.l: 
			current_sim_candle.l = price
			
		# 计算倒计时 (假装这是 1 分钟 K 线)
		var progress = float(i) / float(total_steps)
		var secs_left = int(60 * (1.0 - progress))
		
		# --- 更新 UI ---
		_process_tick(current_sim_candle, price, secs_left)
		
		# --- [关键] 强制等待 ---
		await get_tree().create_timer(tick_delay).timeout
		
		# [修改] 关键检查点 2：等待回来后再次检查，防止等待期间发生了跳转
		if my_generation != _current_tick_generation:
			return

	# 4. 完美收官
	_process_tick(final_data, final_data.c, 0)
	_cached_last_candle = final_data
# [修复版] 强制生成高密度的路径点
func _generate_tick_path(o: float, h: float, l: float, c: float) -> Array[float]:
	var path_points = []
	
	# 1. 定义骨架 (Anchor Points)
	# 逻辑：从 Open 出发 -> 随机先去 High 还是 Low -> 最后到 Close
	var anchors = [o]
	
	# 50% 概率先去最高，50% 先去最低，增加随机感
	if randf() > 0.5:
		# 路径: Open -> High -> Low -> Close
		anchors.append(lerp(o, h, 0.5)) # 中途点
		anchors.append(h)
		anchors.append(lerp(h, l, 0.5)) # 中途点
		anchors.append(l)
	else:
		# 路径: Open -> Low -> High -> Close
		anchors.append(lerp(o, l, 0.5)) 
		anchors.append(l)
		anchors.append(lerp(l, h, 0.5)) 
		anchors.append(h)
	
	anchors.append(c) # 最后必须回到 Close
	
	# 2. 填充血肉 (Ticks)
	var result_ticks: Array[float] = []
	
	# [关键修改] 强制每个区间生成至少 20 个点。
	# 假如 anchors 有 5 个点，那么总共有 4 段 * 20 = 80 个 Tick
	var points_per_segment = 20 
	
	for i in range(anchors.size() - 1):
		var p_start = anchors[i]
		var p_end = anchors[i+1]
		
		for step in range(points_per_segment):
			var t = float(step) / float(points_per_segment)
			
			# 线性插值
			var base = lerp(p_start, p_end, t)
			
			# 叠加噪声 (让线条抖动)
			_noise_offset += 1.32
			var noise_val = _noise.get_noise_1d(_noise_offset * 50.0) 
			
			# 动态振幅：价差越大抖动越厉害，但至少给一点抖动
			var segment_diff = abs(p_end - p_start)
			var shake_amp = max(segment_diff * 0.15, 0.00005) 
			
			var final_val = base + (noise_val * shake_amp)
			result_ticks.append(final_val)
			
	# 补上终点，确保数据闭环
	result_ticks.append(c)
	
	return result_ticks

# [修改] 参数增加 seconds_left
func _process_tick(candle_state: Dictionary, current_price: float, seconds_left: int):
	# 1. 如果是这根 K 线的第一次(Time变了)，需要 append，否则是 update
	if _cached_last_candle.get("t") != candle_state.t:
		chart.append_candle(candle_state.duplicate())
		# 新 K 线生成时，不再强制滚屏，遵从 chart.append_candle 中的 _auto_scroll 逻辑。
		# 原先的 chart.scroll_to_end() 会把 _auto_scroll 强制设为 true，导致用户设置被覆盖。
		# 已移除该强制调用以修复 Auto Scroll 被重置的问题。
	else:
		chart.update_last_candle(candle_state.duplicate())
	
	# 更新缓存
	_cached_last_candle = candle_state.duplicate()
	
	# 2. 更新现价线 (UI) -> 传入倒计时
	chart.update_current_price(current_price, seconds_left)
	
	# 3. 喂给账户系统
	account.update_equity(current_price)
	
	# 更新订单窗口报价
	if order_window and order_window.visible:
		order_window.update_market_data(current_price, current_price)
	
	# 4. 刷新订单层
	# 偶尔略过绘制以提升性能？不用，现在电脑快。
	chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
	
	# [新增] 每一跳都分析一次市场结构
	_analyze_market_structure()

# [新增] 核心策略分析器 (修改版：使用预计算的 EMA)
func _analyze_market_structure():
	if full_history_data.is_empty(): return
	
	# 获取当前 K 线索引
	# 注意：current_playback_index 指向的是"即将"发生的 K 线
	# 在播放中，我们实际上是在模拟 current_playback_index 这一根的生成
	# 所以要获取当前的 EMA 值，就用这个索引
	var idx = current_playback_index
	
	# 边界检查
	var current_ema = NAN
	if idx >= 0 and idx < _history_ema200.size():
		current_ema = _history_ema200[idx]
	
	# 获取当前实时价格 (来自缓存的最新一跳价格)
	var current_price = 0.0
	if not _cached_last_candle.is_empty():
		current_price = _cached_last_candle.c
	
	# === 更新 HUD (趋势过滤器) ===
	if hud_display:
		hud_display.update_trend_filter(current_price, current_ema)
		
		# 同时更新 RSI 和 ATR (保留原来的部分逻辑)
		# 为了性能，这里可以简化，不再重复切片计算 EMA
		# 只需要计算 RSI/ATR
		_update_oscillators_for_hud(idx)

# [新增辅助] 提取原本的震荡指标计算逻辑，保持代码整洁
func _update_oscillators_for_hud(end_idx: int):
	if full_history_data.is_empty(): return
	if end_idx < 14: return # 数据太少
	
	# 1. 准备实时数据窗口 (最近 200 根足矣)
	var lookback = 250 
	var start_idx = max(0, end_idx - lookback)
	var slice_data = [] # KLine Dict Array
	var slice_closes = [] # Float Array for Math
	
	for i in range(start_idx, end_idx + 1): # 包含 end_idx 本身
		if i >= full_history_data.size(): break
		var candle = full_history_data[i]
		slice_data.append(candle)
		slice_closes.append(candle.c)
	
	if slice_closes.is_empty(): return
		
	# 2. 计算 RSI 14 和 ATR 14
	var rsi_arr = IndicatorCalculator.calculate_rsi(slice_closes, 14)
	var current_rsi = rsi_arr.back() if not rsi_arr.is_empty() else NAN
	
	var atr_arr = IndicatorCalculator.calculate_atr(slice_data, 14)
	var current_atr = atr_arr.back() if not atr_arr.is_empty() else NAN
	
	# 3. 更新 HUD 的 RSI/ATR 显示
	if hud_display:
		hud_display.update_status_indicators(current_rsi, current_atr)


# --- 布林带配置 UI 相关函数 ---

func _setup_bb_config_ui():
	# 1. 创建入口按钮 (放在屏幕右上角或者其他空闲位置)
	var btn_config = Button.new()
	btn_config.text = "🔧 BB Config"
	btn_config.position = Vector2(100, 60) # 你可以根据实际情况调整位置，比如放在 MA 按钮旁边
	btn_config.size = Vector2(100, 30)
	# 添加到 CanvasLayer 确保显示在最上层，或者直接加到 HUD 里
	# 这里为了简单，直接加到当前节点，如果被遮挡，建议加到 HUD 的父节点下
	add_child(btn_config) 
	
	# 2. 创建配置弹窗
	_bb_config_dialog = ConfirmationDialog.new()
	_bb_config_dialog.title = "Bollinger Bands Settings"
	_bb_config_dialog.min_size = Vector2(300, 150)
	add_child(_bb_config_dialog)
	
	var vbox = VBoxContainer.new()
	_bb_config_dialog.add_child(vbox)
	
	# --- 周期设置 ---
	var hbox1 = HBoxContainer.new()
	vbox.add_child(hbox1)
	var lbl1 = Label.new()
	lbl1.text = "Period (N): "
	lbl1.custom_minimum_size.x = 100
	hbox1.add_child(lbl1)
	
	_spin_period = SpinBox.new()
	_spin_period.min_value = 2
	_spin_period.max_value = 200
	_spin_period.value = _bb_period
	_spin_period.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox1.add_child(_spin_period)
	
	# --- 倍数设置 (关键参数) ---
	var hbox2 = HBoxContainer.new()
	vbox.add_child(hbox2)
	var lbl2 = Label.new()
	lbl2.text = "Deviation (K): " # 这就是控制上下轨宽度的参数
	lbl2.custom_minimum_size.x = 100
	hbox2.add_child(lbl2)
	
	_spin_k = SpinBox.new()
	_spin_k.min_value = 0.1
	_spin_k.max_value = 10.0
	_spin_k.step = 0.1     # 允许 0.1 的微调，比如 2.1, 2.2
	_spin_k.value = _bb_k
	_spin_k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox2.add_child(_spin_k)
	
	# 3. 连接信号
	# 点击按钮 -> 打开弹窗
	btn_config.pressed.connect(func():
		_spin_period.value = _bb_period
		_spin_k.value = _bb_k
		_bb_config_dialog.popup_centered()
	)
	
	# 点击确定 -> 应用设置
	_bb_config_dialog.confirmed.connect(func():
		_bb_period = int(_spin_period.value)
		_bb_k = _spin_k.value
		_apply_bb_settings()
	)

func _apply_bb_settings():
	print(">> 应用布林带参数: Period=%d, K=%.2f" % [_bb_period, _bb_k])
	
	# 1. 调用 Chart 的接口重绘指标
	if chart:
		# 强制显式颜色 Cyan，确保三青线视觉一致
		chart.set_bollinger_visible(true, _bb_period, _bb_k, Color.CYAN)
		# 如果需要立即刷新，可以调用 chart.queue_redraw()，但 set_bollinger_visible 内部通常处理了

	# 2. (可选) 更新 HUD 显示当前参数
	if hud_display and hud_display.has_method("update_bb_info"):
		hud_display.update_bb_info(_bb_period, _bb_k)
