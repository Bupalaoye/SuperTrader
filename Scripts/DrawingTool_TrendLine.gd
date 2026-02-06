class_name DrawingTool_TrendLine
extends DrawingObject

func _init():
	# 趋势线默认两个点
	points = [{"t": "", "p": 0.0}, {"t": "", "p": 0.0}]
	color = Color.YELLOW

func draw(control: Control, chart: KLineChart):
	# 1. 将 Time/Price 转换为屏幕坐标
	var p1 = _get_screen_pos(points[0], chart)
	var p2 = _get_screen_pos(points[1], chart)
	
	# 如果坐标无效（比如尚未设置时间），不绘制
	if p1 == Vector2.INF or p2 == Vector2.INF:
		return

	# 2. 画线
	control.draw_line(p1, p2, color, width, true)
	
	# 3. 如果被选中，画手柄(圆点)
	if selected:
		control.draw_circle(p1, 5.0, Color.WHITE)
		control.draw_circle(p2, 5.0, Color.WHITE)

func is_hit(mouse_pos: Vector2, chart: KLineChart) -> bool:
	var p1 = _get_screen_pos(points[0], chart)
	var p2 = _get_screen_pos(points[1], chart)
	
	# 任何一个点无效，都不可能被点中
	if p1 == Vector2.INF or p2 == Vector2.INF: 
		return false
	
	# 【修复点】这里修正了函数名：on_segment -> to_segment
	var point_on_segment = Geometry2D.get_closest_point_to_segment(mouse_pos, p1, p2)
	
	# 判断鼠标距离线段的距离是否在容差范围内 (比如 10px)
	return mouse_pos.distance_to(point_on_segment) < 10.0

func get_handle_at(mouse_pos: Vector2, chart: KLineChart) -> int:
	var p1 = _get_screen_pos(points[0], chart)
	var p2 = _get_screen_pos(points[1], chart)
	
	if p1 != Vector2.INF and mouse_pos.distance_to(p1) < 10.0: 
		return 0
	if p2 != Vector2.INF and mouse_pos.distance_to(p2) < 10.0: 
		return 1
	return -1

# [内部辅助] 坐标转换
func _get_screen_pos(point_data: Dictionary, chart: KLineChart) -> Vector2:
	# 防御性检查：确保 chart 还在
	if not chart: return Vector2.INF
	
	var x = chart.get_x_by_time(point_data["t"])
	if x == -1: 
		# 如果时间找不到（可能是数据还没加载，或者在屏幕外太远）
		# 这里简单返回 INF 不绘制。
		# 进阶做法是根据索引推算屏幕外坐标，但比较复杂，先这样，
		return Vector2.INF
		
	var y = chart.map_price_to_y_public(point_data["p"])
	return Vector2(x, y)
