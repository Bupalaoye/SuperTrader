class_name TerminalPanel
extends PanelContainer

# --- 信号 ---
# 当用户双击订单行时发出
signal order_double_clicked(order: OrderData)

# --- 节点引用 ---
@onready var trade_tree: Tree = %TradeTree
@onready var history_tree: Tree = %HistoryTree
@onready var journal_log: RichTextLabel = %JournalLog

# --- 数据源 ---
var _account: AccountManager

# --- 列定义 (方便后续修改) ---
enum TradeCol { TICKET, TIME, TYPE, LOTS, PRICE, SL, TP, PROFIT, MAX }
enum HistCol { TICKET, TIME, TYPE, LOTS, OPEN_PRICE, CLOSE_PRICE, PROFIT, MAX }

func _ready():
	_setup_trade_tree()
	_setup_history_tree()
	
	# [新增] 连接双击信号
	trade_tree.item_activated.connect(_on_tree_item_activated)
	
	log_message("终端系统初始化完成。等待数据...")

# --- 初始化表格结构 ---
func _setup_trade_tree():
	# [新增] 关键布局设置：强制表格填充父容器的高度
	trade_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# [新增] 关键布局设置：允许水平缩放
	trade_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	trade_tree.columns = TradeCol.MAX
	trade_tree.set_column_title(TradeCol.TICKET, "Order")
	trade_tree.set_column_title(TradeCol.TIME, "Time")
	trade_tree.set_column_title(TradeCol.TYPE, "Type")
	trade_tree.set_column_title(TradeCol.LOTS, "Size")
	trade_tree.set_column_title(TradeCol.PRICE, "Price")
	trade_tree.set_column_title(TradeCol.SL, "S / L")
	trade_tree.set_column_title(TradeCol.TP, "T / P")
	trade_tree.set_column_title(TradeCol.PROFIT, "Profit")
	
	# 设置列宽 (可选)
	trade_tree.set_column_custom_minimum_width(TradeCol.TIME, 120)
	trade_tree.set_column_custom_minimum_width(TradeCol.PROFIT, 80)
	
	# 确保根节点存在但不显示
	if not trade_tree.get_root():
		trade_tree.create_item()

func _setup_history_tree():
	# [新增] 同样的设置给历史记录表
	history_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	history_tree.columns = HistCol.MAX
	history_tree.set_column_title(HistCol.TICKET, "Order")
	history_tree.set_column_title(HistCol.TIME, "Time")
	history_tree.set_column_title(HistCol.TYPE, "Type")
	history_tree.set_column_title(HistCol.LOTS, "Size")
	history_tree.set_column_title(HistCol.OPEN_PRICE, "Open")
	history_tree.set_column_title(HistCol.CLOSE_PRICE, "Close")
	history_tree.set_column_title(HistCol.PROFIT, "Profit")
	
	if not history_tree.get_root():
		history_tree.create_item()

# --- 核心连接 ---
func setup(acc: AccountManager):
	_account = acc
	# 连接信号，实现数据驱动 UI
	_account.order_opened.connect(_on_order_opened)
	_account.order_closed.connect(_on_order_closed)
	_account.equity_updated.connect(_on_equity_updated)
	# [Stage 4 新增] 监听修改信号
	_account.order_modified.connect(_on_order_modified)
	
	log_message("账户连接成功。余额: %.2f" % _account.get_balance())

# --- 信号回调 ---

func _on_order_opened(order: OrderData):
	log_message("开仓: #%d %s %.2f" % [order.ticket_id, "BUY" if order.is_bull() else "SELL", order.lots])
	_add_trade_row(order)

func _on_order_closed(order: OrderData):
	log_message("平仓: #%d 盈亏: %.2f" % [order.ticket_id, order.profit])
	# 1. 从 Trade 表格移除
	_remove_trade_row(order.ticket_id)
	# 2. 添加到 History 表格
	_add_history_row(order)

# [Stage 4 新增] 处理拖拽修改后的表格刷新
func _on_order_modified(order: OrderData):
	log_message("订单 #%d 参数变更: SL=%.5f TP=%.5f" % [order.ticket_id, order.stop_loss, order.take_profit])
	
	# 遍历表格找到对应行，只更新 SL 和 TP 列
	var root = trade_tree.get_root()
	var item = root.get_first_child()
	while item:
		var item_order = item.get_metadata(0)
		if item_order and item_order.ticket_id == order.ticket_id:
			item.set_text(TradeCol.SL, "%.5f" % order.stop_loss)
			item.set_text(TradeCol.TP, "%.5f" % order.take_profit)
			break
		item = item.get_next()

func _on_equity_updated(equity: float, floating: float):
	# 这是高频调用 (每一跳)，只更新 Trade 表格的 Profit 列和背景色
	# 避免重绘整个表格，只修改单元格文本
	var root = trade_tree.get_root()
	var item = root.get_first_child()
	
	while item:
		var order: OrderData = item.get_metadata(0) # 这是一个技巧：把数据对象存在 Item 里
		if is_instance_valid(order) and order.state == OrderData.State.OPEN:
			# 刷新利润数值
			item.set_text(TradeCol.PROFIT, "%.2f" % order.profit)
			
			# 颜色反馈
			var color = Color.GREEN if order.profit >= 0 else Color.RED
			item.set_custom_color(TradeCol.PROFIT, color)
			
		item = item.get_next()

# [新增] 双击回调函数
func _on_tree_item_activated():
	var item = trade_tree.get_selected()
	if not item: return
	
	# 获取绑定的订单数据
	var order: OrderData = item.get_metadata(0)
	if order:
		print("双击订单: #", order.ticket_id)
		order_double_clicked.emit(order) # 通知控制器

# --- 表格操作细节 ---

func _add_trade_row(order: OrderData):
	var root = trade_tree.get_root()
	var item = trade_tree.create_item(root)
	
	# 绑定数据对象，方便后续查找
	item.set_metadata(0, order)
	
	# 填充静态数据
	item.set_text(TradeCol.TICKET, str(order.ticket_id))
	item.set_text(TradeCol.TIME, order.open_time)
	
	var type_str = "buy" if order.type == OrderData.Type.BUY else "sell"
	item.set_text(TradeCol.TYPE, type_str)
	var type_color = Color.CORNFLOWER_BLUE if order.type == OrderData.Type.BUY else Color.CORAL
	item.set_custom_color(TradeCol.TYPE, type_color)
	
	item.set_text(TradeCol.LOTS, "%.2f" % order.lots)
	item.set_text(TradeCol.PRICE, "%.5f" % order.open_price)
	item.set_text(TradeCol.SL, "%.5f" % order.stop_loss)
	item.set_text(TradeCol.TP, "%.5f" % order.take_profit)
	item.set_text(TradeCol.PROFIT, "0.00") # 初始为0，立刻会被 update 更新

func _remove_trade_row(ticket_id: int):
	var root = trade_tree.get_root()
	var item = root.get_first_child()
	while item:
		var order = item.get_metadata(0)
		if order and order.ticket_id == ticket_id:
			item.free() # 删除这一行
			return
		item = item.get_next()

func _add_history_row(order: OrderData):
	var root = history_tree.get_root()
	# 历史记录通常插在最前面 (Use index 0)
	var item = history_tree.create_item(root, 0)
	
	item.set_text(HistCol.TICKET, str(order.ticket_id))
	item.set_text(HistCol.TIME, order.close_time) # 历史表显示平仓时间
	
	var type_str = "buy" if order.type == OrderData.Type.BUY else "sell"
	item.set_text(HistCol.TYPE, type_str)
	var type_color = Color.CORNFLOWER_BLUE if order.type == OrderData.Type.BUY else Color.CORAL
	item.set_custom_color(HistCol.TYPE, type_color)
	
	item.set_text(HistCol.LOTS, "%.2f" % order.lots)
	item.set_text(HistCol.OPEN_PRICE, "%.5f" % order.open_price)
	item.set_text(HistCol.CLOSE_PRICE, "%.5f" % order.close_price)
	
	item.set_text(HistCol.PROFIT, "%.2f" % order.profit)
	var profit_color = Color.GREEN if order.profit >= 0 else Color.RED
	item.set_custom_color(HistCol.PROFIT, profit_color)

# --- 日志工具 ---
func log_message(msg: String):
	if journal_log:
		var time = Time.get_time_string_from_system()
		journal_log.append_text("[%s] %s\n" % [time, msg])