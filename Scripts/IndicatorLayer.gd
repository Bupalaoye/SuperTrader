class_name IndicatorLayer
extends Control

# --- 依赖 ---
var _chart: KLineChart
var _indicators: Array[Dictionary] = [] # 存储所有开启的指标

# --- 结构定义 ---
# 指标字典结构:
# {
#   "type": "MA", 
#   "data": [Array of floats], 
#   "color": Color, 
#   "width": 1.5,
#   "is_subwindow": false # 是否像 MACD 那样画在副图 (目前先都画主图)
# }

func setup(chart: KLineChart):
	_chart = chart
	mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

# 添加一个指标数据
func add_indicator(data_array: Array, color: Color, width: float = 1.0):
	var ind = {
		"type": "Line",
		"data": data_array,
		"color": color,
		"width": width
	}
	_indicators.append(ind)
	queue_redraw()

func clear_indicators():
	_indicators.clear()
	queue_redraw()

func _draw():
	if not _chart or _indicators.is_empty(): return
	
	# 获取图表可见范围，只绘制可见部分，提升性能
	# 这里我们需要访问 KLineChart 的一些私有变量，或者再次复用其公开接口
	# 为了方便，我们在 KLineChart 里加一个 get_visible_range() 接口
	# 现在先全量绘制，或者简单的视锥剔除
	
	var chart_rect = get_rect()
	var point_count = _indicators[0].data.size() # 假设所有指标长度和 K线一致
	
	# 遍历每一条指标线
	for ind in _indicators:
		var data = ind.data
		var col = ind.color
		var w = ind.width
		var points_to_draw = PackedVector2Array()
		
		# 这是一个优化点：只遍历屏幕内的索引
		var start_idx = _chart.get_first_visible_index()
		var end_idx = _chart.get_last_visible_index()
		
		# 多画两根以防断裂
		start_idx = max(0, start_idx - 2)
		end_idx = min(data.size() - 1, end_idx + 2)
		
		for i in range(start_idx, end_idx + 1):
			var val = data[i]
			
			if is_nan(val):
				# 如果遇到无效值，且之前有积攒的点，先把之前的线画了（断开处理）
				if points_to_draw.size() > 1:
					draw_polyline(points_to_draw, col, w, true)
				points_to_draw.clear()
				continue
			
			# 获取屏幕坐标
			# X: 这里稍微麻烦，我们需要根据 Index 算 X
			# KLineChart 需要提供 get_x_by_index
			var x = _chart.get_x_by_index_public(i)
			var y = _chart.map_price_to_y_public(val)
			
			points_to_draw.append(Vector2(x, y))
		
		# 画剩下的
		if points_to_draw.size() > 1:
			draw_polyline(points_to_draw, col, w, true)