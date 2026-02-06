class_name DrawingLayer
extends Control

# --- 状态定义 ---
enum State { IDLE, CREATING, DRAGGING_HANDLE, MOVING_OBJ }

# --- 依赖 ---
var _chart: KLineChart

# --- 数据 ---
var _drawings: Array[DrawingObject] = []
var _current_state: State = State.IDLE

# --- 交互缓存 ---
var _active_tool: DrawingObject = null # 当前正在创建或操作的对象
var _drag_handle_index: int = -1
var _last_mouse_pos: Vector2 = Vector2.ZERO

func setup(chart: KLineChart):
	_chart = chart
	mouse_filter = MouseFilter.MOUSE_FILTER_PASS # 必须允许鼠标事件通过(但也拦截)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# 开启焦点模式，允许点击时获取焦点以接收键盘事件
	focus_mode = Control.FOCUS_CLICK

# --- 核心入口：开始画线 ---
func start_tool(tool_type_name: String):
	_current_state = State.CREATING
	
	# 工厂模式简化版
	if tool_type_name == "TrendLine":
		_active_tool = DrawingTool_TrendLine.new()
	
	_drawings.append(_active_tool)
	
	# 初始化第一个点为无效，等待第一次点击
	_active_tool.points[0].t = "" 
	print("画图模式: 请点击屏幕确定起点")

# --- 绘图循环 ---
func _draw():
	if not _chart: return
	
	# 绘制所有已存在的对象
	for obj in _drawings:
		obj.draw(self, _chart)

# --- 事件处理 (重中之重) ---
func _gui_input(event):
	if not _chart: return
	
	# 键盘事件监听 (删除功能)
	if event is InputEventKey:
		if event.pressed and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
			_delete_selected_drawing()
			accept_event() # 阻止事件传播
			return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 点击时抢占焦点，以接收后续的键盘事件
				grab_focus()
				_on_mouse_down(event.position)
			else:
				_on_mouse_up()
				
	elif event is InputEventMouseMotion:
		_on_mouse_move(event.position)

func _on_mouse_down(pos: Vector2):
	var data = _get_chart_data(pos)
	if data.t == "": return # 点击无效区域
	
	match _current_state:
		State.IDLE:
			# 1. 检查是否点中 Handle (准备拖拽变形)
			for obj in _drawings:
				if obj.selected:
					var handle = obj.get_handle_at(pos, _chart)
					if handle != -1:
						_current_state = State.DRAGGING_HANDLE
						_active_tool = obj
						_drag_handle_index = handle
						accept_event()
						return
			
			# 2. 检查是否点中对象 (选中)
			var hit_any = false
			for obj in _drawings:
				if obj.is_hit(pos, _chart):
					_deselect_all()
					obj.selected = true
					_active_tool = obj # 暂存，可能后续用于整体拖拽
					hit_any = true
					queue_redraw()
					accept_event()
					return
			
			# 3. 点击空白处，取消选中
			if not hit_any:
				_deselect_all()
				queue_redraw()

		State.CREATING:
			# 第一次点击：确定起点
			if _active_tool.points[0].t == "":
				_active_tool.points[0] = data
				_active_tool.points[1] = data # 终点先重合
				print("起点已定，请点击终点")
			else:
				# 第二次点击：确定终点，结束创建
				_active_tool.points[1] = data
				_active_tool.selected = true
				_finish_creation()
			accept_event()

func _on_mouse_move(pos: Vector2):
	var data = _get_chart_data(pos)
	if data.t == "": return
	
	match _current_state:
		State.CREATING:
			# 还没定起点时，没动作
			if _active_tool.points[0].t == "": return
			# 定了起点，终点跟随鼠标预览
			_active_tool.points[1] = data
			queue_redraw()
			
		State.DRAGGING_HANDLE:
			# 修改对应点的坐标
			_active_tool.points[_drag_handle_index] = data
			queue_redraw()

func _on_mouse_up():
	if _current_state == State.DRAGGING_HANDLE:
		_current_state = State.IDLE
		_drag_handle_index = -1

# --- 辅助 ---
func _get_chart_data(pos: Vector2) -> Dictionary:
	return {
		"t": _chart.get_time_at_x(pos.x),
		"p": _chart.get_price_at_y(pos.y)
	}

func _deselect_all():
	for obj in _drawings:
		obj.selected = false

func _delete_selected_drawing():
	"""删除当前选中的所有对象"""
	var did_delete = false
	# 倒序遍历，安全删除
	for i in range(_drawings.size() - 1, -1, -1):
		if _drawings[i].selected:
			_drawings.remove_at(i)
			did_delete = true
	
	if did_delete:
		print("已删除选中对象")
		_active_tool = null
		_current_state = State.IDLE
		queue_redraw()

func _finish_creation():
	print("画图完成")
	_current_state = State.IDLE
	_active_tool = null
	queue_redraw()
