import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

/// Markdown 文本渲染组件
class MarkdownTextWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const MarkdownTextWidget({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    
    return RichText(
      text: _parseMarkdown(text, defaultStyle, theme),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  TextSpan _parseMarkdown(String text, TextStyle baseStyle, ThemeData theme) {
    final List<TextSpan> spans = [];
    
    // 按行处理，支持引用块
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // 处理引用块
      if (line.startsWith('> ')) {
        final quotedText = line.substring(2);
        spans.add(TextSpan(
          text: quotedText,
          style: baseStyle.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
        ));
      } else {
        // 处理普通行的 Markdown 语法
        _parseLineMarkdown(line, spans, baseStyle, theme);
      }
      
      // 添加换行符（除了最后一行）
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    // 如果没有找到任何内容，返回原始文本
    if (spans.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    return TextSpan(children: spans);
  }

  void _parseLineMarkdown(String line, List<TextSpan> spans, TextStyle baseStyle, ThemeData theme) {
    final RegExp markdownRegex = RegExp(
      r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)]+)\))',
      multiLine: true,
    );

    int lastMatchEnd = 0;
    
    for (final match in markdownRegex.allMatches(line)) {
      // 添加匹配前的普通文本
      if (match.start > lastMatchEnd) {
        final plainText = line.substring(lastMatchEnd, match.start);
        if (plainText.isNotEmpty) {
          spans.add(TextSpan(text: plainText, style: baseStyle));
        }
      }

      // 处理不同的 Markdown 语法
      if (match.group(1) != null) {
        // 粗体 **text**
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null) {
        // 斜体 *text*
        spans.add(TextSpan(
          text: match.group(4),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(5) != null) {
        // 代码 `code`
        spans.add(TextSpan(
          text: ' ${match.group(6)} ',
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: (baseStyle.fontSize ?? 14) * 0.9,
          ),
        ));
      } else if (match.group(7) != null) {
        // 链接 [text](url)
        final linkText = match.group(8) ?? '';
        final linkUrl = match.group(9) ?? '';
        spans.add(TextSpan(
          text: linkText,
          style: baseStyle.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchUrl(linkUrl),
        ));
      }

      lastMatchEnd = match.end;
    }

    // 如果这一行没有找到任何 Markdown 语法，添加整行文本
    if (lastMatchEnd == 0 && line.isNotEmpty) {
      spans.add(TextSpan(text: line, style: baseStyle));
    } else if (lastMatchEnd < line.length) {
      // 添加剩余的普通文本
      final remainingText = line.substring(lastMatchEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }
  }

  void _launchUrl(String url) async {
    try {
      // 如果 URL 不包含协议，添加 https://
      String finalUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        finalUrl = 'https://$url';
      }
      
      final uri = Uri.parse(finalUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('无法打开链接: $url, 错误: $e');
    }
  }
}

/// Markdown 编辑器工具栏
class MarkdownToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onChanged;

  const MarkdownToolbar({
    super.key,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
        ),
      ),
      child: Wrap(
        spacing: 4,
        children: [
          _buildToolButton(
            context,
            icon: Icons.format_bold,
            tooltip: '粗体',
            onTap: () => _insertMarkdown('**', '**', '粗体文本'),
          ),
          _buildToolButton(
            context,
            icon: Icons.format_italic,
            tooltip: '斜体',
            onTap: () => _insertMarkdown('*', '*', '斜体文本'),
          ),
          _buildToolButton(
            context,
            icon: Icons.link,
            tooltip: '链接',
            onTap: () => _insertMarkdown('[', '](https://example.com)', '链接文本'),
          ),
          _buildToolButton(
            context,
            icon: Icons.format_quote,
            tooltip: '引用',
            onTap: () => _insertLinePrefix('> '),
          ),
          const SizedBox(width: 8),
          _buildPresetButton(context, '重要', '**重要**'),
          _buildPresetButton(context, '注意', '*注意*'),
          _buildPresetButton(context, '引用', '> 这是一段引用文本'),
          _buildPresetButton(context, '链接', '[链接](https://example.com)'),
        ],
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }

  Widget _buildPresetButton(BuildContext context, String label, String markdown) {
    return InkWell(
      onTap: () => _insertText(markdown),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  void _insertMarkdown(String prefix, String suffix, String placeholder) {
    final text = controller.text;
    final selection = controller.selection;
    
    String selectedText = '';
    if (selection.isValid && !selection.isCollapsed) {
      selectedText = text.substring(selection.start, selection.end);
    }
    
    final insertText = selectedText.isEmpty ? placeholder : selectedText;
    final newText = prefix + insertText + suffix;
    
    final newSelection = TextSelection.collapsed(
      offset: selection.start + prefix.length + insertText.length,
    );
    
    _replaceSelection(newText, newSelection);
  }

  void _insertText(String text) {
    final selection = controller.selection;
    final newSelection = TextSelection.collapsed(
      offset: selection.start + text.length,
    );
    
    _replaceSelection(text, newSelection);
  }

  void _insertLinePrefix(String prefix) {
    final text = controller.text;
    final selection = controller.selection;
    
    // 找到当前行的开始位置
    int lineStart = selection.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    
    // 检查当前行是否已经有这个前缀
    final currentLine = text.substring(lineStart, 
        text.indexOf('\n', lineStart) != -1 ? text.indexOf('\n', lineStart) : text.length);
    
    if (currentLine.startsWith(prefix)) {
      // 如果已经有前缀，移除它
      final newText = text.substring(0, lineStart) + 
          currentLine.substring(prefix.length) + 
          text.substring(lineStart + currentLine.length);
      final newSelection = TextSelection.collapsed(
        offset: selection.start - prefix.length,
      );
      controller.text = newText;
      controller.selection = newSelection;
    } else {
      // 如果没有前缀，添加它
      final newText = text.substring(0, lineStart) + 
          prefix + 
          text.substring(lineStart);
      final newSelection = TextSelection.collapsed(
        offset: selection.start + prefix.length,
      );
      controller.text = newText;
      controller.selection = newSelection;
    }
    
    onChanged?.call();
  }

  void _replaceSelection(String newText, TextSelection newSelection) {
    final text = controller.text;
    final selection = controller.selection;
    
    final beforeSelection = text.substring(0, selection.start);
    final afterSelection = text.substring(selection.end);
    
    controller.text = beforeSelection + newText + afterSelection;
    controller.selection = newSelection;
    
    onChanged?.call();
  }
}
