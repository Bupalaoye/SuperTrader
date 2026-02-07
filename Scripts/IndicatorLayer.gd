class_name IndicatorLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _indicators: Array[Dictionary] = [] 

# --- 结构定义 ---
# 1. Line: { type:"Line", data:[], color, width }
# 2. Band: { type:"Band", data:{ub,lb,mb}, color, width }
# 3. Marker: { type:"Marker", data:{ index: price, ... }, color, is_up: bool } [新增]

func setup(chart: KLineChart):
	_chart = chart
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# 添加普通折线
func add_line_indicator(data_array: Array, color: Color, width: float = 1.0):
	_indicators.append({ "type": "Line", "data": data_array, "color": color, "width": width })
	queue_redraw()

# 添加布林带通道
func add_band_indicator(data_dict: Dictionary, color: Color, width: float = 1.0):
	_indicators.append({ "type": "Band", "data": data_dict, "color": color, "width": width })
	queue_redraw()

# [兼容] 新增：通过 key 更新或新增 Band 指标，避免重复堆叠
func update_band_indicator(key: String, data_dict: Dictionary, color: Color, width: float = 1.0):
	# 1. 如果存在相同 key，则更新数据
	for i in range(_indicators.size()):
		if _indicators[i].has("key") and _indicators[i]["key"] == key:
			_indicators[i]["data"] = data_dict
			_indicators[i]["color"] = color
			_indicators[i]["width"] = width
			queue_redraw()
			return

	# 2. 否则新增一条带 key 的 Band 指标
	_indicators.append({
		"key": key,
		"type": "Band",
		"data": data_dict,
		"color": color,
		"width": width
	})
	queue_redraw()

# [兼容旧接口] 保留 add_band_indicator，但内部生成随机 key
func add_band_indicator_compat(data_dict: Dictionary, color: Color, width: float = 1.0):
	var random_key = "Band_" + str(randi())
	update_band_indicator(random_key, data_dict, color, width)

# [新增] 添加图标标记 (用于分型 Fractals)
# data_map: 字典 { index(int): price(float), ... }
# is_up_arrow: true=向上箭头(标记底), false=向下箭头(标记顶)
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
	
	var start_idx = max(0, _chart.get_first_visible_index() - 2)
	var end_idx = min(_chart.get_last_visible_index() + 2, 999999)
	
	for ind in _indicators:
		if ind.type == "Line":
			_draw_simple_line(ind, start_idx, end_idx)
		elif ind.type == "Band":
			_draw_band_channel(ind, start_idx, end_idx)
		elif ind.type == "Marker":
			_draw_markers(ind, start_idx, end_idx)

# 绘制图标标记
func _draw_markers(ind: Dictionary, start: int, end: int):
	var data_map = ind.data
	var color = ind.color
	var is_up = ind.is_up
	var arrow_size = 6.0
	var offset_y = 15.0 # 距离价格的偏移量像素
	
	# 遍历可见范围内的索引
	for i in range(start, end + 1):
		if data_map.has(i):
			var price = data_map[i]
			var x = _chart.get_x_by_index_public(i)
			var y = _chart.map_price_to_y_public(price)
			
			var points = PackedVector2Array()
			if is_up:
				# 向上箭头 (标记底部，画在 Price 下方)
				var tip = Vector2(x, y + offset_y)
				points.append(tip)
				points.append(Vector2(x - arrow_size, y + offset_y + arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y + offset_y + arrow_size * 1.5))
			else:
				# 向下箭头 (标记顶部，画在 Price 上方)
				var tip = Vector2(x, y - offset_y)
				points.append(tip)
				points.append(Vector2(x - arrow_size, y - offset_y - arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y - offset_y - arrow_size * 1.5))
			
			draw_colored_polygon(points, color)

# 绘制普通单线
func _draw_simple_line(ind: Dictionary, start: int, end: int):
	var data = ind.data
	var safe_end = min(end, data.size() - 1)
	if safe_end <= start: return
	
	var points = PackedVector2Array()
	
	for i in range(start, safe_end + 1):
		var val = data[i]
		if is_nan(val):
			if points.size() > 1:
				draw_polyline(points, ind.color, ind.width, true)
			points.clear()
			continue
			
		var x = _chart.get_x_by_index_public(i)
		var y = _chart.map_price_to_y_public(val)
		points.append(Vector2(x, y))
		
	if points.size() > 1:
		draw_polyline(points, ind.color, ind.width, true)

# [核心] 绘制通道 (布林带)
func _draw_band_channel(ind: Dictionary, start: int, end: int):
	var ub = ind.data.get("ub", [])
	var lb = ind.data.get("lb", [])
	var mb = ind.data.get("mb", []) # 中轨可选
	
	var safe_end = min(end, ub.size() - 1)
	if safe_end <= start: return
	
	# --- 1. 绘制半透明填充 (Fill) ---
	# 颜色处理：取原色，Alpha 通道设为 0.1 ~ 0.2 (半透明)
	var fill_color = ind.color
	fill_color.a = 0.15 
	
	# 构建多边形点集：顺时针一圈
	# 上轨：从左到右 -> 下轨：从右到左
	var polygon_points = PackedVector2Array()
	var bottom_points_reversed = PackedVector2Array()
	
	# 这里我们要处理 NAN 断层。如果中间有断层，必须要把多边形切断
	# 为了简单高效，我们假设布林带中间不会突然断裂，只要开始有值就是连续的
	
	var current_chunk_top = PackedVector2Array()
	var current_chunk_bot = PackedVector2Array()
	
	for i in range(start, safe_end + 1):
		var val_u = ub[i]
		var val_l = lb[i]
		
		if is_nan(val_u) or is_nan(val_l):
			# 遇到断层，如果之前有积累了点，先画掉
			if not current_chunk_top.is_empty():
				_flush_poly(current_chunk_top, current_chunk_bot, fill_color)
				current_chunk_top.clear()
				current_chunk_bot.clear()
			continue
			
		var x = _chart.get_x_by_index_public(i)
		var y_u = _chart.map_price_to_y_public(val_u)
		var y_l = _chart.map_price_to_y_public(val_l)
		
		current_chunk_top.append(Vector2(x, y_u))
		current_chunk_bot.append(Vector2(x, y_l))
	
	# 循环结束后，画最后一段
	if not current_chunk_top.is_empty():
		_flush_poly(current_chunk_top, current_chunk_bot, fill_color)

	# --- 2. 绘制边框线 (Outline) ---
	# 为了美观，边框线稍微淡一点，或者细一点
	var line_color = ind.color
	line_color.a = 0.6 # 边框 60% 透明度
	
	# 就是调用画线的逻辑，把 UB, LB, MB 分别画一次
	if not ub.is_empty(): _draw_sub_line(ub, start, safe_end, line_color, 1.0)
	if not lb.is_empty(): _draw_sub_line(lb, start, safe_end, line_color, 1.0)
	if not mb.is_empty(): _draw_sub_line(mb, start, safe_end, line_color, 1.0, true) # 中轨可以是虚线或不同色

# 辅助：提交多边形绘制
func _flush_poly(t: PackedVector2Array, b: PackedVector2Array, c: Color):
	if t.size() < 2: return
	var p = t.duplicate()
	b.reverse()
	p.append_array(b)
	draw_colored_polygon(p, c)

# 辅助：画内部单线
func _draw_sub_line(data: Array, start: int, end: int, col: Color, w: float, dashed: bool = false):
	var points = PackedVector2Array()
	for i in range(start, end + 1):
		var v = data[i]
		if is_nan(v):
			if points.size() > 1: _draw_seg(points, col, w, dashed)
			points.clear(); continue
		points.append(Vector2(_chart.get_x_by_index_public(i),_chart.map_price_to_y_public(v)))
	if points.size() > 1: _draw_seg(points, col, w, dashed)

func _draw_seg(pts: PackedVector2Array, c: Color, w: float, d: bool):
	if d: for i in range(pts.size()-1): if i%2==0: draw_line(pts[i], pts[i+1], c, w)
	else: draw_polyline(pts, c, w, true)