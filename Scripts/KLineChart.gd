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

@export_group("Indicators")
@export var indicators: Array[ChartIndicator] = []

# --- 节点引用 ---
var _overlay: CrosshairOverlay
# --- 新增变量 ---
var _order_layer: OrderOverlay
var _drawing_layer: DrawingLayer
var _indicator_layer: IndicatorLayer
# 布林带配置状态 (是否启用、周期、倍数、颜色)
var _bb_settings = { "active": false, "period": 34, "color": Color.TEAL }
# [核心修复] 单一真理源：屏幕最左边是哪根K线？
var _calculated_start_index: int = 0
# 持久化缓存，避免每帧创建大数组
var _bb_cache: Dictionary = { "ub": [], "mb": [], "lb": [] }
# 标记是否已经把引用传给了 IndicatorLayer
var _bb_cache_linked: bool = false
# 持久化 Close 值缓存（与 _all_candles 索引对应），用于零拷贝增量计算
var _closes_cache: Array = []
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

# --- 新增：图表右侧留白与自动滚动配置 ---
var _max_right_buffer_bars: int = 50  # 允许向右拖出多少根空白 K 线
var _auto_scroll: bool = true  # 是否开启自动滚动
var _chart_shift_margin: int = 5  # 自动滚动时，右侧保留多少根空白间距

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
	
	# --- 8. 初始化指标系统 ---
	_setup_indicators()

func _setup_indicators():
	# 监听所有指标的资源变化信号
	for ind in indicators:
		if ind and not ind.changed.is_connected(queue_redraw):
			ind.changed.connect(queue_redraw)
	
	# 计算初始数据
	_recalculate_all_indicators()

func _recalculate_all_indicators():
	# 如果没有数据，跳过
	if _all_candles.is_empty():
		return
	
	# 通知所有指标重新计算，基于当前的 K 线数据
	for ind in indicators:
		if ind:
			ind.calculate(_all_candles)

func _draw():
	# 触发网格和辅助层重绘
	if _grid_layer: _grid_layer.queue_redraw()
	if _current_price_layer: _current_price_layer.queue_redraw()
	if _indicator_layer: _indicator_layer.queue_redraw()
	if _order_layer: _order_layer.queue_redraw()
	
	if _all_candles.is_empty():
		return

	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	
	# 1. [核心步骤] 统一计算可视范围，只在这里算一次！
	# 向上取整，保证屏幕边缘能多画半根，防止穿帮
	_visible_count = ceili(chart_width / candle_full_width)
	
	# 计算屏幕左边缘对应的索引 (Screen Left Index)
	# 逻辑：EndIndex 是屏幕右边缘的 K 线，往回推 VisibleCount 根
	# +1 是为了保证 EndIndex 也是可见的
	_calculated_start_index = _end_index - _visible_count + 1
	
	# 2. 计算价格轴范围 (Y轴缩放)
	_calculate_price_bounds(_calculated_start_index, _end_index)

	# 3. 绘制 K 线 (使用统一的坐标逻辑)
	# 遍历屏幕上每一根可能的柱子位置 (i from 0 to _visible_count)
	for i in range(_visible_count + 1): # 多画一根防止边缘闪烁
		
		var data_idx = _calculated_start_index + i
		
		# [边界检查] 超出数据范围（左侧无历史，或右侧留白区域）不画
		if data_idx < 0 or data_idx >= _all_candles.size():
			continue
			
		var candle = _all_candles[data_idx]
		
		# [核心修复] 直接调用 public 接口计算 X，确保与指标层 100% 对齐
		# 以前是 x = i * width，由偏差；现在走统一公式
		var center_x = get_x_by_index_public(data_idx)
		var x_pos = center_x - (candle_width / 2.0)
		
		# 绘制逻辑
		var y_open = _map_price_to_y(candle.o)
		var y_close = _map_price_to_y(candle.c)
		var y_high = _map_price_to_y(candle.h)
		var y_low = _map_price_to_y(candle.l)
		
		var is_bull = candle.c >= candle.o
		var color = bull_color if is_bull else bear_color
		
		# 画影线
		draw_line(Vector2(center_x, y_high), Vector2(center_x, y_low), wick_color, 1.0)
		
		# 画实体
		var rect_top = min(y_open, y_close)
		var rect_height = abs(y_close - y_open)
		if rect_height < 1.0: rect_height = 1.0 
		
		draw_rect(Rect2(x_pos, rect_top, candle_width, rect_height), color)
	
	# === 绘制指标系统 ===
	if indicators.size() > 0:
		# 创建坐标转换函数，绑定到当前 KLineChart 实例
		var transformer = Callable(self, "get_screen_coord_for_indicator")
		
		# 遍历所有指标
		for ind in indicators:
			if ind and ind.is_visible:
				# 调用指标的绘制方法
				ind.draw(self, transformer, _calculated_start_index, _end_index)

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
	
	# 稍微加个阈值，别让轻微抖动就触发
	if abs(delta_x) > 2.0:
		# 既然用户在手动拖拽，暂时禁用自动滚动
		_auto_scroll = false
	
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

## 指标的坐标转换函数 (解耦的关键)
## 接收 (K线索引, 价格值) -> 返回 (屏幕坐标 Vector2)
## 这是指标系统与主图表通信的核心接口
func get_screen_coord_for_indicator(idx: int, price: float) -> Vector2:
	var x = get_x_by_index_public(idx)
	var y = _map_price_to_y(price)
	return Vector2(x, y)

func _calculate_price_bounds(start_idx: int, end_idx: int):
	var min_p = 99999999.0
	var max_p = -99999999.0
	var has_data = false

	# 只遍历真实存在的数据 range
	var real_start = max(0, start_idx)
	var real_end = min(end_idx, _all_candles.size() - 1)
	
	if real_start <= real_end:
		for i in range(real_start, real_end + 1):
			var c = _all_candles[i]
			if c.l < min_p: min_p = c.l
			if c.h > max_p: max_p = c.h
			has_data = true

	if not has_data:
		# 如果视口全是空的(比如拖太远了)，就用上一次的范围或者默认值
		if _min_visible_price == 0 and _max_visible_price == 0:
			min_p = 0.0; max_p = 1.0
		else:
			return # 保持现有范围不变

	if has_data:
		# 关键优化：动态扩展边界（Padding）
		var range_diff = max_p - min_p
		if range_diff == 0: range_diff = 0.0001

		var padding = range_diff * 0.1 # 上下各留 10%

		_min_visible_price = min_p - padding
		_max_visible_price = max_p + padding
		_price_range = _max_visible_price - _min_visible_price

func _zoom_chart(factor: float):
	candle_width *= factor
	candle_width = clamp(candle_width, 1.0, 100.0)
	queue_redraw()

func _clamp_view():
	if _all_candles.is_empty():
		_end_index = 0
		return
	
	var max_idx = _all_candles.size() - 1
	
	# [关键修改] 允许视图向右超出数据范围 (制造右侧空白)
	# 最小不能小于 0
	# 最大允许：数据尽头 + 我们允许的缓冲空地
	var absolute_max = max_idx + _max_right_buffer_bars
	
	_end_index = clamp(_end_index, 0, absolute_max)

func set_history_data(data: Array):
	_all_candles = data
	_end_index = data.size() - 1
	
	# [新增] 重建缓存
	_time_to_index_cache.clear()
	for i in range(data.size()):
		var t_str = data[i].t
		_time_to_index_cache[t_str] = i

	# 同步 closes 缓存
	_closes_cache.clear()
	for c in _all_candles:
		_closes_cache.append(c.c)

	# 全量计算布林带（仅在加载历史时执行一次）
	_recalculate_indicators_full()
	
	# === 指标系统：重新计算所有指标 ===
	_recalculate_all_indicators()

	queue_redraw()

func append_candle(data: Dictionary):
	_all_candles.append(data)
	
	# [新增] 更新缓存
	_time_to_index_cache[data.t] = _all_candles.size() - 1
	
	# 同步 closes 缓存（零拷贝追加）
	_closes_cache.append(data.c)

	# 新增：新 K 线生成后进行增量追加计算
	_append_indicators_incremental()
	
	# [核心修改] 自动滚动逻辑
	if _auto_scroll:
		_snap_to_latest()
	else:
		queue_redraw()

# [新增] 更新现价线 (支持倒计时)
func update_current_price(price: float, seconds_left: int = 0):
	if _current_price_layer:
		# 调用新的 update_info 接口
		_current_price_layer.update_info(price, seconds_left)

# [新增] 更新最后一根 K 线的数据 (用于模拟 Tick 波动)
func update_last_candle(data: Dictionary):
	if _all_candles.is_empty(): return

	# 1. 更新数据源
	var last_idx = _all_candles.size() - 1
	_all_candles[last_idx] = data

	# 同步 closes 缓存（原地修改，零分配）
	if _closes_cache.size() == _all_candles.size():
		_closes_cache[last_idx] = data.c
	else:
		# 防御性处理：保持一致
		_closes_cache.clear()
		for c in _all_candles:
			_closes_cache.append(c.c)

	# 2. [关键] 强制重新计算视野
	# 必须重新扫描当前屏幕，因为这根 K 线可能刚刚创了新高，撑大了 Y 轴
	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	var vis_count = ceili(chart_width / candle_full_width)
	var start_idx = max(0, _end_index - vis_count)

	# 重算边界 (这将触发 Y 轴缩放)
	_calculate_price_bounds(start_idx, _end_index)

	# 3. 在重绘前，进行增量更新（只计算最后一个点）
	_update_indicators_incremental()

	# 4. 处理自动滚动
	if _auto_scroll:
		_snap_to_latest()
	else:
		queue_redraw()

	# 5. 联动更新其他层
	if _order_layer: _order_layer.queue_redraw()
	if _current_price_layer: _current_price_layer.queue_redraw()
	# 把最新的价格和 K 线 X 坐标发给现价线
	if _current_price_layer:
		# 这里假设 update_last_candle 使用时，外部会同步调用 update_current_price
		# 所以这里只要让它重绘就行
		pass

# --- 新增: 辅助逻辑 _snap_to_latest (吸附到最新K线并留白) ---
func _snap_to_latest():
	if _all_candles.is_empty(): return
	
	# 计算目标索引：最新K线索引 + 留白数量
	# 比如有 100 根线，允许留白 5 根，目标 end_index 就是 104
	# 这样第 99 根线（最新）就会显示在屏幕靠右的位置，右边空出 5 格
	var target_end = (_all_candles.size() - 1) + _chart_shift_margin
	
	_end_index = target_end
	_clamp_view() # 确保不超出 _max_right_buffer_bars 的限制
	queue_redraw()

# --- 修改: 强制视图滚动到最右侧 ---
# [修复] 确保全文件只有这一个 scroll_to_end 函数
func scroll_to_end():
	# 既然用户强制请求滚动到底部，我们默认开启自动滚动
	_auto_scroll = true
	_snap_to_latest()

# --- 跳转到指定索引 (用于回放/历史查看) ---
func jump_to_index(idx: int):
	# 跳转意味着用户在手动操作，暂时关闭自动滚动
	_auto_scroll = false 
	_end_index = idx
	_clamp_view()
	queue_redraw()

# --- [新增接口] 供 Controller 控制 Auto Scroll ---
func set_auto_scroll(enabled: bool):
	_auto_scroll = enabled
	if enabled:
		_snap_to_latest()

# --- [新增接口] 供 Controller 控制 Chart Shift (留白) ---
func toggle_chart_shift(enabled: bool):
	# 简单的逻辑：如果开启 Shift，就留 5 根空位，否则留 0 根
	# 你可以根据喜好调整这个数字 5 => 10 或者更多
	_chart_shift_margin = 10 if enabled else 0
	
	# 如果当前正在自动滚动，立即应用留白
	if _auto_scroll:
		_snap_to_latest()
	else:
		# 如果没滚动，只刷新界面，等下次从自动滚动触发时生效，或者手动拖拽
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


# -------------------------
# Bollinger Band Controls
# -------------------------

# [\u91cd构] 接口签名修改：移除 k 参数
func set_bollinger_visible(active: bool, period: int = 34, color: Color = Color.CYAN):
	_bb_settings.active = active
	_bb_settings.period = period
	# [清理] _bb_settings.k = k  <-- 删除这行
	_bb_settings.color = color

	if active:
		_recalculate_indicators_full()
	else:
		_bb_cache = { "ub": [], "mb": [], "lb": [] }
		_bb_cache_linked = false
		if _indicator_layer:
			_indicator_layer.clear_indicators()

func _recalculate_indicators():
	# 兼容旧名字：保留但转发到全量函数
	_recalculate_indicators_full()


func _recalculate_indicators_full():
	if not _bb_settings.active or not _indicator_layer:
		return
	if _all_candles.is_empty():
		return

	# [CHANGED] 不再只提取 Closes，而是直接把整个 candles 数组传给新算法
	# 算法内部会提取 High/Low/Close
	var period = _bb_settings.period # 34

	# 调用新的 EMA Channel 算法
	var result = IndicatorCalculator.calculate_ema_channel(_all_candles, period)

	# 更新缓存 (保持结构 ub/mb/lb 不变，IndicatorLayer 依然能画出三青线)
	_bb_cache = result

	# 链接图层
	if _indicator_layer:
		# 这里的 "MAIN_BB" 可以改个名，但为了不破坏 IndicatorLayer 的逻辑，保持 key 不变没问题
		_indicator_layer.update_band_indicator("MAIN_BB", _bb_cache, _bb_settings.color, 1.0)
		_bb_cache_linked = true


func _update_indicators_incremental():
	if not _bb_settings.active or _all_candles.is_empty(): return

	var last_idx = _all_candles.size() - 1
	var period = _bb_settings.period

	# 如果历史数据不足以形成 EMA，跳过
	if last_idx < period: return

	# 1. 获取上一根 (Index - 1) 的 EMA 值
	# 注意：_bb_cache["ub"] 长度通常等于 _all_candles 长度
	var prev_idx = last_idx - 1
	if prev_idx < 0: return

	# 安全检查：确保缓存数组够长
	if _bb_cache["ub"].size() <= prev_idx: return

	var prev_ub = _bb_cache["ub"][prev_idx]
	var prev_lb = _bb_cache["lb"][prev_idx]
	var prev_mb = _bb_cache["mb"][prev_idx]

	# 2. 获取当前 K 线数据
	var curr_candle = _all_candles[last_idx]

	# 3. [CHANGED] 调用新的增量算法
	var val = IndicatorCalculator.calculate_ema_channel_at_index(curr_candle, prev_ub, prev_lb, prev_mb, period)

	# 4. 填充或更新缓存
	# 确保数组长度足以容纳 new_idx
	if _bb_cache["ub"].size() <= last_idx:
		_bb_cache["ub"].append(NAN)
		_bb_cache["mb"].append(NAN)
		_bb_cache["lb"].append(NAN)

	# 原地修改
	_bb_cache["ub"][last_idx] = val.ub
	_bb_cache["mb"][last_idx] = val.mb
	_bb_cache["lb"][last_idx] = val.lb

	# 通知重绘
	if _indicator_layer: _indicator_layer.queue_redraw()


func _append_indicators_incremental():
	# 在追加新 K 线后，调用增量更新（会执行 append 或修改最后一位）
	if not _bb_settings.active: return
	_update_indicators_incremental()
	
	# === 指标系统：增量计算 ===
	_append_indicators_incremental_new()

func _append_indicators_incremental_new():
	# 为新指标系统提供增量计算支持
	if _all_candles.is_empty():
		return
	
	var last_index = _all_candles.size() - 1
	
	for ind in indicators:
		if ind:
			# 调用指标的增量计算方法
			ind.calculate_incremental(_all_candles, last_index)

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
		# [修复] 改为调用具体的 add_line_indicator
		_indicator_layer.add_line_indicator(ma_data, color, 1.5)

# [新增] 专门用于绘制趋势过滤线 (EMA 200)
# data: float 数组 (与 K 线数量对应)
# color: 线的颜色
func add_trend_line_data(data: Array, color: Color = Color.ORANGE, width: float = 2.0):
	if _indicator_layer:
		# 使用 Key 机制，确保多次调用（如重置时）能覆盖旧的，而不是一直叠加
		# 我们复用 IndicatorLayer 的 update_band_indicator 逻辑
		# 这里 trick 是利用 Band 指标的 'mb' (中轨) 来画单线，
		# update_band_indicator 支持 key 替换，这样就不会重复添加线条了
		
		_indicator_layer.update_band_indicator("TREND_EMA_200", {"mb": data}, color, width)
		print(">> 图表已加载趋势过滤器 (EMA 200)")

# [新增] 图层需要的辅助查询接口
# [核心修复] 所有外部图层询问 "第 N 根 K 线在哪里" 时，必须依据 _calculated_start_index
func get_x_by_index_public(idx: int) -> float:
	var candle_full_width = candle_width + spacing
	
	# 相对位置 = 目标索引 - 屏幕最左索引
	var relative_idx = idx - _calculated_start_index
	
	# 屏幕 X = 相对位置 * 宽度 + 半宽偏移 (因为我们要的是中心点)
	return (relative_idx * candle_full_width) + (candle_width / 2.0)

# [核心修复] 获取屏幕最左侧索引
func get_first_visible_index() -> int:
	return _calculated_start_index

# [核心修复] 获取屏幕最右侧索引
func get_last_visible_index() -> int:
	return _end_index

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

# [新增] 计算并添加布林带
func calculate_and_add_bollinger(period: int = 20, multiplier: float = 2.0, color: Color = Color.CYAN):
	# 1. 准备数据
	# 为了提高效率，这里最好只提取 Close 数组
	var closes = []
	for c in _all_candles:
		closes.append(c.c)
	
	if closes.is_empty(): return

	# 2. 计算 (调用 IndicatorCalculator)
	var result_dict = IndicatorCalculator.calculate_bollinger_bands(closes, period, multiplier)
	
	# 3. 添加到图层 (新接口)
	# 指标层的 add_band_indicator 会自动处理半透明填充
	if _indicator_layer:
		# 旧接口是 add_indicator，我们需要兼容或区分
		# 这里我们直接修改 _indicator_layer 的代码，所以直接用
		_indicator_layer.add_band_indicator(result_dict, color, 1.0)
		
	print("已添加布林带: N=%d, K=%.1f" % [period, multiplier])

# [新增] 计算并显示分型 (Fractals)
func calculate_and_add_fractals():
	if _all_candles.size() < 5: return
	
	# 1. 计算
	var result = IndicatorCalculator.calculate_fractals(_all_candles)
	
	# result = {"highs": {index: price}, "lows": {index: price}}
	
	if _indicator_layer:
		# 2. 绘制顶分型 (红色向下箭头)
		# is_up_arrow = false
		_indicator_layer.add_marker_indicator(result.highs, Color.RED, false)
		
		# 3. 绘制底分型 (绿色向上箭头)
		# is_up_arrow = true
		_indicator_layer.add_marker_indicator(result.lows, Color.GREEN, true)
		
	print("已添加分型标记 (Fractals)")
