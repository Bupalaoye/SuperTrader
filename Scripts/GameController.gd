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

# --- 噪声生成 (Perlin Noise) ---
var _noise: FastNoiseLite
var _noise_offset: float = 0.0 # 噪声的滚动偏移量

# --- 核心数据 ---
var full_history_data: Array = [] 
var current_playback_index: int = 0 
var is_playing: bool = false
var _cached_last_candle: Dictionary = {} # 缓存当前K线，防止空数据

# 修改: 增加 tick 间隔控制
var tick_delay: float = 0.05 # 每个微 Tick 之间的间隔 (秒)

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

	print("系统就绪! 请加载 CSV 数据。")

	

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
		)

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

# 打开订单窗口
func _open_order_window(default_type: OrderData.Type):
	if _cached_last_candle.is_empty():
		print("没有数据，无法交易")
		return
		
	var price = _cached_last_candle.c
	
	# 显示遮罩和窗口
	order_window_overlay.visible = true
	order_window.visible = true
	order_window_overlay.move_to_front() # 确保在最前
	
	# 初始化数值 (默认 0.1 手，SL/TP 为 0)
	order_window.setup_values(0.1, 0.0, 0.0)
	
	# 立即刷新一次价格
	order_window.update_market_data(price, price) 
	# 注意：真实交易里 bid 和 ask 有点差，这里模拟器暂且认为 bid=ask=close

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
	
	# 暂停主 Timer，避免 Tick 动画还没播完，下一根 K 线就来了
	playback_timer.stop()
	
	# 获取这一根完整的数据
	var target_candle = full_history_data[current_playback_index]
	
	# 执行 Tick 模拟协程
	await _simulate_candle_ticks(target_candle)
	
	current_playback_index += 1
	
	# 动画播完，如果还是播放状态，恢复计时器开始下一轮
	if is_playing:
		playback_timer.start()

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

# [核心重写] 模拟真实的 K 线生长过程
func _simulate_candle_ticks(final_data: Dictionary):
	var t_str = final_data.t
	var o = final_data.o
	var h_target = final_data.h
	var l_target = final_data.l
	var c_target = final_data.c
	
	# 1. 出生阶段：K线刚出来时，是一条横线，O=H=L=C
	var current_sim_candle = {
		"t": t_str,
		"o": o,
		"h": o, # 注意：最高价初始为开盘价
		"l": o, # 注意：最低价初始为开盘价
		"c": o  
	}
	
	# 立即推送“初始胚胎”，让用户看到新K线诞生
	_process_tick(current_sim_candle, o, 60)
	
	# 2. 规划路径：生成一系列微观价格点 (Ticks)
	# 这是核心：路径必须保证经过 High 和 Low，最后落在 Close
	var ticks = _generate_tick_path(o, h_target, l_target, c_target)
	
	# 3. 演化循环 (Evolution Loop)
	var total_ticks = ticks.size()
	
	for i in range(total_ticks):
		# 如果用户点了暂停或停止，终止循环
		if not is_playing: 
			return
		
		var tick_price = ticks[i]
		
		# --- [注入灵魂的关键逻辑] ---
		# 随着 Tick 价格的变化，动态推高 H 或 踩低 L
		# 这就是“K线是长出来的”视觉原理
		current_sim_candle.c = tick_price
		if tick_price > current_sim_candle.h:
			current_sim_candle.h = tick_price
		if tick_price < current_sim_candle.l:
			current_sim_candle.l = tick_price
			
		# 计算倒计时 (模拟 1 分钟内的 60 秒倒数)
		var progress = float(i) / float(total_ticks)
		var seconds_left = int(60.0 * (1.0 - progress))
		
		# 推送更新 (刷新图表、现价线、账户盈亏)
		_process_tick(current_sim_candle, tick_price, seconds_left)
		
		# --- [节奏控制] ---
		# 模拟市场的快慢节奏：有时候快，有时候慢
		# 比如：大幅波动时快一点，盘整时慢一点
		var dynamic_delay = randf_range(0.02, 0.08) # 平均 0.05秒一跳
		await get_tree().create_timer(dynamic_delay).timeout

	# 4. 定格阶段：强制对齐最终数据
	# 模拟结束，必须确保最终的 H/L/C 与历史数据完全一致
	# 这一步消除了插值和噪声带来的微小误差
	_process_tick(final_data, c_target, 0)
	_cached_last_candle = final_data

# [新增] 生成包含 High 和 Low 的随机路径
func _generate_tick_path(o: float, h: float, l: float, c: float) -> Array[float]:
	var path_points = []
	
	# --- A. 确定关键锚点 (Anchors) ---
	# 逻辑：价格必须从 O 出发，经过 H 和 L，最后到达 C。
	# 问题是先去 H 还是先去 L？
	# 我们根据形态做一个概率判断，或者完全随机。
	
	var anchors = [o]
	
	# 简单的策略：
	# 1. 阳线 (Close > Open)：通常先探底(L)，再冲高(H)，再回落(C)
	# 2. 阴线 (Close < Open)：通常先冲高(H)，再探底(L)，再反弹(C)
	# 当然，为了真实，我们偶尔打乱顺序
	
	var is_bull = c >= o
	var go_low_first = is_bull # 默认逻辑
	
	# 20% 的概率走“反常”路线 (比如阳线先冲高再回落再拉升)
	if randf() < 0.2:
		go_low_first = !go_low_first
	
	if go_low_first:
		# 路径: O -> L -> H -> C
		anchors.append(lerp(o, l, 0.5)) # 中途停顿
		anchors.append(l)               # 踩到最低
		anchors.append(lerp(l, h, 0.4)) # 反弹
		anchors.append(h)               # 冲到最高
	else:
		# 路径: O -> H -> L -> C
		anchors.append(lerp(o, h, 0.5)) # 中途停顿
		anchors.append(h)               # 冲到最高
		anchors.append(lerp(h, l, 0.4)) # 下跌
		anchors.append(l)               # 踩到最低
	
	anchors.append(c) # 终点
	
	# --- B. 填充路径 (Interpolation & Noise) ---
	# 将锚点之间填满微小的 Ticks
	
	var result_ticks: Array[float] = []
	var ticks_per_segment = 20 # 每个锚点之间生成多少个微跳动
	
	for i in range(anchors.size() - 1):
		var p_start = anchors[i]
		var p_end = anchors[i+1]
		
		for step in range(ticks_per_segment):
			var t = float(step) / float(ticks_per_segment)
			
			# 1. 线性插值作为基准
			var base = lerp(p_start, p_end, t)
			
			# 2. 叠加柏林噪声 (制造自然波动)
			_noise_offset += 1.0 # 快速滚动噪声
			var noise_val = _noise.get_noise_1d(_noise_offset) * 0.5 # -0.5 ~ 0.5
			
			# 噪声幅度：基于当前段落的价差，价差越大波动越明显
			var amplitude = abs(p_end - p_start) * 0.3
			# 最小给一点波动，防止死水
			if amplitude < 0.00005: amplitude = 0.00005 
			
			var final_val = base + (noise_val * amplitude)
			
			result_ticks.append(final_val)
			
	# 补上最后一个点
	result_ticks.append(c)
	
	return result_ticks

	
# [修改] 参数增加 seconds_left
func _process_tick(candle_state: Dictionary, current_price: float, seconds_left: int):
	# 1. 如果是这根 K 线的第一次(Time变了)，需要 append，否则是 update
	if _cached_last_candle.get("t") != candle_state.t:
		chart.append_candle(candle_state.duplicate())
		# 新 K 线生成时，强制滚屏，确保可见
		chart.scroll_to_end()
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
