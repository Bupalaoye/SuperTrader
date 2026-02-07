class_name IndicatorCalculator
extends RefCounted

# ==========================================
# 1. 基础均线系统 (EMA & SMA)
# ==========================================

# 简单移动平均 (SMA) - 用于布林带中轨
static func calculate_sma(data: Array, period: int) -> Array:
	var result = []
	result.resize(data.size())
	result.fill(NAN) # 填充无效值
	
	if data.size() < period:
		return result
		
	var sum_val = 0.0
	
	# 预先计算第一个窗口
	for i in range(period):
		sum_val += data[i]
	
	result[period - 1] = sum_val / float(period)
	
	# 滑动窗口计算后续
	for i in range(period, data.size()):
		sum_val += data[i] # 加上新的
		sum_val -= data[i - period] # 减去旧的
		result[i] = sum_val / float(period)
		
	return result

# 指数移动平均 (EMA) - 递归算法
static func calculate_ema(data: Array, period: int) -> Array:
	var result = []
	result.resize(data.size())
	result.fill(NAN)
	
	if data.size() < period:
		return result
	
	var k = 2.0 / (period + 1.0)
	
	var sum_val = 0.0
	for i in range(period):
		sum_val += data[i]
	var initial_sma = sum_val / period
	
	result[period - 1] = initial_sma
	
	for i in range(period, data.size()):
		var close_t = data[i]
		var ema_prev = result[i - 1]
		var ema_t = (close_t * k) + (ema_prev * (1.0 - k))
		result[i] = ema_t
		
	return result

# ==========================================
# 2. MACD (动能指标)
# ==========================================
static func calculate_macd(data: Array, fast_p: int = 12, slow_p: int = 26, signal_p: int = 9) -> Dictionary:
	var ema_fast = calculate_ema(data, fast_p)
	var ema_slow = calculate_ema(data, slow_p)
	
	var dif = []
	dif.resize(data.size())
	dif.fill(NAN)
	
	var valid_dif_data = [] 
	var diff_start_index = slow_p - 1 
	
	for i in range(data.size()):
		if i >= diff_start_index:
			var val = ema_fast[i] - ema_slow[i]
			dif[i] = val
			valid_dif_data.append(val)
	
	if valid_dif_data.size() < signal_p:
		return {"dif": dif, "dea": dif, "hist": dif} 
		
	var dea_raw = calculate_ema(valid_dif_data, signal_p)
	
	var dea = []
	dea.resize(data.size())
	dea.fill(NAN)
	
	var hist = []
	hist.resize(data.size())
	hist.fill(NAN)
	
	for i in range(dea_raw.size()):
		var real_index = diff_start_index + i
		var d = dea_raw[i]
		
		if not is_nan(d):
			dea[real_index] = d
			hist[real_index] = (dif[real_index] - d) * 2.0
			
	return {
		"dif": dif,
		"dea": dea,
		"hist": hist
	}

# ==========================================
# 3. RSI (相对强弱指标)
# ==========================================
static func calculate_rsi(data: Array, period: int = 14) -> Array:
	var result = []
	result.resize(data.size())
	result.fill(NAN)
	
	if data.size() <= period:
		return result
	
	var gain_sum = 0.0
	var loss_sum = 0.0
	
	for i in range(1, period + 1):
		var change = data[i] - data[i-1]
		if change > 0:
			gain_sum += change
		else:
			loss_sum += abs(change)
			
	var avg_gain = gain_sum / period
	var avg_loss = loss_sum / period
	
	result[period] = 100.0 - (100.0 / (1.0 + (avg_gain / max(avg_loss, 0.0000001))))
	
	for i in range(period + 1, data.size()):
		var change = data[i] - data[i-1]
		var current_gain = change if change > 0 else 0.0
		var current_loss = abs(change) if change < 0 else 0.0
		
		avg_gain = ((avg_gain * (period - 1)) + current_gain) / period
		avg_loss = ((avg_loss * (period - 1)) + current_loss) / period
		
		if avg_loss == 0:
			result[i] = 100.0
		else:
			var rs = avg_gain / avg_loss
			result[i] = 100.0 - (100.0 / (1.0 + rs))
			
	return result

# ==========================================
# 4. 布林带 (Bollinger Bands) - 全量计算
# ==========================================
static func calculate_bollinger_bands(data: Array, period: int = 20, multiplier: float = 2.0) -> Dictionary:
	var mb = calculate_sma(data, period)
	
	var ub = [] 
	var lb = [] 
	ub.resize(data.size()); ub.fill(NAN)
	lb.resize(data.size()); lb.fill(NAN)
	
	for i in range(period - 1, data.size()):
		var mean = mb[i]
		if is_nan(mean): continue
		
		var sum_sq_diff = 0.0
		for j in range(period):
			var diff = data[i - j] - mean
			sum_sq_diff += diff * diff
		
		# [关键参数调整点]
		# 目前使用总体标准差: variance = sum_sq_diff / period
		# 如果你觉得上下轨线太窄，可以改成样本标准差（MT4/TradingView常用）：
		# var variance = sum_sq_diff / float(max(1, period - 1))
		var variance = sum_sq_diff / period
		var std_dev = sqrt(variance)
		
		ub[i] = mean + (multiplier * std_dev)
		lb[i] = mean - (multiplier * std_dev)
		
	return {"ub": ub, "mb": mb, "lb": lb}

# ==========================================
# 5. ATR (真实波动幅度均值)
# ==========================================
static func calculate_atr(candles: Array, period: int = 14) -> Array:
	var result = []
	result.resize(candles.size())
	result.fill(NAN)
	
	if candles.size() <= period:
		return result
		
	var tr_list = []
	tr_list.resize(candles.size())
	
	tr_list[0] = candles[0].h - candles[0].l
	
	for i in range(1, candles.size()):
		var h = candles[i].h
		var l = candles[i].l
		var prev_c = candles[i-1].c
		
		var val1 = h - l
		var val2 = abs(h - prev_c)
		var val3 = abs(l - prev_c)
		
		tr_list[i] = max(val1, max(val2, val3))
		
	var sum_tr = 0.0
	for i in range(period):
		sum_tr += tr_list[i]
	
	var val_atr = sum_tr / period
	result[period - 1] = val_atr
	
	for i in range(period, candles.size()):
		var current_tr = tr_list[i]
		val_atr = ((val_atr * (period - 1)) + current_tr) / float(period)
		result[i] = val_atr
		
	return result

# ==========================================
# 6. 分型 (Fractals)
# ==========================================
static func calculate_fractals(candles: Array) -> Dictionary:
	var swing_highs = {} # key: index, value: price
	var swing_lows = {}
	
	if candles.size() < 5:
		return {"highs": swing_highs, "lows": swing_lows}
	
	# 必须从第 2 根遍历到倒数第 2 根
	for i in range(2, candles.size() - 2):
		var curr = candles[i]
		
		# 顶分型
		if curr.h > candles[i-1].h and curr.h > candles[i-2].h and \
		   curr.h > candles[i+1].h and curr.h > candles[i+2].h:
			swing_highs[i] = curr.h
			
		# 底分型
		if curr.l < candles[i-1].l and curr.l < candles[i-2].l and \
		   curr.l < candles[i+1].l and curr.l < candles[i+2].l:
			swing_lows[i] = curr.l
			
	return {"highs": swing_highs, "lows": swing_lows}

# ==========================================
# 7. 单点布林带增量计算 (极致优化 - 新增)
# ==========================================
# 注意：此函数必须独立于其他函数之外
static func calculate_bollinger_at_index(closes: Array, index: int, period: int, k: float) -> Dictionary:
	# 边界检查
	if index < period - 1 or index >= closes.size():
		return { "ub": NAN, "mb": NAN, "lb": NAN }

	var sum_val = 0.0
	# 只遍历最近 period 个收盘价
	for i in range(period):
		sum_val += closes[index - i]

	var mb = sum_val / float(period)

	var sum_sq_diff = 0.0
	for i in range(period):
		var diff = closes[index - i] - mb
		sum_sq_diff += diff * diff

	var std_dev = sqrt(sum_sq_diff / float(period))

	return {
		"mb": mb,
		"ub": mb + (k * std_dev),
		"lb": mb - (k * std_dev)
	}


# ==========================================
# 8. [NEW] 34 EMA Channel (High/Low/Close) - 全量计算
# ==========================================
static func calculate_ema_channel(candles: Array, period: int) -> Dictionary:
	var size = candles.size()
	var ub_list = []
	ub_list.resize(size)
	ub_list.fill(NAN) # High EMA
	var lb_list = []
	lb_list.resize(size)
	lb_list.fill(NAN) # Low EMA
	var mb_list = []
	mb_list.resize(size)
	mb_list.fill(NAN) # Close EMA (Trend)

	if size < period:
		return {"ub": ub_list, "mb": mb_list, "lb": lb_list}

	# 1. 提取基础数据数组
	var highs = []
	var lows = []
	var closes = []
	highs.resize(size)
	lows.resize(size)
	closes.resize(size)

	for i in range(size):
		highs[i] = candles[i].h
		lows[i] = candles[i].l
		closes[i] = candles[i].c

	# 2. 复用已有的 EMA 算法分别计算
	ub_list = calculate_ema(highs, period)
	lb_list = calculate_ema(lows, period)
	mb_list = calculate_ema(closes, period)

	return {"ub": ub_list, "mb": mb_list, "lb": lb_list}


# ==========================================
# 9. [NEW] 34 EMA Channel - 单点增量计算 (实时性能优化)
# ==========================================
# ub_prev, lb_prev, mb_prev: 上一根K线的指标值
static func calculate_ema_channel_at_index(candle: Dictionary, ub_prev: float, lb_prev: float, mb_prev: float, period: int) -> Dictionary:
	# 如果前值为 NAN，无法进行递归计算，返回 NAN
	if is_nan(ub_prev) or is_nan(lb_prev) or is_nan(mb_prev):
		return { "ub": NAN, "mb": NAN, "lb": NAN }

	# EMA 乘数公式: 2 / (N + 1)
	var k = 2.0 / (float(period) + 1.0)

	# EMA = (Price - Prev) * k + Prev
	# 分别对应 High, Low, Close
	var new_ub = (candle.h - ub_prev) * k + ub_prev
	var new_lb = (candle.l - lb_prev) * k + lb_prev
	var new_mb = (candle.c - mb_prev) * k + mb_prev

	return { "ub": new_ub, "mb": new_mb, "lb": new_lb }