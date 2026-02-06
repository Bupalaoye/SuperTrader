extends Control
class_name KLineChart

# --- 状态机定义 (第一阶段核心) ---
enum Mode { 
	NONE,       # 默认状态
	DRAG_VIEW,  # 拖拽视图平移
	CROSSHAIR,  # 十字光标模式
	MEASURE     # 量尺测量模式
}

# --- 配置参数 ---
@export_group("Visual Settings")
@export var candle_width: float = 8.0 
@export var spacing: float = 2.0 
@export var bull_color: Color = Color.hex(0x00FF00FF) 
@export var bear_color: Color = Color.hex(0xFF0000FF) 
@export var wick_color: Color = Color.WHITE 
@export var bg_color: Color = Color.hex(0x111111FF) 

# --- 节点引用 ---
var _overlay: CrosshairOverlay # 引用子节点

# --- 数据存储 ---
var _all_candles: Array = [] 
var _visible_count: int = 100 

# --- 视图状态 ---
var _end_index: int = 0 
var _max_visible_price: float = 0.0
var _min_visible_price: float = 0.0
var _price_range: float = 1.0

# --- 交互状态 ---
var _current_mode: Mode = Mode.NONE # 单源真理
var _drag_start_x: float = 0.0
var _drag_start_index: int = 0
var _zoom_speed: float = 1.0

func _ready():
	# 1. 初始化覆盖层 (架构分层)
	_setup_overlay()
	
	# 2. 初始化数据
	_generate_test_data()
	_end_index = _all_candles.size() - 1

# 动态创建 Overlay 节点，确保“分层”架构落地
func _setup_overlay():
	_overlay = CrosshairOverlay.new()
	_overlay.name = "CrosshairOverlay"
	# 让覆盖层撑满整个图表
	_overlay.layout_mode = 1 # Anchors Preset: Full Rect
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	# 初始状态设为关闭
	_overlay.set_active(false)

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	
	if _all_candles.is_empty():
		return

	# [保留原有的绘制逻辑不变]
	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	_visible_count = ceili(chart_width / candle_full_width)
	var start_index = max(0, _end_index - _visible_count)
	var count = _end_index - start_index
	if count <= 0: return

	_calculate_price_bounds(start_index, _end_index)

	for i in range(count):
		var data_idx = start_index + i
		var candle = _all_candles[data_idx]
		var x_pos = i * candle_full_width
		
		var y_open = _map_price_to_y(candle.o)
		var y_close = _map_price_to_y(candle.c)
		var y_high = _map_price_to_y(candle.h)
		var y_low = _map_price_to_y(candle.l)
		
		var is_bull = candle.c >= candle.o
		var color = bull_color if is_bull else bear_color
		
		var center_x = x_pos + candle_width / 2
		draw_line(Vector2(center_x, y_high), Vector2(center_x, y_low), wick_color, 1.0)
		
		var rect_top = min(y_open, y_close)
		var rect_height = abs(y_close - y_open)
		if rect_height < 1.0: rect_height = 1.0 
		draw_rect(Rect2(x_pos, rect_top, candle_width, rect_height), color)

func _gui_input(event):
	# 1. 鼠标按键事件
	if event is InputEventMouseButton:
		
		# --- A. 中键：切换十字光标模式 ---
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_toggle_crosshair_mode()
			accept_event() 
			return

		# --- B. 滚轮 ---
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_chart(1.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_chart(0.9)
			accept_event()
			
		# --- C. 左键 ---
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				match _current_mode:
					Mode.NONE:
						_start_drag(event.position.x)
					Mode.CROSSHAIR:
						_start_measure(event.position)
			else:
				match _current_mode:
					Mode.DRAG_VIEW:
						_stop_drag()
					Mode.MEASURE:
						_stop_measure()
	# 2. 鼠标移动事件
	if event is InputEventMouseMotion:
		match _current_mode:
			Mode.DRAG_VIEW:
				_process_drag(event.position.x)
			
			Mode.CROSSHAIR, Mode.MEASURE:
				# --- Phase 2 新增逻辑: 像素转数据 ---
				var data = _get_data_at_mouse(event.position)
				
				# 通知 Overlay 更新，不仅传位置，还传价格和时间
				if _overlay:
					_overlay.update_crosshair(event.position, data)

# 把鼠标位置转换成具体的业务数据
func _get_data_at_mouse(mouse_pos: Vector2) -> Dictionary:
	var result = {
		"price": 0.0,
		"price_str": "",
		"time_str": "",
		"index": -1
	}
	
	# 1. 计算 Y 轴对应的价格
	result.price = _get_price_at_y(mouse_pos.y)
	# 格式化价格 (这里假设是外汇 4位小数，你可以根据 symbol digits 动态调整)
	result.price_str = "%.5f" % result.price
	
	# 2. 计算 X 轴对应的索引
	var idx = _get_index_at_x(mouse_pos.x)
	result.index = idx
	
	# 3. 获取时间
	if idx >= 0 and idx < _all_candles.size():
		var candle = _all_candles[idx]
		# 假设你的数据里有 "t" (time) 字段
		result.time_str = str(candle.get("t", "N/A"))
	else:
		result.time_str = ""
		
	return result
# 像素 X -> K线索引 Index
func _get_index_at_x(x: float) -> int:
	var candle_full_width = candle_width + spacing
	if candle_full_width <= 0: return 0
	
	# 计算屏幕可见的起始索引
	# 注意：必须和 _draw 里的逻辑完全一致
	var char_width = size.x
	# 这里的 _visible_count 最好引用 _draw 计算后的值，或者重新算一遍
	var vis_count = ceili(char_width / candle_full_width)
	var start_index = max(0, _end_index - vis_count)
	
	# 当前鼠标在第几根（相对于屏幕左侧）
	var relative_idx = int(x / candle_full_width)
	
	return start_index + relative_idx
# 像素 Y -> 价格 Price
func _get_price_at_y(y: float) -> float:
	# 逆向推导 _map_price_to_y 公式
	# 原公式: y = padding + (1.0 - ratio) * render_height
	# ratio = (price - min) / range
	
	var padding = size.y * 0.05
	var render_height = size.y * 0.9
	
	if render_height == 0: return 0.0
	
	var val = (y - padding) / render_height
	var ratio = 1.0 - val
	
	return _min_visible_price + ratio * _price_range
# --- 状态管理方法 ---

func _toggle_crosshair_mode():
	if _current_mode == Mode.CROSSHAIR or _current_mode == Mode.MEASURE:
		# 退出十字模式，回到普通模式
		_current_mode = Mode.NONE
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _overlay: _overlay.set_active(false)
	else:
		# 进入十字模式
		_current_mode = Mode.CROSSHAIR
		
		# Input.mouse_mode = Input.MOUSE_MODE_HIDDEN 
		if _overlay: 
			_overlay.set_active(true)
			
			# 因为 update_crosshair 现在需要两个参数，所以初始化时也要计算一下数据
			var mouse_pos = get_local_mouse_position()
			var data = _get_data_at_mouse(mouse_pos)
			_overlay.update_crosshair(mouse_pos, data)

func _start_drag(mouse_x: float):
	_current_mode = Mode.DRAG_VIEW
	_drag_start_x = mouse_x
	_drag_start_index = _end_index

func _stop_drag():
	if _current_mode == Mode.DRAG_VIEW:
		_current_mode = Mode.NONE

func _process_drag(mouse_x: float):
	var delta_x = mouse_x - _drag_start_x
	var candle_full_width = candle_width + spacing
	var move_count = int(delta_x / candle_full_width)
	_end_index = _drag_start_index - move_count
	_clamp_view()
	queue_redraw()

# 量尺暂未实现具体绘制（第二/三阶段内容），先搭好状态切换
func _start_measure(pos: Vector2):
	_current_mode = Mode.MEASURE
	print("开始测量 (Phase 3 待实现)")

func _stop_measure():
	# 松手后回到十字模式
	_current_mode = Mode.CROSSHAIR
	print("结束测量")

# --- 辅助函数保持不变 ---
func _map_price_to_y(price: float) -> float:
	if _price_range == 0: return size.y / 2
	var ratio = (price - _min_visible_price) / _price_range
	var padding = size.y * 0.05
	var render_height = size.y * 0.9
	return padding + (1.0 - ratio) * render_height

func _calculate_price_bounds(start_idx: int, end_idx: int):
	var min_p = 99999999.0
	var max_p = -99999999.0
	for i in range(start_idx, end_idx + 1):
		if i >= _all_candles.size(): break
		var c = _all_candles[i]
		if c.l < min_p: min_p = c.l
		if c.h > max_p: max_p = c.h
	_min_visible_price = min_p
	_max_visible_price = max_p
	_price_range = max_p - min_p

func _zoom_chart(factor: float):
	candle_width *= factor
	candle_width = clamp(candle_width, 1.0, 100.0)
	queue_redraw()

func _clamp_view():
	_end_index = clamp(_end_index, 0, _all_candles.size() - 1)

func set_history_data(data: Array):
	_all_candles = data
	_end_index = data.size() - 1
	queue_redraw()

func append_candle(data: Dictionary):
	_all_candles.append(data)
	if _end_index == _all_candles.size() - 2:
		_end_index += 1
	queue_redraw()

func jump_to_index(idx: int):
	_end_index = idx
	_clamp_view()
	queue_redraw()

func _generate_test_data():
	var price = 100.0
	for i in range(2000):
		var change = randf_range(-2.0, 2.0)
		var o = price
		var c = price + change
		var h = max(o, c) + randf_range(0.0, 1.0)
		var l = min(o, c) - randf_range(0.0, 1.0)
		_all_candles.append({"t": str(i), "o": o, "h": h, "l": l, "c": c})
		price = c
