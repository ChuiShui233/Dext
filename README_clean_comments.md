# Dart注释清理工具使用说明

## 功能说明

这个Python脚本可以自动清理Dart文件中的过度注释，同时保留重要的技术注释和文档注释。

## 清理规则

### 会被删除的注释类型：
- 文件头注释 (如: `// file: xxx.dart`)
- 分隔线注释 (如: `// ########` 或 `// ----------`)
- 简单的中文描述注释 (如: `// 变量定义`)
- 简单的英文描述注释 (如: `// variable definition`)
- 空注释行 (如: `//`)

### 会被保留的注释类型：
- 文档注释 (`///` 开头)
- TODO、FIXME、NOTE等重要标记
- 包含代码的注释
- 包含URL或路径的注释
- 包含版本号的注释
- ignore注释 (Flutter/Dart特有)
- 包含特殊符号的技术注释

## 使用方法

### 基本用法
```bash
python clean_comments.py lib/pages
```

### 预览模式 (不实际修改文件)
```bash
python clean_comments.py lib/pages --dry-run
```

### 只处理当前目录 (不递归子目录)
```bash
python clean_comments.py lib/pages --no-recursive
```

### 处理整个lib目录
```bash
python clean_comments.py lib
```

## 安全特性

1. **备份建议**: 运行前建议先提交代码到Git或创建备份
2. **预览模式**: 使用 `--dry-run` 可以预览将要删除的内容
3. **保守策略**: 默认保留可能重要的注释，只删除明确的冗余注释
4. **编码安全**: 使用UTF-8编码处理中文注释

## 示例输出

```
找到 20 个Dart文件
✓ account_security_page.dart: 删除了 5 行注释
✓ survey_results_page.dart: 删除了 3 行注释
✓ edit_question_page.dart: 删除了 4 行注释
- home_page.dart: 无需修改
- login_page.dart: 无需修改

清理完成:
  修改文件数: 15/20
  删除注释行数: 45
```

## 注意事项

1. 脚本会自动处理连续空行，最多保留2个连续空行
2. 删除注释后如果产生多余空行会自动清理
3. 建议在版本控制环境下使用，方便回滚
4. 首次使用建议先在小范围目录测试
