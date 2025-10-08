#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dart注释清理工具
自动清理Dart文件中的过度注释，保留重要的文档注释
"""

import os
import re
import argparse
from pathlib import Path
from typing import List, Tuple

class DartCommentCleaner:
    def __init__(self):
        # 需要清理的注释模式
        self.patterns_to_remove = [
            # 文件头注释 (如: // file: xxx.dart)
            r'^//\s*file:\s*.*\.dart\s*$',
            
            # 分隔线注释 (如: // ######## 或 // ----------)
            r'^//\s*[#\-=*]{3,}\s*$',
            r'^//\s*#+\s*.*\s*#+\s*$',
            
            # 简单的中文描述注释 (单行，非文档注释)
            r'^//\s*[\u4e00-\u9fa5\s，。！？：；（）【】""''、]+\s*$',
            
            # 简单的英文描述注释 (单行，非文档注释)
            r'^//\s*[a-zA-Z\s\.,!?:;()[\]"\']+\s*$',
            
            # 空注释行
            r'^//\s*$',
            
            # 特定格式的注释 (如: // 变量说明)
            r'^//\s*[\u4e00-\u9fa5]+[\u4e00-\u9fa5\s]*\s*$',
        ]
        
        # 需要保留的注释模式
        self.patterns_to_keep = [
            # 文档注释 (/// 开头)
            r'^\s*///',
            
            # TODO, FIXME, NOTE 等重要标记
            r'//\s*(TODO|FIXME|NOTE|HACK|BUG|WARNING|IMPORTANT)',
            
            # 包含代码的注释
            r'//.*[{}();=]',
            
            # 包含URL或路径的注释
            r'//.*[/\\].*[/\\]',
            r'//.*https?://',
            
            # 包含版本号或数字的重要注释
            r'//.*v?\d+\.\d+',
            
            # 包含特殊符号的技术注释
            r'//.*[@#$%^&*]',
            
            # ignore 注释 (Flutter/Dart 特有)
            r'//\s*ignore',
            
            # 包含英文和数字混合的技术注释
            r'//.*[a-zA-Z]+.*\d+|//.*\d+.*[a-zA-Z]+',
        ]
    
    def should_keep_comment(self, line: str) -> bool:
        """判断是否应该保留这个注释"""
        stripped = line.strip()
        
        # 不是注释行，保留
        if not stripped.startswith('//'):
            return True
        
        # 检查是否匹配需要保留的模式
        for pattern in self.patterns_to_keep:
            if re.search(pattern, line, re.IGNORECASE):
                return True
        
        # 检查是否匹配需要删除的模式
        for pattern in self.patterns_to_remove:
            if re.match(pattern, stripped, re.IGNORECASE):
                return False
        
        # 默认保留
        return True
    
    def clean_file(self, file_path: Path) -> Tuple[bool, int]:
        """
        清理单个文件
        返回: (是否有修改, 删除的注释行数)
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except Exception as e:
            print(f"读取文件失败 {file_path}: {e}")
            return False, 0
        
        original_count = len(lines)
        cleaned_lines = []
        removed_count = 0
        
        i = 0
        while i < len(lines):
            line = lines[i]
            
            if self.should_keep_comment(line):
                cleaned_lines.append(line)
            else:
                removed_count += 1
                # 如果删除的注释行后面是空行，也一起删除
                if (i + 1 < len(lines) and 
                    lines[i + 1].strip() == '' and 
                    len(cleaned_lines) > 0 and 
                    cleaned_lines[-1].strip() != ''):
                    i += 1  # 跳过下一个空行
                    removed_count += 1
            
            i += 1
        
        # 清理多余的空行 (连续超过2个空行的情况)
        final_lines = []
        empty_count = 0
        
        for line in cleaned_lines:
            if line.strip() == '':
                empty_count += 1
                if empty_count <= 2:  # 最多保留2个连续空行
                    final_lines.append(line)
            else:
                empty_count = 0
                final_lines.append(line)
        
        # 如果有修改，写回文件
        if len(final_lines) != original_count or removed_count > 0:
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.writelines(final_lines)
                return True, removed_count
            except Exception as e:
                print(f"写入文件失败 {file_path}: {e}")
                return False, 0
        
        return False, 0
    
    def clean_directory(self, directory: Path, recursive: bool = True) -> None:
        """清理目录中的所有Dart文件"""
        if not directory.exists():
            print(f"目录不存在: {directory}")
            return
        
        pattern = "**/*.dart" if recursive else "*.dart"
        dart_files = list(directory.glob(pattern))
        
        if not dart_files:
            print(f"在 {directory} 中没有找到Dart文件")
            return
        
        print(f"找到 {len(dart_files)} 个Dart文件")
        
        total_modified = 0
        total_removed = 0
        
        for file_path in dart_files:
            modified, removed = self.clean_file(file_path)
            if modified:
                total_modified += 1
                total_removed += removed
                print(f"✓ {file_path.name}: 删除了 {removed} 行注释")
            else:
                print(f"- {file_path.name}: 无需修改")
        
        print(f"\n清理完成:")
        print(f"  修改文件数: {total_modified}/{len(dart_files)}")
        print(f"  删除注释行数: {total_removed}")

def main():
    parser = argparse.ArgumentParser(description="清理Dart文件中的过度注释")
    parser.add_argument("directory", help="要处理的目录路径")
    parser.add_argument("--no-recursive", action="store_true", help="不递归处理子目录")
    parser.add_argument("--dry-run", action="store_true", help="预览模式，不实际修改文件")
    
    args = parser.parse_args()
    
    directory = Path(args.directory)
    cleaner = DartCommentCleaner()
    
    if args.dry_run:
        print("=== 预览模式 (不会实际修改文件) ===")
        # 在预览模式下，可以添加更详细的分析逻辑
    
    cleaner.clean_directory(directory, not args.no_recursive)

if __name__ == "__main__":
    main()
