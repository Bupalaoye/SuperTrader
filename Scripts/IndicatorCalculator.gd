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
# 对应文档算法 1
static func calculate_ema(data: Array, period: int) -> Array:
	var result = []
	result.resize(data.size())
	result.fill(NAN)
	
	if data.size() < period:
		return result
	
	# 步骤 1: 计算平滑系数 Alpha = 2 / (N + 1)
	var k = 2.0 / (period + 1.0)
	
	# 步骤 2: 初始化
	# 第一根 EMA 通常用 SMA 作为起点，或者直接用 Price。
	# 为了稳定，我们在 period-1 处计算一个 SMA 作为种子。
	var sum_val = 0.0
	for i in range(period):
		sum_val += data[i]
	var initial_sma = sum_val / period
	
	result[period - 1] = initial_sma
	
	# 步骤 3: 递归计算
	# EMA_t = (Close_t * k) + (EMA_prev * (1 - k))
	for i in range(period, data.size()):
		var close_t = data[i]
		var ema_prev = result[i - 1]
		
		# 极速公式
		var ema_t = (close_t * k) + (ema_prev * (1.0 - k))
		result[i] = ema_t
		
	return result

# ==========================================
# 2. MACD (动能指标)
# ==========================================
# 对应文档算法 2
static func calculate_macd(data: Array, fast_p: int = 12, slow_p: int = 26, signal_p: int = 9) -> Dictionary:
	# 1. 计算快慢线
	var ema_fast = calculate_ema(data, fast_p)
	var ema_slow = calculate_ema(data, slow_p)
	
	var dif = []
	dif.resize(data.size())
	dif.fill(NAN)
	
	var valid_dif_data = [] # 用于计算 Signal 线的纯净数据
	var diff_start_index = slow_p - 1 # 慢线出来后才有 DIFF
	
	for i in range(data.size()):
		if i >= diff_start_index:
			var val = ema_fast[i] - ema_slow[i]
			dif[i] = val
			valid_dif_data.append(val)
	
	# 2. 计算 DEA (Signal Line) - 即对 DIF 进行 EMA
	if valid_dif_data.size() < signal_p:
		# 数据不足
		return {"dif": dif, "dea": dif, "hist": dif} # 返回全NAN数组
		
	var dea_raw = calculate_ema(valid_dif_data, signal_p)
	
	# 将 DEA 对齐回原始数组长度
	var dea = []
	dea.resize(data.size())
	dea.fill(NAN)
	
	# 3. 计算柱状图 (Histogram = (DIF - DEA) * 2)
	var hist = []
	hist.resize(data.size())
	hist.fill(NAN)
	
	# 对齐逻辑：DEA 的第0个数据 对应的是 valid_dif_data 的第0个
	# 而 valid_dif_data 的第0个 对应的是 data 的 diff_start_index
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
# 对应文档算法 3 - 使用 Wilder's Smoothing
static func calculate_rsi(data: Array, period: int = 14) -> Array:
	var result = []
	result.resize(data.size())
	result.fill(NAN)
	
	if data.size() <= period:
		return result
	
	var gain_sum = 0.0
	var loss_sum = 0.0
	
	# 1. 初始平均值 (使用简单平均 SMA 作为第一个 Wilder 平滑值)
	for i in range(1, period + 1):
		var change = data[i] - data[i-1]
		if change > 0:
			gain_sum += change
		else:
			loss_sum += abs(change)
			
	var avg_gain = gain_sum / period
	var avg_loss = loss_sum / period
	
	# 计算第一个点的 RSI
	result[period] = 100.0 - (100.0 / (1.0 + (avg_gain / max(avg_loss, 0.0000001))))
	
	# 2. Wilder's Smoothing 递归
	# Formula: NewAvg = (PrevAvg * (N-1) + Current) / N
	for i in range(period + 1, data.size()):
		var change = data[i] - data[i-1]
		var current_gain = change if change > 0 else 0.0
		var current_loss = abs(change) if change < 0 else 0.0
		
		avg_gain = ((avg_gain * (period - 1)) + current_gain) / period
		avg_loss = ((avg_loss * (period - 1)) + current_loss) / period
		
		# 相除保护
		if avg_loss == 0:
			result[i] = 100.0
		else:
			var rs = avg_gain / avg_loss
			result[i] = 100.0 - (100.0 / (1.0 + rs))
			
	return result

# ==========================================
# 4. 布林带 (Bollinger Bands)
# ==========================================
# 对应文档算法 4
static func calculate_bollinger_bands(data: Array, period: int = 20, multiplier: float = 2.0) -> Dictionary:
	# 1. 计算中轨 (MB) = SMA
	var mb = calculate_sma(data, period)
	
	var ub = [] # 上轨
	var lb = [] # 下轨
	ub.resize(data.size()); ub.fill(NAN)
	lb.resize(data.size()); lb.fill(NAN)
	
	# 2. 计算标准差并生成轨道
	for i in range(period - 1, data.size()):
		var mean = mb[i]
		if is_nan(mean): continue
		
		# 计算过去 N 个价格与均值的方差和
		var sum_sq_diff = 0.0
		for j in range(period):
			var diff = data[i - j] - mean
			sum_sq_diff += diff * diff
			
		var variance = sum_sq_diff / period
		var std_dev = sqrt(variance)
		
		ub[i] = mean + (multiplier * std_dev)
		lb[i] = mean - (multiplier * std_dev)
		
	return {"ub": ub, "mb": mb, "lb": lb}

# ==========================================
# 5. ATR (真实波动幅度均值)
# ==========================================
# 对应文档算法 5
# 注意：需要完整的 Open, High, Low, Close 结构数组，而非单一直数组
static func calculate_atr(candles: Array, period: int = 14) -> Array:
	var result = []
	result.resize(candles.size())
	result.fill(NAN)
	
	if candles.size() <= period:
		return result
		
	# 1. 计算 True Range (TR) 序列
	var tr_list = []
	tr_list.resize(candles.size())
	
	# 第一根 K 线的 TR 通常就是 H - L
	tr_list[0] = candles[0].h - candles[0].l
	
	for i in range(1, candles.size()):
		var h = candles[i].h
		var l = candles[i].l
		var prev_c = candles[i-1].c
		
		var val1 = h - l
		var val2 = abs(h - prev_c)
		var val3 = abs(l - prev_c)
		
		tr_list[i] = max(val1, max(val2, val3))
		
	# 2. 对 TR 进行移动平均 (通常 ATR 用 RMA/Wilder's，这里用 SMA 即可满足普通回测，如果要严谨按 RSI 方式写)
	# 文档提到：MA(TR, N)，默认可以用 SMA
	# 但专业的 ATR 实际上是 Wilder's Smoothing。这里我们复用类似 RSI 的平滑逻辑：
	
	# 初始化：前 N 个 TR 的 SMA
	var sum_tr = 0.0
	for i in range(period):
		sum_tr += tr_list[i]
	
	var val_atr = sum_tr / period
	result[period - 1] = val_atr
	
	# 后续：ATR_t = (ATR_{t-1} * (N-1) + TR_t) / N
	for i in range(period, candles.size()):
		var current_tr = tr_list[i]
		val_atr = ((val_atr * (period - 1)) + current_tr) / float(period)
		result[i] = val_atr
		
	return result

# ==========================================
# 6. 分型 (Fractals) - Swing High/Low
# ==========================================
# 对应文档算法 6
# 返回字典：{"highs": Map<Time, Price>, "lows": Map<Time, Price>}
# Map 的 Key 是 K 线索引 (int)，Value 是价格
static func calculate_fractals(candles: Array) -> Dictionary:
	var swing_highs = {} # key: index, value: price
	var swing_lows = {}
	
	if candles.size() < 5:
		return {"highs": swing_highs, "lows": swing_lows}
	
	# 必须从第 2 根遍历到倒数第 2 根 (0, 1, [2]... [N-3], N-2, N-1)
	for i in range(2, candles.size() - 2):
		var curr = candles[i]
		
		# 1. 顶分型判断 (Swing High)
		# 中间 > 左1, 左2 且 中间 > 右1, 右2
		if curr.h > candles[i-1].h and curr.h > candles[i-2].h and \
		   curr.h > candles[i+1].h and curr.h > candles[i+2].h:
			swing_highs[i] = curr.h
			
		# 2. 底分型判断 (Swing Low)
		# 中间 < 左1, 左2 且 中间 < 右1, 右2
		if curr.l < candles[i-1].l and curr.l < candles[i-2].l and \
		   curr.l < candles[i+1].l and curr.l < candles[i+2].l:
			swing_lows[i] = curr.l
			
	return {"highs": swing_highs, "lows": swing_lows}