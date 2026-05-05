# -*- coding: utf-8 -*-
"""
Created on Sun Mar  1 16:45:01 2026

@author: xiwangxiang
"""

import os
import json

def check_json_files(directory='.', recursive=True):
    """
    检查指定目录下所有.json文件的格式。

    :param directory: 要检查的目录，默认为当前目录
    :param recursive: 是否递归子目录，默认为True
    """
    total_files = 0
    error_files = 0

    if recursive:
        # 递归遍历所有子目录
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith('.json'):
                    total_files += 1
                    filepath = os.path.join(root, file)
                    if not check_single_json(filepath):
                        error_files += 1
    else:
        # 仅检查当前目录
        for file in os.listdir(directory):
            if file.endswith('.json'):
                filepath = os.path.join(directory, file)
                if os.path.isfile(filepath):
                    total_files += 1
                    if not check_single_json(filepath):
                        error_files += 1

    print(f"\n检查完成。共发现 {total_files} 个JSON文件，其中 {error_files} 个存在格式错误。")

def check_single_json(filepath):
    """检查单个JSON文件，返回True表示格式正确，False表示错误"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            json.load(f)
        print(f"✅ 格式正确: {filepath}")
        return True
    except json.JSONDecodeError as e:
        print(f"❌ 格式错误: {filepath} - {e}")
        return False
    except Exception as e:
        print(f"⚠️ 读取失败: {filepath} - {e}")
        return False

if __name__ == "__main__":
    # 运行检查（默认递归当前目录）
    check_json_files()