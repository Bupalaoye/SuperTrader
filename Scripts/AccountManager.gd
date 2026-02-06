class_name AccountManager
extends Node

# --- 信号定义 (观察者模式) ---
# 当净值发生变化时发出 (用于高频更新 UI)
signal equity_updated(equity: float, floating_profit: float)
# 当余额发生变化时发出 (平仓后)
signal balance_updated(balance: float)
# 当订单开仓时发出
signal order_opened(order: OrderData)
# 当订单平仓时发出
signal order_closed(order: OrderData)
# [Stage 4 新增] 订单被修改信号 (专门用于 SL/TP 变更，不会导致 UI 添加重复行)
signal order_modified(order: OrderData)

# --- 账户配置 ---
@export var initial_balance: float = 10000.0
@export var leverage: int = 100 # 杠杆 1:100
# 合约大小 (标准手: 100,000 单位，这里假设模拟外汇)
var contract_size: float = 100000.0 

# --- 内部状态 ---
var _balance: float = 0.0
var _active_orders: Array[OrderData] = []
var _history_orders: Array[OrderData] = []
var _ticket_counter: int = 1 # 订单号生成器

func _ready():
	_balance = initial_balance
	# 初始化时发射一次信号更新 UI
	balance_updated.emit(_balance)
	equity_updated.emit(_balance, 0.0)

# --- 核心交易逻辑 ---

# 开仓 (Open Market Order)
func open_market_order(type: OrderData.Type, lots: float, price: float, time_str: String, sl: float = 0.0, tp: float = 0.0) -> OrderData:
	# 1. 创建订单数据对象
	var ticket = _ticket_counter
	_ticket_counter += 1
	var new_order = OrderData.new(ticket, type, lots, price, time_str)
	new_order.stop_loss = sl
	new_order.take_profit = tp
	
	# 2. 加入活跃列表
	_active_orders.append(new_order)
	
	print(">>> 订单开仓: ", new_order)
	
	# 3. 通知系统
	order_opened.emit(new_order)
	
	# 4. 立即计算一次净值 (扣除点差等逻辑可在未来加入，目前假设0点差)
	update_equity(price)
	
	return new_order

# 平仓 (Close Position)
# 如果 ticket_id 为 -1，则平掉所有持仓
func close_market_order(ticket_id: int, price: float, time_str: String):
	# 倒序遍历，方便删除
	for i in range(_active_orders.size() - 1, -1, -1):
		var order = _active_orders[i]
		
		# 找到目标订单 或 平所有仓
		if ticket_id == -1 or order.ticket_id == ticket_id:
			_finalize_order(order, price, time_str)
			_active_orders.remove_at(i)
			_history_orders.append(order)
			
			order_closed.emit(order)
	
	# 平仓后更新余额
	balance_updated.emit(_balance)
	update_equity(price)

# 内部平仓结算逻辑
func _finalize_order(order: OrderData, close_price: float, close_time: String):
	order.state = OrderData.State.CLOSED
	order.close_price = close_price
	order.close_time = close_time
	
	# 结算利润
	var profit = _calculate_profit(order, close_price)
	order.profit = profit
	
	_balance += profit
	print("<<< 订单平仓: #%d 盈亏: %.2f, 余额: %.2f" % [order.ticket_id, profit, _balance])

# --- 实时计算逻辑 ---

# 在每一根 K 线或 Tick 更新时调用此函数
func update_equity(current_price: float):
	var total_floating_profit = 0.0
	# 倒序遍历，因为可能涉及到平仓删除数组元素
	for i in range(_active_orders.size() - 1, -1, -1):
		var order = _active_orders[i]
		
		# 1. 检查 SL/TP 触发 (模拟撮合)
		var is_closed = _check_sl_tp(order, current_price)
		
		if not is_closed:
			# 2. 如果没平仓，计算浮盈
			var floating = _calculate_profit(order, current_price)
			order.profit = floating
			total_floating_profit += floating
		
	var equity = _balance + total_floating_profit
	equity_updated.emit(equity, total_floating_profit)

# 利润计算核心公式 (MT4 标准算法)
func _calculate_profit(order: OrderData, current_price: float) -> float:
	var diff = 0.0
	if order.type == OrderData.Type.BUY:
		# 多单：(现价 - 开盘价)
		diff = current_price - order.open_price
	else:
		# 空单：(开盘价 - 现价)
		diff = order.open_price - current_price
	
	# 利润 = 价差 * 手数 * 合约单位
	return diff * order.lots * contract_size

# --- 数据获取接口 ---

func get_balance() -> float:
	return _balance

func get_active_orders() -> Array[OrderData]:
	return _active_orders

func get_history_orders() -> Array[OrderData]:
	return _history_orders

# [Stage 4 修复] 修改订单接口 (UI 拖拽松手后调用这里)
func modify_order(ticket_id: int, new_sl: float, new_tp: float):
	for order in _active_orders:
		if order.ticket_id == ticket_id:
			# 只要数据有变化才触发信号
			if not is_equal_approx(order.stop_loss, new_sl) or not is_equal_approx(order.take_profit, new_tp):
				order.stop_loss = new_sl
				order.take_profit = new_tp
				print(">>> 订单修改 #%d: SL=%.5f, TP=%.5f" % [ticket_id, new_sl, new_tp])
				
				# [修复] 之前这里错用了 order_opened，导致 UI 添加重复行
				# 现在改为发射专用信号
				order_modified.emit(order)
			return

# [内部新增] 检查止损止盈
func _check_sl_tp(order: OrderData, current_price: float) -> bool:
	var hit = false
	var close_reason = ""
	
	if order.type == OrderData.Type.BUY:
		# 多单止损：现价 <= SL
		if order.stop_loss > 0 and current_price <= order.stop_loss:
			hit = true; close_reason = "SL"
		# 多单止盈：现价 >= TP
		elif order.take_profit > 0 and current_price >= order.take_profit:
			hit = true; close_reason = "TP"
			
	elif order.type == OrderData.Type.SELL:
		# 空单止损：现价 >= SL
		if order.stop_loss > 0 and current_price >= order.stop_loss:
			hit = true; close_reason = "SL"
		# 空单止盈：现价 <= TP
		elif order.take_profit > 0 and current_price <= order.take_profit:
			hit = true; close_reason = "TP"
	
	if hit:
		print("!!! 触发 %s 平仓 !!!" % close_reason)
		# 获取当前时间字符串
		var t_str = Time.get_datetime_string_from_system().replace("T", " ")
		# 执行平仓，价格按 SL/TP 价还是现价？模拟器通常按触发价(Order Price)或滑点后的现价
		# 这里简单处理：按触发那一刻的 current_price 成交
		close_market_order(order.ticket_id, current_price, t_str)
		return true
		
	return false
