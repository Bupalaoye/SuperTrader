extends Control
class_name KLineChart

# --- 状态机定义 ---
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
var _overlay: CrosshairOverlay
# --- 新增变量 ---
var _order_layer: OrderOverlay
var _drawing_layer: DrawingLayer
var _indicator_layer: IndicatorLayer
# [新增] 现价线层
var _current_price_layer: CurrentPriceLayer
# [新增] 网格层
var _grid_layer: GridLayer 

# --- 数据存储 ---
var _all_candles: Array = [] 
var _visible_count: int = 100
# [新增] 时间索引缓存，用于快速查找特定时间的K线位置
var _time_to_index_cache: Dictionary = {} 

# --- 视图状态 ---
var _end_index: int = 0 
var _max_visible_price: float = 0.0
var _min_visible_price: float = 0.0
var _price_range: float = 1.0

# --- 交互状态 ---
var _current_mode: Mode = Mode.NONE 
var _measure_start_pos: Vector2 = Vector2.ZERO   
var _measure_start_data: Dictionary = {}         
var _drag_start_x: float = 0.0
var _drag_start_index: int = 0
var _zoom_speed: float = 1.0

func _ready():
	# 按顺序初始化，确保遮挡关系正确
	
	# 1. 底层
	# (未来放网格层)
	
	# 2. K线 (KLineChart 自身的 _draw 画在最底层)
	_generate_test_data()
	_end_index = _all_candles.size() - 1

	# 1. 网格层 (GridLayer)
	_grid_layer = GridLayer.new()
	_grid_layer.name = "GridLayer"
	add_child(_grid_layer)
	
	# [修改] 传入 bg_color 
	_grid_layer.setup(self, bg_color)
	
	# [关键] 这一行绝对不能少，保证 Grid 在 Chart 之前画
	_grid_layer.show_behind_parent = true

	# 3. 指标层
	_indicator_layer = IndicatorLayer.new()
	_indicator_layer.name = "IndicatorLayer"
	add_child(_indicator_layer)
	_indicator_layer.setup(self)

	# 4. [新增] 现价线层 (在指标之上，但在订单之下)
	_current_price_layer = CurrentPriceLayer.new()
	_current_price_layer.name = "CurrentPriceLayer"
	add_child(_current_price_layer)
	_current_price_layer.setup(self)

	# 5. 绘图层 ([修复核心] 必须先添加 DrawingLayer，再添加 OrderOverlay)
	_drawing_layer = DrawingLayer.new()
	_drawing_layer.name = "DrawingLayer"
	add_child(_drawing_layer)
	_drawing_layer.setup(self)
	
	# 6. 订单层 (现在它在 DrawingLayer 之上，能优先接收鼠标)
	_order_layer = OrderOverlay.new()
	_order_layer.name = "OrderOverlay"
	add_child(_order_layer)
	_order_layer.setup(self)
	
	# 7. 十字光标 (最顶层)
	_setup_overlay()

func _setup_overlay():
	_overlay = CrosshairOverlay.new()
	_overlay.name = "CrosshairOverlay"
	_overlay.layout_mode = 1 
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_overlay.set_active(false)

func _draw():
	# [修改] 删除了 draw_rect - 背景现在由 GridLayer 负责
	# 现在的绘制逻辑是：
	# 1. GridLayer._draw (画背景 + 网格) -> 因为 show_behind_parent
	# 2. KLineChart._draw (画蜡烛)      -> 因为这是父节点
	
	# [新增] 触发网格的一起重绘
	if _grid_layer: _grid_layer.queue_redraw()
	
	if _all_candles.is_empty():
		return

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
	
	# 每次 Chart 重绘时(比如拖拽、缩放、新K线)，通知 OrderLayer 也跟着对齐重绘
	if _order_layer:
		_order_layer.queue_redraw()
	
	# 通知指标层重绘
	if _indicator_layer:
		_indicator_layer.queue_redraw()

func _gui_input(event):
	# 1. 鼠标按键事件
	if event is InputEventMouseButton:
		
		# --- A. 中键：切换十字光标模式 ---
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_toggle_crosshair_mode()
			accept_event() 
			return
		
		# --- D. (新功能) 右键：取消/退出十字光标模式 ---
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# 只有在 十字模式 或 测量模式 下，右键才生效（作为取消键）
			if _current_mode == Mode.CROSSHAIR or _current_mode == Mode.MEASURE:
				_disable_crosshair_mode() # 强行退出
				accept_event()
			return

		# --- B. 滚轮 (缩放) ---
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_chart(1.1)
			if _current_mode == Mode.CROSSHAIR: _push_data_to_overlay(get_local_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_chart(0.9)
			if _current_mode == Mode.CROSSHAIR: _push_data_to_overlay(get_local_mouse_position())
			accept_event()
			
		# --- C. 左键 (核心交互逻辑) ---
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
				_push_data_to_overlay(event.position)

# --- 核心逻辑 ---

func _push_data_to_overlay(mouse_pos: Vector2):
	if not _overlay: return
	var current_data = _get_data_at_mouse(mouse_pos)
	
	var payload = current_data.duplicate()
	payload["current_pos"] = mouse_pos
	
	if _current_mode == Mode.MEASURE:
		payload["is_measuring"] = true
		payload["start_pos"] = _measure_start_pos
		payload["start_price"] = _measure_start_data.get("price", 0.0)
		payload["start_index"] = _measure_start_data.get("index", 0)
	else:
		payload["is_measuring"] = false
	
	_overlay.update_crosshair(mouse_pos, payload)

func _start_measure(pos: Vector2):
	_current_mode = Mode.MEASURE
	_measure_start_pos = pos
	_measure_start_data = _get_data_at_mouse(pos)
	_push_data_to_overlay(pos)

func _stop_measure():
	_current_mode = Mode.CROSSHAIR
	_push_data_to_overlay(get_local_mouse_position())

func _get_data_at_mouse(mouse_pos: Vector2) -> Dictionary:
	var result = {
		"price": 0.0,
		"price_str": "",
		"time_str": "",
		"index": -1
	}
	result.price = _get_price_at_y(mouse_pos.y)
	result.price_str = "%.5f" % result.price
	var idx = _get_index_at_x(mouse_pos.x)
	result.index = idx
	if idx >= 0 and idx < _all_candles.size():
		result.time_str = str(_all_candles[idx].get("t", "N/A"))
	else:
		result.time_str = ""
	return result

func _get_index_at_x(x: float) -> int:
	var candle_full_width = candle_width + spacing
	if candle_full_width <= 0: return 0
	var char_width = size.x
	var vis_count = ceili(char_width / candle_full_width)
	var start_index = max(0, _end_index - vis_count)
	var relative_idx = int(x / candle_full_width)
	return start_index + relative_idx

func _get_price_at_y(y: float) -> float:
	var padding = size.y * 0.05
	var render_height = size.y * 0.9
	if render_height == 0: return 0.0
	var val = (y - padding) / render_height
	var ratio = 1.0 - val
	return _min_visible_price + ratio * _price_range

# --- 状态管理方法更新 ---

func _toggle_crosshair_mode():
	# 如果已经在十字或测量模式，则关闭
	if _current_mode == Mode.CROSSHAIR or _current_mode == Mode.MEASURE:
		_disable_crosshair_mode()
	else:
		# 否则开启
		_enable_crosshair_mode()

# 拆分出独立的开启函数
func _enable_crosshair_mode():
	_current_mode = Mode.CROSSHAIR
	# Input.mouse_mode = Input.MOUSE_MODE_HIDDEN # 如需隐藏系统光标可取消注释
	if _overlay: 
		_overlay.set_active(true)
		_push_data_to_overlay(get_local_mouse_position())

# 拆分出独立的关闭函数 (供中键Toggle和右键Cancel共同使用)
func _disable_crosshair_mode():
	_current_mode = Mode.NONE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _overlay: _overlay.set_active(false)

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
	
	# [新增] 重建缓存
	_time_to_index_cache.clear()
	for i in range(data.size()):
		var t_str = data[i].t
		_time_to_index_cache[t_str] = i
	
	queue_redraw()

func append_candle(data: Dictionary):
	_all_candles.append(data)
	
	# [新增] 更新缓存
	_time_to_index_cache[data.t] = _all_candles.size() - 1
	
	if _end_index == _all_candles.size() - 2:
		_end_index += 1
	queue_redraw()

# [新增] 更新现价线 (支持倒计时)
func update_current_price(price: float, seconds_left: int = 0):
	if _current_price_layer:
		# 调用新的 update_info 接口
		_current_price_layer.update_info(price, seconds_left)

# [新增] 更新最后一根 K 线的数据 (用于模拟 Tick 波动)
func update_last_candle(data: Dictionary):
	if _all_candles.is_empty(): return

	# 1. 更新数据
	_all_candles[_all_candles.size() - 1] = data

	# 2. 关键修复：因为 High/Low 变了，必须重新计算Y轴缩放范围，
	# 否则新长出来的 K 线可能超出屏幕或看起来是扁的
	# 我们获取当前可见范围的索引进行重算
	var vis_count = ceili(size.x / (candle_width + spacing))
	var start_idx = max(0, _end_index - vis_count)
	_calculate_price_bounds(start_idx, _end_index)

	# 3. 强制重绘
	queue_redraw()

	# 4. 通知所有图层刷新
	if _order_layer: _order_layer.queue_redraw()
	if _current_price_layer: _current_price_layer.queue_redraw()

func jump_to_index(idx: int):
	_end_index = idx
	_clamp_view()
	queue_redraw()

func _generate_test_data():
	var price = 1.10000 # 模拟欧元兑美元价格
	var current_time = Time.get_unix_time_from_system()
	
	for i in range(100): # 生成100根K线
		var change = randf_range(-0.0005, 0.0005)
		var o = price
		var c = price + change
		var h = max(o, c) + randf_range(0.0, 0.0002)
		var l = min(o, c) - randf_range(0.0, 0.0002)
		
		# [Bug修复核心] 生成 Time 字符串 "YYYY.MM.DD HH:mm"
		# 每一根K线间隔 1 小时 (3600秒)
		current_time += 3600 
		var t_str = Time.get_datetime_string_from_unix_time(current_time).replace("T", " ").left(16)
		
		_all_candles.append({"t": t_str, "o": o, "h": h, "l": l, "c": c})
		price = c

# --- 对外公开接口 ---

# OrderOverlay 会调用这个方法来确定线画在哪里
func map_price_to_y_public(price: float) -> float:
	# 直接复用内部逻辑
	return _map_price_to_y(price)

# [修改] 现在接收 active 和 history 两个参数
func update_visual_orders(active: Array[OrderData], history: Array[OrderData] = []):
	if _order_layer:
		_order_layer.update_orders(active, history)

# [新增] 根据时间字符串获取屏幕 X 坐标
# 如果时间不在当前数据内，返回 -1
func get_x_by_time(time_str: String) -> float:
	if not _time_to_index_cache.has(time_str):
		return -1.0
	
	var target_index = _time_to_index_cache[time_str]
	
	# 反向计算 X 坐标
	# 逻辑参考 _draw 中的 calculation
	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	var start_index = max(0, _end_index - _visible_count)
	
	# 如果该索引不在可视范围内，虽然能算出来，但可以做个标记
	# 这里不仅算 X，还要算相对位置
	var relative_pos = target_index - start_index
	var x_pos = relative_pos * candle_full_width + candle_width / 2
	
	return x_pos

# --- KLineChart 新增辅助方法 ---

# 根据屏幕 X 坐标获取对应的时间字符串 (反向查询)
func get_time_at_x(x: float) -> String:
	var idx = _get_index_at_x(x)
	# 范围检查
	if idx < 0 or idx >= _all_candles.size():
		return ""
	return _all_candles[idx].t

# 根据屏幕 Y 坐标获取对应的价格 (反向查询)
func get_price_at_y(y: float) -> float:
	# 复用之前的 _get_price_at_y 逻辑
	return _get_price_at_y(y)

# [辅助] 暴露当前的 candle width 以便计算点击容差
func get_candle_width() -> float:
	return candle_width + spacing

# [新增公开接口] 只要能拿到 chart 就能开始画线
func start_drawing(tool_name: String):
	if _drawing_layer:
		_drawing_layer.start_tool(tool_name)

# [新增] 计算指标
func calculate_and_add_ma(period: int, color: Color):
	# 1. 提取收盘价数组
	var closes = []
	for candle in _all_candles:
		closes.append(candle.c)
		
	# 2. 计算
	var ma_data = IndicatorCalculator.calculate_sma(closes, period)
	
	# 3. 添加到图层
	if _indicator_layer:
		_indicator_layer.add_indicator(ma_data, color, 1.5)

# [新增] 图层需要的辅助查询接口
func get_first_visible_index() -> int:
	var vis_count = ceili(size.x / (candle_width + spacing))
	return max(0, _end_index - vis_count)

func get_last_visible_index() -> int:
	return _end_index

func get_x_by_index_public(idx: int) -> float:
	var candle_full_width = candle_width + spacing
	var start_idx = get_first_visible_index()
	var relative = idx - start_idx
	return relative * candle_full_width + candle_width / 2.0

# --- 网格层使用的接口 ---

func get_min_visible_price() -> float:
	return _min_visible_price

func get_max_visible_price() -> float:
	return _max_visible_price

# 获取指定 Index 的时间文本
func get_time_by_index_public(idx: int) -> String:
	if idx >= 0 and idx < _all_candles.size():
		return _all_candles[idx].t
	return ""

# --- 新增: 获取最后一根 K 线在屏幕上的中心 X 坐标
func get_last_candle_visual_x() -> float:
	if _all_candles.is_empty(): return 0.0

	# 复用现有的坐标计算逻辑
	# 最后一根数据的索引
	var last_data_idx = _all_candles.size() - 1
	return get_x_by_index_public(last_data_idx)

# --- 新增: 强制视图滚动到最右侧 (确保用户能看到正在生成的 K 线)
func scroll_to_end():
	_end_index = _all_candles.size() - 1
	_clamp_view() # 确保不越界
	queue_redraw()
