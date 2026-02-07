@tool
class_name IndicatorEMA extends ChartIndicator

@export_group("EMA 参数")
@export var period: int = 200: # 周期，默认200，策划可以改成 50, 20
	set(value):
		period = max(1, value) # 最少1个周期
		emit_changed() # 参数变了，通知重绘

func _init() -> void:
	indicator_name = "EMA"
	color = Color(1, 0.6, 0.2) # 默认一种橘黄色

# 重写计算逻辑
func calculate(kline_data: Array) -> void:
	super.calculate(kline_data) 
	
	if kline_data.size() == 0:
		return
		
	var ema_values = []
	var multiplier = 2.0 / (period + 1.0)
	
	# 简单的 EMA 算法示例
	var prev_ema = 0.0
	
	for i in range(kline_data.size()):
		# 假设 kline_data[i] 是一个字典或对象，包含 'close' 属性
		# 根据你的实际数据结构调整: kline_data[i].close 或 kline_data[i]["close"]
		var close_price = kline_data[i]["c"] # SuperTrader 使用 "c" 表示 close
		
		var current_ema = 0.0
		if i == 0:
			current_ema = close_price # 第一根线简单处理
		else:
			# EMA = (Close - PrevEMA) * Multiplier + PrevEMA
			current_ema = (close_price - prev_ema) * multiplier + prev_ema
		
		# 将计算结果存入缓存，如果 i < period 其实数据是不准的，可视情况处理
		ema_values.append(current_ema)
		prev_ema = current_ema
		
	_cache_data = ema_values

# 重写绘制逻辑
func draw(control: Control, transform_func: Callable, start_index: int, end_index: int) -> void:
	if not is_visible or _cache_data.size() == 0:
		return
		
	# 只需要绘制当前视图可见范围内的线段
	var points: PackedVector2Array = []
	
	# 限制循环范围，防止越界
	var loop_start = max(0, start_index)
	var loop_end = min(_cache_data.size(), end_index + 1)
	
	for i in range(loop_start, loop_end):
		var price_val = _cache_data[i]
		# 核心：调用主图表传来的"坐标转换函数"
		# 只要告诉它第几个点(i)，数值是多少(price_val)，它就会返回屏幕坐标
		var screen_pos = transform_func.call(i, price_val)
		points.append(screen_pos)
	
	# 绘制折线
	if points.size() > 1:
		control.draw_polyline(points, color, line_width, true)

# 增量计算优化版本 (仅计算最后一个新值)
func calculate_incremental(kline_data: Array, last_index: int) -> void:
	# 如果缓存为空或不完整，进行全量计算
	if _cache_data.size() != last_index:
		calculate(kline_data)
		return
	
	# 缓存已经包含了前面的所有值，只需要计算最后一个
	if kline_data.size() == 0:
		return
	
	var multiplier = 2.0 / (period + 1.0)
	var prev_ema = _cache_data[last_index - 1] if last_index > 0 else 0.0
	var close_price = kline_data[last_index]["c"]
	
	var current_ema = 0.0
	if last_index == 0:
		current_ema = close_price
	else:
		current_ema = (close_price - prev_ema) * multiplier + prev_ema
	
	_cache_data.append(current_ema)

