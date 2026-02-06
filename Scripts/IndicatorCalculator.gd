class_name IndicatorCalculator
extends RefCounted

# --- 移动平均线 (SMA) ---
# data: 输入的 float 数组 (通常是收盘价)
# period: 周期 (如 14)
# return: 输出的 float 数组 (长度与 data 一致，前面不足周期的部分补 0.0 或 NAN)
static func calculate_sma(data: Array, period: int) -> Array:
	var result = []
	var sum = 0.0
	
	for i in range(data.size()):
		var val = data[i]
		sum += val
		
		if i >= period:
			sum -= data[i - period]
		
		if i >= period - 1:
			result.append(sum / float(period))
		else:
			result.append(NAN) # 标记无效数据
			
	return result

# --- 指数移动平均线 (EMA) ---
# 公式: EMA_today = (Price_today * k) + (EMA_prev * (1 - k)), k = 2 / (N + 1)
static func calculate_ema(data: Array, period: int) -> Array:
	var result = []
	var mult = 2.0 / (period + 1.0)
	
	for i in range(data.size()):
		if i < period - 1:
			result.append(NAN)
		elif i == period - 1:
			# 第一根 EMA 通常用 SMA 代替，或者直接用当前价
			var sum = 0.0
			for j in range(period):
				sum += data[j]
			result.append(sum / period)
		else:
			var prev_ema = result[i - 1]
			var curr_val = data[i]
			var ema = (curr_val - prev_ema) * mult + prev_ema
			result.append(ema)
			
	return result

# --- MACD ---
# 标准参数: fast=12, slow=26, signal=9
# 返回: Dictionary {"macd": [], "signal": [], "hist": []}
static func calculate_macd(data: Array, fast_p: int = 12, slow_p: int = 26, signal_p: int = 9) -> Dictionary:
	var ema_fast = calculate_ema(data, fast_p)
	var ema_slow = calculate_ema(data, slow_p)
	
	var macd_line = []
	var valid_start_idx = -1
	
	# 1. 计算 DIF (快线 - 慢线)
	for i in range(data.size()):
		var v1 = ema_fast[i]
		var v2 = ema_slow[i]
		
		if is_nan(v1) or is_nan(v2):
			macd_line.append(NAN)
		else:
			macd_line.append(v1 - v2)
			
	# 2. 计算 DEA (Signal Line, 即 DIF 的 EMA)
	# 需要先把 macd_line 里的 NAN 去掉或者跳过处理，为了简单，我们用辅助函数
	# 这里简化处理：构造一个这就去掉了前置 NAN 的数组传给 EMA
	var temp_macd_values = []
	var offset = 0
	for v in macd_line:
		if not is_nan(v):
			temp_macd_values.append(v)
		else:
			offset += 1
			
	var signal_line_raw = calculate_ema(temp_macd_values, signal_p)
	
	# 把 Signal Line 对齐回原始长度
	var signal_line = []
	for k in range(offset):
		signal_line.append(NAN)
	signal_line.append_array(signal_line_raw)
	
	# 3. 计算 Histogram (柱状图)
	var hist_line = []
	for i in range(data.size()):
		var m = macd_line[i]
		var s = signal_line[i]
		if is_nan(m) or is_nan(s):
			hist_line.append(NAN)
		else:
			hist_line.append(m - s)
			
	return {
		"macd": macd_line,
		"signal": signal_line,
		"hist": hist_line
	}