extends Control
class_name KLineChart

# --- 配置参数 ---
@export_group("Visual Settings")
@export var candle_width: float = 8.0 # K线宽度
@export var spacing: float = 2.0 # 间隙
@export var bull_color: Color = Color.hex(0x00FF00FF) # 涨 (绿)
@export var bear_color: Color = Color.hex(0xFF0000FF) # 跌 (红)
@export var wick_color: Color = Color.WHITE # 影线颜色
@export var bg_color: Color = Color.hex(0x111111FF) # 背景黑

# --- 数据存储 ---
# 定义数据结构 (使用 Dictionary 比 Object 轻量一点，但在 Godot 4 中 Typed Class 性能更好，为了通用性这里用 Dictionary)
# 结构: { "o": float, "h": float, "l": float, "c": float }
var _all_candles: Array = [] 
var _visible_count: int = 100 # 当前屏幕能放下多少根

# --- 视图状态 ---
var _end_index: int = 0 # 屏幕最右侧对应的是第几根K线（数据索引）
var _max_visible_price: float = 0.0
var _min_visible_price: float = 0.0
var _price_range: float = 1.0

# --- 交互状态 ---
var _is_dragging: bool = false
var _drag_start_x: float = 0.0
var _drag_start_index: int = 0
var _zoom_speed: float = 1.0

# --- 信号 ---
signal chart_updated

func _ready():
	# 初始化测试数据 (如果没有 CSV，先生成数学正弦波数据测试)
	_generate_test_data()
	# 初始定位到最新数据
	_end_index = _all_candles.size() - 1

func _draw():
	# 1. 绘制背景
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	
	if _all_candles.is_empty():
		return

	# 2. 计算可见区域的数据索引
	# 这里的逻辑是：屏幕最右边是 _end_index
	var chart_width = size.x
	var candle_full_width = candle_width + spacing
	
	# 计算屏幕能容纳多少根
	_visible_count = ceili(chart_width / candle_full_width)
	
	var start_index = max(0, _end_index - _visible_count)
	var count = _end_index - start_index
	if count <= 0: return

	# 3. 动态计算当前可见区域的最高/最低价 (为了做 Y 轴自适应，像 MT4 那样)
	_calculate_price_bounds(start_index, _end_index)

	# 4. 循环绘制每一根可见 K 线
	for i in range(count):
		var data_idx = start_index + i
		var candle = _all_candles[data_idx]
		
		# X 坐标计算
		# 屏幕最右边是 size.x. 
		# 第 i 根的位置 = 屏幕右边 - (总数 - i) * 宽度
		# 或者：左边位置 = i * 宽度
		# 为了符合 MT4 习惯（最右边是新数据），我们通常从右向左推算，或者从左向右画
		var x_pos = i * candle_full_width
		
		# Y 坐标映射 (Price -> Pixel)
		var y_open = _map_price_to_y(candle.o)
		var y_close = _map_price_to_y(candle.c)
		var y_high = _map_price_to_y(candle.h)
		var y_low = _map_price_to_y(candle.l)
		
		var is_bull = candle.c >= candle.o
		var color = bull_color if is_bull else bear_color
		
		# 绘制影线 (Line)
		# draw_line 第一个参数是起点，第二个是终点
		var center_x = x_pos + candle_width / 2
		draw_line(Vector2(center_x, y_high), Vector2(center_x, y_low), wick_color, 1.0)
		
		# 绘制实体 (Rect)
		# 注意：Godot 的 draw_rect 高度不能为负，且 Y 轴向下
		var rect_top = min(y_open, y_close)
		var rect_height = abs(y_close - y_open)
		# 防止十字星看不见，给个最小高度
		if rect_height < 1.0: rect_height = 1.0 
		
		draw_rect(Rect2(x_pos, rect_top, candle_width, rect_height), color)

# --- 核心辅助逻辑 ---

# 价格转屏幕 Y 坐标
func _map_price_to_y(price: float) -> float:
	if _price_range == 0: return size.y / 2
	# (价格 - 最低价) / 范围 = 0~1 的比例
	var ratio = (price - _min_visible_price) / _price_range
	# 屏幕坐标系 Y 向下，价格越高 Y 越小，需要反转 (1.0 - ratio)
	# 留出 5% 的上下边距 padding
	var padding = size.y * 0.05
	var render_height = size.y * 0.9
	return padding + (1.0 - ratio) * render_height

# 计算这种可见范围内的最大最小值
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

# --- 交互逻辑 (Input Handling) ---

func _gui_input(event):
	# 1. 缩放 (鼠标滚轮)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_chart(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_chart(0.9)
			
		# 2. 拖拽开始/结束 (鼠标中键或左键)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_start_x = event.position.x
				_drag_start_index = _end_index
			else:
				_is_dragging = false

	# 3. 拖拽过程
	if event is InputEventMouseMotion and _is_dragging:
		var delta_x = event.position.x - _drag_start_x
		var candle_full_width = candle_width + spacing
		# 移动了多少根 K 线
		var move_count = int(delta_x / candle_full_width)
		
		# 拖拽时，向右拖动看历史 (index 减小)，向左拖动看未来 (index 增加)
		# 注意这里逻辑反一下，因为我们是拖动视图
		_end_index = _drag_start_index - move_count
		_clamp_view()
		queue_redraw()

func _zoom_chart(factor: float):
	candle_width *= factor
	# 限制一下大小
	candle_width = clamp(candle_width, 1.0, 100.0)
	queue_redraw()

func _clamp_view():
	# 限制 end_index 不越界
	_end_index = clamp(_end_index, 0, _all_candles.size() - 1)

# --- 外部接口：回放用 ---

# 设置所有历史数据
func set_history_data(data: Array):
	_all_candles = data
	_end_index = data.size() - 1
	queue_redraw()

# 追加新的一根 K 线 (模拟实时数据或回放推进)
func append_candle(data: Dictionary):
	_all_candles.append(data)
	# 如果用户正在看最新的位置，自动跟随
	if _end_index == _all_candles.size() - 2:
		_end_index += 1
	queue_redraw()

# 强制跳转到某一个索引 (回放控制)
func jump_to_index(idx: int):
	_end_index = idx
	_clamp_view()
	queue_redraw()

# --- 测试数据生成器 ---
func _generate_test_data():
	var price = 100.0
	for i in range(2000):
		var change = randf_range(-2.0, 2.0)
		var o = price
		var c = price + change
		var h = max(o, c) + randf_range(0.0, 1.0)
		var l = min(o, c) - randf_range(0.0, 1.0)
		
		# 简单的 Dictionary 结构
		_all_candles.append({
			"t": i, "o": o, "h": h, "l": l, "c": c
		})
		price = c
