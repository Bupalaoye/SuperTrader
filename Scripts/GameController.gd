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

# --- 核心数据 ---
var full_history_data: Array = [] 
var current_playback_index: int = 0 
var is_playing: bool = false
var _cached_last_candle: Dictionary = {} # 缓存当前K线，防止空数据

# 修改: 增加 tick 间隔控制
var tick_delay: float = 0.1 # 每个微 Tick 之间的间隔 (秒)

func _ready():
	print("正在初始化控制器...")
	
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
	account.order_closed.connect(func(o): 
		print("UI通知: 平仓完成 #", o.ticket_id)
		# 传递 active 和 history
		chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
	)

	# 3. 连接 UI 交互信号
	_setup_ui_signals()
	
	# 4. 初始化基础参数
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.csv ; MT4 History", "*.txt"]
	
	# 修改: Timer 时间可以设长一点，以便容纳内部的 tick 动画
	playback_timer.wait_time = 1.0 
	# 5. 初始化终端面板
	if terminal:
		terminal.setup(account)
	else:
		printerr("警告：未找到 TerminalPanel 节点")

	print("系统就绪! 请加载 CSV 数据。")
	

func _setup_ui_signals():
	# 文件与回放
	if btn_load: btn_load.pressed.connect(func(): file_dialog.popup_centered(Vector2(800, 600)))
	if btn_play: btn_play.pressed.connect(_toggle_play)
	if file_dialog: file_dialog.file_selected.connect(_on_file_selected)
	if playback_timer: playback_timer.timeout.connect(_on_timer_tick)
	
	# 交易控制
	# 点击 BUY -> 开 0.1 手多单
	if btn_buy: 
		btn_buy.pressed.connect(func(): _execute_trade(OrderData.Type.BUY))
	
	# 点击 SELL -> 开 0.1 手空单
	if btn_sell: 
		btn_sell.pressed.connect(func(): _execute_trade(OrderData.Type.SELL))
		
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

# [新增] 模拟一根 K 线内部的波动
func _simulate_candle_ticks(final_data: Dictionary):
	var t_str = final_data.t
	var o = final_data.o
	var h = final_data.h
	var l = final_data.l
	var c = final_data.c
	
	# 构建一个临时 K 线对象
	var temp_candle = {
		"t": t_str,
		"o": o,
		"h": o, # 初始最高也是开盘
		"l": o, # 初始最低也是开盘
		"c": o  # 初始收盘也是开盘
	}
	
	# --- Tick 1: 开盘 (Open) ---
	_process_tick(temp_candle, o)
	await get_tree().create_timer(tick_delay).timeout
	if not is_playing: return # 允许中途暂停
	
	# --- Tick 2: 随机先去 High 还是 Low ---
	# 为了真实感，我们简单随机一下顺序
	# 假设逻辑：先去 Low，再去 High，最后去 Close (或者反之)
	
	# 这里简单处理：Open -> Low -> High -> Close
	# 你可以在未来加入更复杂的随机插值算法
	
	# 模拟去往 Low 的过程
	temp_candle.l = l
	temp_candle.c = l # 现价跌到 Low
	# 注意：如果 Low 低于当前的 Open，Height 保持不变
	
	_process_tick(temp_candle, l)
	await get_tree().create_timer(tick_delay).timeout
	if not is_playing: return
	
	# 模拟去往 High 的过程
	temp_candle.h = h
	temp_candle.c = h # 现价拉到 High
	
	_process_tick(temp_candle, h)
	await get_tree().create_timer(tick_delay).timeout
	if not is_playing: return
	
	# --- Tick 3: 收盘 (Close) ---
	temp_candle.c = c
	# 最终状态确认
	_process_tick(temp_candle, c)
	
	# 缓存更新，确保交易逻辑用到最新的全量数据
	_cached_last_candle = final_data 

# [新增] 处理单个 Tick 的通用逻辑
func _process_tick(candle_state: Dictionary, current_price: float):
	# 1. 如果是这根 K 线的第一次(Open)，需要 append，否则是 update
	# 判断依据：_cached_last_candle 的时间是否和当前不同
	if _cached_last_candle.get("t") != candle_state.t:
		chart.append_candle(candle_state.duplicate())
	else:
		chart.update_last_candle(candle_state.duplicate())
	
	# 更新缓存
	_cached_last_candle = candle_state.duplicate()
	
	# 2. 更新现价线 (UI)
	chart.update_current_price(current_price)
	
	# 3. 喂给账户系统计算盈亏 (核心交易逻辑)
	account.update_equity(current_price)
	
	# 4. 刷新订单层
	# 注意：Tick 频繁更新历史订单可能费性能，这里只传 Active 也行
	# 但为了视觉连贯，都传
	chart.update_visual_orders(account.get_active_orders(), account.get_history_orders())
