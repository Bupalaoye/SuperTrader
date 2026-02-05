extends Control
class_name KLineChart

# --- 配置参数 ---
@export_group("Visual Settings")
@export var candle_width: float = 8.0
@export var spacing: float = 2.0
@export var bull_color: Color = Color.hex(0x00FF00FF) # 涨 (绿)
@export var bear_color: Color = Color.hex(0xFF0000FF) # 跌 (红)
@export var wick_color: Color = Color.WHITE
@export var bg_color: Color = Color.hex(0x111111FF)

# --- 数据存储 ---
var _all_candles: Array = [] 
var _visible_count: int = 100

# --- 视图状态 ---
var _end_index: int = 0 
var _max_visible_price: float = 0.0
var _min_visible_price: float = 0.0
var _price_range: float = 1.0

# --- 交互状态 ---
var _is_dragging: bool = false
var _drag_start_x: float = 0.0
var _drag_start_index: int = 0

func _ready():
	_end_index = -1

func _draw():
	# 1. 绘制背景
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	
	if _all_candles.is_empty():
		return

	# --- 性能优化第一步：预计算布局参数 ---
	var chart_height = size.y
	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	
	# 限制最小宽度，防止缩放过小导致一次绘制几万根而卡死
	if candle_full_width < 1.0: candle_full_width = 1.0
	
	_visible_count = ceili(chart_width / candle_full_width) + 1
	var start_index = max(0, _end_index - _visible_count)
	var count = _end_index - start_index
	
	if count <= 0: return

	# 计算价格边界
	_calculate_price_bounds(start_index, _end_index)
	
	# --- 性能优化第二步：内联数学计算系数 ---
	# 避免在循环里做除法，改为乘法 (乘法比除法快)
	# Pre-calculate calculation constants
	var price_range_inv = 0.0
	if _price_range > 0.0000001:
		price_range_inv = 1.0 / _price_range
		
	var padding_top = chart_height * 0.05
	var render_height = chart_height * 0.9
	var min_p = _min_visible_price

	# --- 性能优化第三步：准备批量绘制数组 ---
	# 使用 PackedVector2Array 比普通 Array 快得多
	var wick_lines = PackedVector2Array() 
	# 虽然 Godot 没有 draw_rects (复数)，但我们至少可以把影线合并
	
	# 循环
	for i in range(count):
		# 从左到右绘制，为了对齐 MT4，这里假设 end_index 是屏幕最右侧
		# 计算逻辑：index 越小越左
		# right_offset 是相对于屏幕右边缘的偏移量
		var data_idx = _end_index - i
		if data_idx < 0: break
		
		var candle = _all_candles[data_idx]
		
		# X 坐标：从右向左画
		# 屏幕宽度 - (当前第几根 * 宽度) - 半个宽度修正
		var x_pos = chart_width - (i * candle_full_width) - (candle_width * 0.5)
		
		if x_pos < -candle_width: break # 超出左边界提前退出
		
		# --- 内联 Y 轴映射逻辑 (Inlining) ---
		# 原来的函数调用 _map_price_to_y 删除了
		var o = candle.o
		var c = candle.c
		var h = candle.h
		var l = candle.l
		
		# 公式: y = padding + (1.0 - (price - min) * range_inv) * height
		# 简化: y = padding + height - (price - min) * range_inv * height
		# 提取常量 scale = range_inv * height
		var val_scale = price_range_inv * render_height
		var base_y = padding_top + render_height
		
		var y_open = base_y - (o - min_p) * val_scale
		var y_close = base_y - (c - min_p) * val_scale
		var y_high = base_y - (h - min_p) * val_scale
		var y_low = base_y - (l - min_p) * val_scale
		
		# --- 收集影线数据 ---
		wick_lines.append(Vector2(x_pos, y_high))
		wick_lines.append(Vector2(x_pos, y_low))
		
		# --- 立即绘制实体 (无法批量，除非用 Mesh，但这步通常够快了) ---
		var is_bull = c >= o
		var rect_color = bull_color if is_bull else bear_color
		
		var rect_top = min(y_open, y_close)
		var rect_h = abs(y_close - y_open)
		if rect_h < 1.0: rect_h = 1.0
		
		# 注意 draw_rect 用的是左上角坐标，x_pos 是中心，所以要偏一下
		draw_rect(Rect2(x_pos - candle_width/2.0, rect_top, candle_width, rect_h), rect_color)

	# --- 性能优化第四步：一次性绘制所有影线 ---
	# 这将几百次 draw_line 压缩为 1 次底层 API 调用
	if wick_lines.size() > 0:
		draw_multiline(wick_lines, wick_color, 1.0)

# --- 辅助逻辑保持不变 ---

func _calculate_price_bounds(start_idx: int, end_idx: int):
	# 重置极值
	_min_visible_price = INF
	_max_visible_price = -INF
	
	# 这里增加一个步长保护，防止数据量过大时循环太久
	# 虽然通常可视区域只有几百根，但为了安全
	start_idx = clamp(start_idx, 0, _all_candles.size() - 1)
	end_idx = clamp(end_idx, 0, _all_candles.size() - 1)
	
	if start_idx > end_idx: return

	# 简单的循环寻找极值 (对于几百个元素，这比 Array.max() 快，因为只遍历部分)
	for i in range(start_idx, end_idx + 1):
		var c = _all_candles[i]
		if c.l < _min_visible_price: _min_visible_price = c.l
		if c.h > _max_visible_price: _max_visible_price = c.h
	
	_price_range = _max_visible_price - _min_visible_price
	if _price_range == 0: _price_range = 1.0

# --- 交互逻辑保持基本一致 ---

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_chart(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_chart(0.9)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_start_x = event.position.x
				_drag_start_index = _end_index
			else:
				_is_dragging = false

	if event is InputEventMouseMotion and _is_dragging:
		var delta_x = event.position.x - _drag_start_x
		var candle_full_width = candle_width + spacing
		var move_count = int(delta_x / candle_full_width)
		
		# 修正: 拖拽方向
		_end_index = _drag_start_index + move_count
		_clamp_view()
		queue_redraw()

func _zoom_chart(factor: float):
	candle_width *= factor
	candle_width = clamp(candle_width, 1.0, 100.0)
	queue_redraw()

func _clamp_view():
	_end_index = clamp(_end_index, 0, _all_candles.size() - 1)

# --- 公开接口 ---

func set_history_data(data: Array):
	_all_candles = data
	_end_index = data.size() - 1
	queue_redraw()

func append_candle(data: Dictionary):
	_all_candles.append(data)
	if _end_index >= _all_candles.size() - 2:
		_end_index = _all_candles.size() - 1
	queue_redraw()

func jump_to_index(idx: int):
	_end_index = idx
	_clamp_view()
	queue_redraw()
