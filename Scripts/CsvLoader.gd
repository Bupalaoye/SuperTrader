class_name CsvLoader
extends RefCounted # 相当于 C# 的纯类，不继承 Node，轻量级

static func load_mt4_csv(file_path: String) -> Array:
	var result_data: Array = []
	
	# 1. 打开文件 (支持 res:// 或 绝对路径)
	if not FileAccess.file_exists(file_path):
		printerr("错误：找不到文件 -> ", file_path)
		return []
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	
	# 2. 读取第一行，判断是否是表头
	# MT4 导出通常第一行是 header，如果是纯数据则不需要这一步
	var first_line = file.get_csv_line()
	
	# 简单的启发式检查：如果第一列包含字母，大概率是表头，跳过
	if first_line.size() > 0 and first_line[0].is_valid_float() == false:
		print("检测到表头，已跳过: ", first_line)
	else:
		# 如果第一行就是数据，我们需要把文件指针重置，或者手动处理这行数据
		# 为了简单，这里假设你刚才读掉的是 Header。
		# 如果你的 CSV 没有 Header，把上面 file.get_csv_line() 注释掉即可。
		pass

	# 3. 循环读取
	while not file.eof_reached():
		var line = file.get_csv_line()
		
		# 这是一个空行保护 (许多 CSV 最后一行是空的)
		if line.size() < 6:
			continue
			
		# 解析逻辑: MT4 格式 -> 字典
		# line 数组: [0]Date, [1]Time, [2]Open, [3]High, [4]Low, [5]Close, [6]Vol
		
		var open_p = float(line[2])
		var high_p = float(line[3])
		var low_p = float(line[4])
		var close_p = float(line[5])
		
		# 构造符合 KLineChart 要求的字典结构
		var candle = {
			"t": line[0] + " " + line[1], # 时间字符串
			"o": open_p,
			"h": high_p,
			"l": low_p,
			"c": close_p
		}
		
		result_data.append(candle)
		
	print("成功加载数据: %d 条" % result_data.size())
	return result_data
