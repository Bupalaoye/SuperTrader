extends Node

# --- 节点引用 (Auto-Wiring) ---
# 只要你的场景树里节点名字叫这些，不需要手动连线，直接能跑
@onready var chart: KLineChart = %KLineChart 
@onready var file_dialog: FileDialog = %FileDialog
@onready var playback_timer: Timer = %Timer

# UI 按钮引用 (假设你把它们放在了一个叫 UI 的 CanvasLayer 下，或者直接在根节点下)
# 请根据实际路径修改，例如 %HBoxContainer/BtnLoad
@onready var btn_load: Button = %BtnLoad 
@onready var btn_play: Button = %BtnPlay
@onready var btn_speed: Button = %BtnSpeedUp

# --- 核心数据 ---
var full_history_data: Array = [] 
var current_playback_index: int = 0 
var is_playing: bool = false

func _ready():
	print("正在初始化控制器...")
	
	# --- 1. 自动连接信号 (Code-driven Signals) ---
	
	# 文件对话框信号
	if not file_dialog.file_selected.is_connected(_on_file_selected):
		file_dialog.file_selected.connect(_on_file_selected)
		
	# 计时器信号
	if not playback_timer.timeout.is_connected(_on_timer_tick):
		playback_timer.timeout.connect(_on_timer_tick)
		
	# UI 按钮信号
	if btn_load:
		btn_load.pressed.connect(func(): file_dialog.popup_centered(Vector2(800, 600)))
	else:
		printerr("警告: BtnLoad 节点未找到，请检查路径!")
		
	if btn_play:
		btn_play.pressed.connect(_toggle_play)
		
	if btn_speed:
		# 这里用匿名函数实现一个简易的切换速度逻辑
		btn_speed.pressed.connect(func(): 
			if playback_timer.wait_time > 0.1:
				playback_timer.wait_time = 0.05 # 极速
				print("速度: 极速 (20fps)")
			else:
				playback_timer.wait_time = 0.5 # 正常
				print("速度: 正常 (2fps)")
		)

	# --- 2. 初始化组件设置 ---
	
	# 配置 FileDialog
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.csv ; MT4 History", "*.txt ; Renamed CSV"]
	
	# 配置 Timer
	playback_timer.wait_time = 0.5 
	playback_timer.one_shot = false
	
	print("系统就绪! 点击 Load 按钮开始。")

# --- 逻辑处理 ---

func _on_file_selected(path: String):
	print("加载 CSV: ", path)
	
	# 停止旧的回放
	is_playing = false
	playback_timer.stop()
	
	# 加载数据
	var data = CsvLoader.load_mt4_csv(path)
	if data.is_empty(): return
	
	full_history_data = data
	
	# 初始化前 200 根
	var init_count = min(200, full_history_data.size())
	current_playback_index = init_count
	
	var init_data = full_history_data.slice(0, current_playback_index)
	chart.set_history_data(init_data)
	chart.jump_to_index(init_data.size() - 1)

func _toggle_play():
	if full_history_data.is_empty(): return
	
	is_playing = !is_playing
	if is_playing:
		playback_timer.start()
		btn_play.text = "Pause"
	else:
		playback_timer.stop()
		btn_play.text = "Play"

func _on_timer_tick():
	if current_playback_index >= full_history_data.size():
		is_playing = false
		playback_timer.stop()
		print("回放结束")
		return
	
	# 喂数据
	chart.append_candle(full_history_data[current_playback_index])
	current_playback_index += 1
