import os
from datetime import datetime


def get_directory_structure(root_path, indent="", max_depth=None, current_depth=0):
    """
    生成目录结构的字符串表示。

    Args:
        root_path (str): 要扫描的根目录路径
        indent (str): 用于缩进的字符串
        max_depth (int, optional): 最大扫描深度，None表示无限制
        current_depth (int): 当前扫描深度

    Returns:
        str: 格式化的目录结构字符串
    """
    if max_depth is not None and current_depth > max_depth:
        return ""

    structure = []
    try:
        # 获取目录内容并排序
        items = sorted(os.listdir(root_path))

        for item in items:
            item_path = os.path.join(root_path, item)

            # 构建显示的路径（相对路径）
            if os.path.isdir(item_path):
                structure.append(f"{indent}📁 {item}/")
                # 递归处理子目录
                sub_structure = get_directory_structure(
                    item_path, indent + "    ", max_depth, current_depth + 1
                )
                if sub_structure:
                    structure.append(sub_structure)
            else:
                # 只显示.cs文件
                if item.endswith(".cs"):
                    structure.append(f"{indent}📄 {item}")

    except Exception as e:
        structure.append(f"{indent}Error accessing {root_path}: {str(e)}")

    return "\n".join(structure)


def merge_cs_files(source_folder, output_file):
    """
    递归合并指定文件夹及其所有子文件夹下所有 .cs 文件的内容到一个 txt 文件中，
    并在文件开头添加目录结构。

    Args:
        source_folder (str): 包含 .cs 文件的根文件夹路径
        output_file (str): 输出的 txt 文件路径
    """
    if not os.path.isdir(source_folder):
        print(f"错误：文件夹 '{source_folder}' 不存在。请检查路径是否正确。")
        return

    try:
        with open(output_file, "w", encoding="utf-8") as outfile:
            # 写入文件头部信息
            outfile.write("=" * 50 + "\n")
            outfile.write("项目文件结构与代码合并报告\n")
            outfile.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            outfile.write("=" * 50 + "\n\n")

            # 写入项目结构
            outfile.write("项目目录结构:\n")
            outfile.write("=" * 20 + "\n")
            directory_structure = get_directory_structure(source_folder)
            outfile.write(directory_structure)
            outfile.write("\n\n" + "=" * 50 + "\n")
            outfile.write("文件内容合并:\n")
            outfile.write("=" * 50 + "\n\n")

            # 计数器
            total_files = 0
            total_lines = 0

            # 使用 os.walk() 递归遍历目录树
            for root, _, files in os.walk(source_folder):
                for filename in sorted(files):
                    if filename.endswith(".gd"):
                        file_path = os.path.join(root, filename)
                        relative_path = os.path.relpath(file_path, source_folder)

                        print(f"  正在处理: {relative_path}")

                        # 写入文件分隔符和元数据
                        outfile.write(f"\n{'=' * 20}\n")
                        outfile.write(
                            f"// 文件路径: {relative_path.replace('\\', '/')}\n"
                        )

                        # 获取文件基本信息
                        file_stats = os.stat(file_path)
                        file_size = file_stats.st_size
                        file_modified = datetime.fromtimestamp(file_stats.st_mtime)

                        outfile.write(f"// 文件大小: {file_size} bytes\n")
                        outfile.write(
                            f"// 修改时间: {file_modified.strftime('%Y-%m-%d %H:%M:%S')}\n"
                        )
                        outfile.write(f"{'=' * 20}\n\n")

                        # 读取并写入文件内容
                        with open(file_path, "r", encoding="utf-8") as infile:
                            content = infile.read()
                            outfile.write(content)
                            outfile.write("\n")

                            # 更新计数器
                            total_files += 1
                            total_lines += len(content.splitlines())

            # 写入统计信息
            outfile.write("\n" + "=" * 50 + "\n")
            outfile.write("统计信息:\n")
            outfile.write(f"总文件数: {total_files}\n")
            outfile.write(f"总代码行数: {total_lines}\n")
            outfile.write("=" * 50 + "\n")

        print(f"\n成功！已生成项目报告和代码合并到 '{output_file}'")
        print(f"合并了 {total_files} 个文件，共 {total_lines} 行代码")

    except Exception as e:
        print(f"处理过程中发生错误: {e}")


if __name__ == "__main__":
    # --- 用户配置 ---
    source_directory = (
        r"C:\Users\Dola\Documents\UnityProj\SuperTrader\Scripts"
    )

    merged_filename = "project_report.txt"

    # 获取脚本所在的目录，并构造完整的输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_file_path = os.path.join(script_dir, merged_filename)

    # --- 执行合并 ---
    merge_cs_files(source_directory, output_file_path)
