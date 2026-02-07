@tool
class_name ChartIndicator extends Resource

# --- 策划配置区 ---
@export_group("基础设置")
@export var indicator_name: String = "Indicator"  # 指标名称
@export var is_visible: bool = true:              # 是否开启
	set(value):
		is_visible = value
		emit_changed() # 通知编辑器或图表资源已变更，请求重绘

@export_group("视觉样式")
@export var color: Color = Color.WHITE
@export var line_width: float = 1.0

# --- 运行时数据区 ---
# 存储计算好的结果，避免每帧重复计算。
# 格式按需定义，通常是一个数组，对应每一根K线的值
var _cache_data: Array = [] 

# --- 接口定义 (虚函数) ---

## 1. 计算逻辑
## @param kline_data: 原始K线数据数组 (例如: [{open:10, close:12...}, ...])
## 当K线数据源更新时，主图表会调用此方法
func calculate(kline_data: Array) -> void:
	_cache_data.clear()
	# 子类必须重写具体的计算公式
	pass

## 2. 绘制逻辑
## @param control: 画布节点 (KLineChart 本身)，用于调用 draw_line
## @param transform_func: 一个 Callable 函数，用于将 (index, price) 转换为屏幕上的 (Vector2)
## transform_func 的签名应该是: func(param_index: int, param_price: float) -> Vector2
func draw(control: Control, transform_func: Callable, start_index: int, end_index: int) -> void:
	if not is_visible or _cache_data.is_empty():
		return
	# 子类必须重写具体的绘制循环
	pass

## 3. 增量计算逻辑 (可选: 当新增一根 K 线时，只需要更新最后的计算)
## @param kline_data: 完整的K线数据数组
## @param last_index: 新增的最后一根K线的索引
## 如果子类支持优化的增量计算，可以重写此方法
## 默认实现是直接调用 calculate() 重新计算全部
func calculate_incremental(kline_data: Array, last_index: int) -> void:
	# 默认实现：直接全量计算
	# 子类可以重写为只计算最后一个值的高效方法
	calculate(kline_data)

