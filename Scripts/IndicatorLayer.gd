class_name IndicatorLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _indicators: Array[Dictionary] = [] 

func setup(chart: KLineChart):
	_chart = chart
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# [新增/兼容] 更新布林带数据
func update_band_indicator(key: String, data_dict: Dictionary, color: Color, width: float = 1.5):
	# 1. 查找是否存在同名指标，存在则更新
	for i in range(_indicators.size()):
		if _indicators[i].has("key") and _indicators[i]["key"] == key:
			_indicators[i]["data"] = data_dict
			_indicators[i]["color"] = color
			_indicators[i]["width"] = width
			queue_redraw()
			return

	# 2. 不存在则新增
	_indicators.append({
		"key": key,
		"type": "Band",
		"data": data_dict,
		"color": color,
		"width": width
	})
	queue_redraw()

# [兼容旧接口]
func add_line_indicator(data_array: Array, color: Color, width: float = 1.0):
	_indicators.append({ "type": "Line", "data": data_array, "color": color, "width": width })
	queue_redraw()

# [兼容旧接口] 
func add_band_indicator(data_dict: Dictionary, color: Color, width: float = 1.0):
	# 没名字就随机生成一个
	var random_key = "Band_" + str(randi())
	update_band_indicator(random_key, data_dict, color, width)

# [兼容旧接口] 添加标记
func add_marker_indicator(data_map: Dictionary, color: Color, is_up_arrow: bool):
	_indicators.append({
		"type": "Marker",
		"data": data_map,
		"color": color,
		"is_up": is_up_arrow,
		"width": 1.0
	})
	queue_redraw()

func clear_indicators():
	_indicators.clear()
	queue_redraw()

func _draw():
	if not _chart or _indicators.is_empty(): return
	
	# 获取当前可视区域索引，稍微多画两根以防边缘断裂
	var start_idx = max(0, _chart.get_first_visible_index() - 2)
	var end_idx = min(_chart.get_last_visible_index() + 2, 999999)
	
	for ind in _indicators:
		if ind.type == "Line":
			_draw_simple_line(ind, start_idx, end_idx)
		elif ind.type == "Band":
			_draw_band_channel(ind, start_idx, end_idx)
		elif ind.type == "Marker":
			_draw_markers(ind, start_idx, end_idx)

# --- 核心修复：三青线绘制逻辑 ---
func _draw_band_channel(ind: Dictionary, start: int, end: int):
	# 获取数据 (如果没有该key，返回空数组)
	var ub = ind.data.get("ub", [])
	var lb = ind.data.get("lb", [])
	var mb = ind.data.get("mb", [])
	
	# 颜色处理：强制完全不透明
	var line_color = ind.color
	line_color.a = 1.0 
	
	# 线宽：默认稍微加粗一点
	var w = ind.get("width", 1.5)

	# [BUG 修复点] 之前这里写了 if ub.is_empty(): return
	# 导致 EMA 200 (只有 mb 没有 ub) 直接被跳过不画
	# 现在的逻辑是：只要三个轨道里有任意一个有数据，就可以继续
	if ub.is_empty() and lb.is_empty() and mb.is_empty():
		return
	
	# 确定绘制范围
	# 注意：为了安全，我们要取现有数据的最大索引
	var max_idx = 0
	if not ub.is_empty(): max_idx = ub.size() - 1
	elif not mb.is_empty(): max_idx = mb.size() - 1 # 如果只有 MB，以 MB 为准
	
	var safe_end = min(end, max_idx)
	if safe_end <= start: return

	# 绘制 (判断非空才画)
	if not ub.is_empty(): _draw_solid_line(ub, start, safe_end, line_color, w)
	if not lb.is_empty(): _draw_solid_line(lb, start, safe_end, line_color, w)
	# EMA 200 主要靠这行画出来：
	if not mb.is_empty(): _draw_solid_line(mb, start, safe_end, line_color, w)

# --- 通用画线函数 (Solid Line) ---
func _draw_solid_line(data: Array, start: int, end: int, col: Color, w: float):
	var points = PackedVector2Array()
	
	# 1. 扩宽绘制范围
	# 前后多画 1 根，保证线段连接到屏幕外，而不是在屏幕边缘断开
	var safe_start = start - 1
	var safe_end = end + 1
	
	for i in range(safe_start, safe_end + 1):
		# 2. 严格的边界检查
		if i < 0 or i >= data.size(): 
			continue
		
		var val = data[i]
		
		# 3. [关键修复] 处理 NAN (无效值)
		# 如果遇到无效数据（例如 MA(20) 的前19个点），必须断开线条
		if is_nan(val):
			if points.size() > 1:
				draw_polyline(points, col, w, true) # 画出之前的段落
			points.clear() # 清空点集，准备下一段
			continue
		
		# 4. [核心] 获取坐标 - 此时 _chart 内部已经锁定了 start_index，绝对对齐
		var x = _chart.get_x_by_index_public(i)
		var y = _chart.map_price_to_y_public(val)
		
		# 5. 防御性检查：防止 Y 轴爆出离谱的值 (比如除以0导致 INF)
		if is_inf(x) or is_nan(x) or is_inf(y) or is_nan(y):
			continue
			
		points.append(Vector2(x, y))
	
	# 画最后剩余的一段
	if points.size() > 1:
		draw_polyline(points, col, w, true)

# --- 绘制普通单线 (Line指标用) ---
func _draw_simple_line(ind: Dictionary, start: int, end: int):
	_draw_solid_line(ind.data, start, min(end, ind.data.size()-1), ind.color, ind.width)

# --- 绘制箭头标记 (Fractals用) ---
func _draw_markers(ind: Dictionary, start: int, end: int):
	var data_map = ind.data
	var color = ind.color
	var is_up = ind.is_up
	
	# 动态调整图标大小，随 K 线宽度缩放
	var base_size = _chart.get_candle_width() * 0.4
	var arrow_size = clamp(base_size, 3.0, 10.0) # 限制最大最小值
	var offset_y = arrow_size * 2.5 # 偏移量也动态化
	
	for i in range(start, end + 1):
		if data_map.has(i):
			var price = data_map[i]
			
			# [核心] 使用统一坐标
			var x = _chart.get_x_by_index_public(i)
			var y = _chart.map_price_to_y_public(price)
			
			var points = PackedVector2Array()
			
			if is_up:
				# 底分型（向上箭头，位于 Low 下方）
				# 顶点指向上方
				points.append(Vector2(x, y + offset_y))           # 箭头尖
				points.append(Vector2(x - arrow_size, y + offset_y + arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y + offset_y + arrow_size * 1.5))
			else:
				# 顶分型（向下箭头，位于 High 上方）
				points.append(Vector2(x, y - offset_y))           # 箭头尖
				points.append(Vector2(x - arrow_size, y - offset_y - arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y - offset_y - arrow_size * 1.5))
				
			draw_colored_polygon(points, color)
