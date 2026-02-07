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
	# 获取数据
	var ub = ind.data.get("ub", [])
	var lb = ind.data.get("lb", [])
	var mb = ind.data.get("mb", [])
	
	# 颜色处理：强制完全不透明
	var line_color = ind.color
	line_color.a = 1.0 
	
	# 线宽：默认稍微加粗一点
	var w = ind.get("width", 1.5)

	# 数据安全检查
	if ub.is_empty(): return
	
	var max_idx = ub.size() - 1
	var safe_end = min(end, max_idx)
	if safe_end <= start: return

	# 直接画三根线，无需任何花哨逻辑
	if not ub.is_empty(): _draw_solid_line(ub, start, safe_end, line_color, w)
	if not lb.is_empty(): _draw_solid_line(lb, start, safe_end, line_color, w)
	if not mb.is_empty(): _draw_solid_line(mb, start, safe_end, line_color, w)

# --- 通用画线函数 (Solid Line) ---
func _draw_solid_line(data: Array, start: int, end: int, col: Color, w: float):
	var points = PackedVector2Array()
	
	for i in range(start, end + 1):
		# 安全边界检查
		if i < 0 or i >= data.size(): continue
		
		var val = data[i]
		
		# 遇到无效值(NAN)，断开线条重画
		if is_nan(val):
			if points.size() > 1:
				draw_polyline(points, col, w, true)
			points.clear()
			continue
		
		# 坐标转换
		var x = _chart.get_x_by_index_public(i)
		var y = _chart.map_price_to_y_public(val)
		points.append(Vector2(x, y))
	
	# 画最后一段
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
	var arrow_size = 6.0
	var offset_y = 15.0
	
	for i in range(start, end + 1):
		if data_map.has(i):
			var price = data_map[i]
			var x = _chart.get_x_by_index_public(i)
			var y = _chart.map_price_to_y_public(price)
			var points = PackedVector2Array()
			if is_up:
				points.append(Vector2(x, y + offset_y))
				points.append(Vector2(x - arrow_size, y + offset_y + arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y + offset_y + arrow_size * 1.5))
			else:
				points.append(Vector2(x, y - offset_y))
				points.append(Vector2(x - arrow_size, y - offset_y - arrow_size * 1.5))
				points.append(Vector2(x + arrow_size, y - offset_y - arrow_size * 1.5))
			draw_colored_polygon(points, color)