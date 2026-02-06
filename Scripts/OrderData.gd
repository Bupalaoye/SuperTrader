class_name OrderData
extends RefCounted

# --- 枚举定义 (严谨的类型控制) ---

# 订单方向类型
enum Type {
	BUY = 0,
	SELL = 1
}

# 订单当前状态
enum State {
	OPEN,   # 持仓中
	CLOSED, # 已平仓
	PENDING # 挂单 (预留未来功能)
}

# --- 核心属性 (完全对应 MT4 结构) ---

# 唯一标识符 (类似于数据库主键)
var ticket_id: int = 0

# 订单类型: OrderData.Type.BUY 或 OrderData.Type.SELL
var type: Type = Type.BUY

# 订单状态 (默认为持仓中)
var state: State = State.OPEN

# 手数 (例如 1.0, 0.1, 0.01)
var lots: float = 0.0

# --- 价格与时间 ---

# 开仓价格
var open_price: float = 0.0

# 开仓时间 (建议存储字符串 "YYYY.MM.DD HH:MM" 或 Unix时间戳，根据你 CSV 的 't' 字段保持一致)
var open_time: String = ""

# 止损价格 (0.0 代表无止损)
var stop_loss: float = 0.0

# 止盈价格 (0.0 代表无止盈)
var take_profit: float = 0.0

# 平仓价格 (平仓前通常该值为 0.0 或等于当前价)
var close_price: float = 0.0

# 平仓时间
var close_time: String = ""

# --- 财务结算 ---

# 手续费 (通常为负数，表示扣除)
var commission: float = 0.0

# 库存费/隔夜利息 (Swap)
var swap: float = 0.0

# 最终盈亏 (不包含手续费和库存费的纯盈亏，或根据需求包含)
var profit: float = 0.0

# 注释/备注 (复盘时写的笔记)
var comment: String = ""

# --- 初始化构造函数 ---

func _init(p_ticket: int, p_type: Type, p_lots: float, p_price: float, p_time: String):
	ticket_id = p_ticket
	type = p_type
	lots = p_lots
	open_price = p_price
	open_time = p_time
	state = State.OPEN
	
	# 初始化默认值
	stop_loss = 0.0
	take_profit = 0.0
	profit = 0.0
	commission = 0.0
	swap = 0.0

# --- 辅助方法 ---

# 快速判断是否是多单
func is_bull() -> bool:
	return type == Type.BUY

# 打印方便调试的信息
func _to_string() -> String:
	var type_str = "BUY" if type == Type.BUY else "SELL"
	var state_str = "OPEN" if state == State.OPEN else "CLOSED"
	return "[Order #%d] %s %s %.2f lots @ %.5f | Profit: %.2f" % [ticket_id, state_str, type_str, lots, open_price, profit]
