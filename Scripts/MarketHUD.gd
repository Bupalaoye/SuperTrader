class_name MarketHUD
extends PanelContainer

# --- UI 节点 ---
var _lbl_trend: Label
var _lbl_stat: Label
var _lbl_atr: Label
var _lbl_bb_info: Label

func _init():
	# 1. 样式设置 (左上角半透明悬浮窗)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6) # 半透明黑
	style.corner_radius_bottom_right = 10
	add_theme_stylebox_override("panel", style)
	
	# 自适应布局
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# 2. 内容组件
	var title = Label.new()
	title.text = "MARKET STATUS"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color.GRAY)
	vbox.add_child(title)
	
	_lbl_trend = Label.new()
	_lbl_trend.text = "TREND: WAITING..."
	_lbl_trend.add_theme_font_size_override("font_size", 18) # 稍微加大
	_lbl_trend.add_theme_constant_override("outline_size", 2) # 加描边
	vbox.add_child(_lbl_trend)
	
	_lbl_stat = Label.new()
	_lbl_stat.text = "RSI: --"
	vbox.add_child(_lbl_stat)
	
	_lbl_atr = Label.new()
	_lbl_atr.text = "ATR: -- (Risk: --)"
	vbox.add_child(_lbl_atr)
	
	# [新增]
	_lbl_bb_info = Label.new()
	_lbl_bb_info.text = "BB: (20, 2.0)"
	_lbl_bb_info.add_theme_color_override("font_color", Color.CYAN) #用青色呼应线
	vbox.add_child(_lbl_bb_info)

# --- 公开接口 ---
# [新增] 趋势过滤函数 (专用于显示 EMA 200 比对结果)
func update_trend_filter(price: float, ema_val: float):
	if is_nan(ema_val) or ema_val == 0:
		_lbl_trend.text = "TREND: WAITING DATA..."
		_lbl_trend.modulate = Color.GRAY
		return

	var diff = price - ema_val
	
	# 核心逻辑：价格 > EMA = 只做多；价格 < EMA = 只做空
	if diff > 0:
		# 绿色 (UPTREND)
		_lbl_trend.text = "🟢 UPTREND (ONLY BUY)\nEMA: %.5f" % ema_val
		_lbl_trend.modulate = Color(0.2, 1.0, 0.4) # 亮绿
	else:
		# 红色 (DOWNTREND)
		_lbl_trend.text = "🔴 DOWNTREND (ONLY SELL)\nEMA: %.5f" % ema_val
		_lbl_trend.modulate = Color(1.0, 0.3, 0.3) # 亮红

# [新增] 震荡指标更新函数 (专用于 RSI 和 ATR)
func update_status_indicators(rsi_val: float, atr_val: float):
	# 2. 更新 RSI
	var rsi_status = "NEUTRAL"
	var rsi_col = Color.WHITE
	if rsi_val > 70: 
		rsi_status = "OVERBOUGHT"
		rsi_col = Color.ORANGE
	elif rsi_val < 30: 
		rsi_status = "OVERSOLD"
		rsi_col = Color.CYAN
	
	_lbl_stat.text = "RSI(14): %.1f [%s]" % [rsi_val, rsi_status]
	_lbl_stat.modulate = rsi_col
	
	# 3. 更新 ATR
	var pips = atr_val * 10000.0
	_lbl_atr.text = "ATR(14): %.5f (~%d pips)" % [atr_val, pips]

# [兼容] 原有的 update_status 函数 (为了向后兼容，保留但不再使用)
func update_status(trend_str: String, rsi_val: float, atr_val: float, price: float):
	_lbl_trend.text = "TREND: " + trend_str
	if trend_str == "BULLISH":
		_lbl_trend.modulate = Color.GREEN
	elif trend_str == "BEARISH":
		_lbl_trend.modulate = Color.RED
	else:
		_lbl_trend.modulate = Color.WHITE
	update_status_indicators(rsi_val, atr_val)

# --- BB 配置信息显示 ---
func update_bb_info(period: int, k: float):
	if _lbl_bb_info:
		_lbl_bb_info.text = "BB Settings: (%d, %.1f)" % [period, k]


# [NEW] 设置策略名称标签
func set_strategy_label(text: String):
	if _lbl_bb_info:
		_lbl_bb_info.text = text
		_lbl_bb_info.modulate = Color.CYAN


# [NEW] 通用趋势更新接口
func update_trend_text(text: String, color: Color):
	_lbl_trend.text = text
	_lbl_trend.modulate = color
