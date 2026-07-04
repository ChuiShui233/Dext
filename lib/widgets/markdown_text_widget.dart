import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:forui/forui.dart';
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
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    
    final defaultStyle = baseStyle.copyWith(
      fontFamily: baseStyle.fontFamily ?? theme.textTheme.bodyMedium?.fontFamily,
      fontWeight: FontWeight.normal,
      color: baseStyle.color ?? theme.textTheme.bodyMedium?.color,
    );
    
    return RichText(
      text: _parseMarkdown(text, defaultStyle, theme, context),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  TextSpan _parseMarkdown(String text, TextStyle baseStyle, ThemeData theme, BuildContext context) {
    final List<TextSpan> spans = [];
    
    // 按行处理（不再特殊处理引用块）
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      // 处理普通行的 Markdown 语法
      _parseLineMarkdown(line, spans, baseStyle, theme, context);
      
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

  void _parseLineMarkdown(String line, List<TextSpan> spans, TextStyle baseStyle, ThemeData theme, BuildContext context) {
    // 检查是否是Markdown标题行
    final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final headingText = headingMatch.group(2)!;
      
      // 根据标题级别设置字号，支持更高的字号
      double fontSizeMultiplier;
      FontWeight fontWeight;
      switch (level) {
        case 1:
          fontSizeMultiplier = 2.0;  // H1: 2倍
          fontWeight = FontWeight.w900;
          break;
        case 2:
          fontSizeMultiplier = 1.75; // H2: 1.75倍
          fontWeight = FontWeight.w800;
          break;
        case 3:
          fontSizeMultiplier = 1.5;  // H3: 1.5倍
          fontWeight = FontWeight.w700;
          break;
        case 4:
          fontSizeMultiplier = 1.25; // H4: 1.25倍
          fontWeight = FontWeight.w600;
          break;
        case 5:
          fontSizeMultiplier = 1.1;  // H5: 1.1倍
          fontWeight = FontWeight.w600;
          break;
        default:
          fontSizeMultiplier = 1.0;  // H6: 1倍
          fontWeight = FontWeight.w500;
      }
      
      final headingStyle = baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 14) * fontSizeMultiplier,
        fontWeight: fontWeight,
        height: 1.3,
      );
      
      // 递归解析标题内容中的其他Markdown语法（粗体、斜体等）
      _parseInlineMarkdown(headingText, spans, headingStyle, theme, context);
      return;
    }
    
    // 非标题行，正常解析
    _parseInlineMarkdown(line, spans, baseStyle, theme, context);
  }
  
  void _parseInlineMarkdown(String text, List<TextSpan> spans, TextStyle baseStyle, ThemeData theme, BuildContext context) {
    final RegExp markdownRegex = RegExp(
      r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)]+)\))',
      multiLine: true,
    );

    int lastMatchEnd = 0;
    
    for (final match in markdownRegex.allMatches(text)) {
      // 添加匹配前的普通文本
      if (match.start > lastMatchEnd) {
        final plainText = text.substring(lastMatchEnd, match.start);
        if (plainText.isNotEmpty) {
          spans.add(TextSpan(text: plainText, style: baseStyle));
        }
      }

      // 处理不同的 Markdown 语法
      if (match.group(1) != null) {
        // 粗体 **text** -> 提升到更明显的字重
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w900),
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
            ..onTap = () => _launchUrl(context, linkUrl),
        ));
      }

      lastMatchEnd = match.end;
    }

    // 如果这一行没有找到任何 Markdown 语法，添加整行文本
    if (lastMatchEnd == 0 && text.isNotEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    } else if (lastMatchEnd < text.length) {
      // 添加剩余的普通文本
      final remainingText = text.substring(lastMatchEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }
  }

  void _launchUrl(BuildContext context, String url) async {
    // 弹窗确认是否跳转
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style.call,
        animation: animation,
        direction: Axis.horizontal,
        title: const Text('打开外部链接'),
        body: Text('即将跳转到第三方链接，是否继续？\n$url'),
        actions: [
          FButton(
            style: context.theme.buttonStyles.outline.call,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            style: context.theme.buttonStyles.primary.call,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
        // 半透明背景，贴合整体玻璃风格
        color: (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _buildToolButton(
            context,
            icon: Icons.format_bold,
            onTap: () => _insertMarkdown('**', '**', '粗体文本'),
          ),
          _buildToolButton(
            context,
            icon: Icons.format_italic,
            onTap: () => _insertMarkdown('*', '*', '斜体文本'),
          ),
          _buildToolButton(
            context,
            icon: Icons.link,
            onTap: () => _insertMarkdown('[', '](https://example.com)', '链接文本'),
          ),
          // 分隔线
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
          // 标题按钮
          _buildToolButton(
            context,
            label: 'H1',
            onTap: () => _insertHeading(1),
          ),
          _buildToolButton(
            context,
            label: 'H2',
            onTap: () => _insertHeading(2),
          ),
          _buildToolButton(
            context,
            label: 'H3',
            onTap: () => _insertHeading(3),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context, {
    IconData? icon,
    String? label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: icon != null 
          ? Icon(icon, size: 18)
          : Text(
              label ?? '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
      ),
    );
  }

  void _insertHeading(int level) {
    final text = controller.text;
    TextSelection selection = controller.selection;
    
    if (!selection.isValid || selection.start < 0) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    
    final cursorPos = selection.start.clamp(0, text.length);
    
    // 找到当前行的开始位置
    int lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    
    // 找到当前行的结束位置
    int lineEnd = cursorPos;
    while (lineEnd < text.length && text[lineEnd] != '\n') {
      lineEnd++;
    }
    
    // 获取当前行文本
    String lineText = text.substring(lineStart, lineEnd);
    
    // 检查是否已经有标题语法
    final existingHeading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(lineText);
    
    String newLineText;
    if (existingHeading != null) {
      // 已有标题，更新级别
      final content = existingHeading.group(2)!;
      newLineText = '${'#' * level} $content';
    } else {
      // 没有标题，添加标题语法
      final trimmed = lineText.trimLeft();
      if (trimmed.isEmpty) {
        newLineText = '${'#' * level} 标题文本';
      } else {
        newLineText = '${'#' * level} $trimmed';
      }
    }
    
    // 替换当前行
    final before = text.substring(0, lineStart);
    final after = text.substring(lineEnd);
    controller.text = before + newLineText + after;
    
    // 设置光标位置到行尾
    final newCursorPos = lineStart + newLineText.length;
    controller.selection = TextSelection.collapsed(offset: newCursorPos);
    
    onChanged?.call();
  }

  void _insertMarkdown(String prefix, String suffix, String placeholder) {
    final text = controller.text;
    TextSelection selection = controller.selection;

    // 规范化选择区，处理未聚焦或无效选择（-1）的情况
    if (!selection.isValid || selection.start < 0 || selection.end < 0) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);

    String selectedText = '';
    if (end > start) {
      selectedText = text.substring(start, end);
    }

    final insertText = selectedText.isEmpty ? placeholder : selectedText;
    final newText = prefix + insertText + suffix;

    _insertText(newText);
  }

  void _insertText(String text) {
    TextSelection selection = controller.selection;
    final current = controller.text;
    if (!selection.isValid || selection.start < 0 || selection.end < 0) {
      selection = TextSelection.collapsed(offset: current.length);
    }
    final start = selection.start.clamp(0, current.length);
    final end = selection.end.clamp(0, current.length);

    final newSelection = TextSelection.collapsed(
      offset: start + text.length,
    );

    _replaceSelection(text, newSelection, overrideStart: start, overrideEnd: end);
  }

  void _replaceSelection(String newText, TextSelection newSelection, {int? overrideStart, int? overrideEnd}) {
    final content = controller.text;
    TextSelection selection = controller.selection;
    if (overrideStart != null && overrideEnd != null) {
      selection = TextSelection(baseOffset: overrideStart, extentOffset: overrideEnd);
    } else if (!selection.isValid || selection.start < 0 || selection.end < 0) {
      selection = TextSelection.collapsed(offset: content.length);
    }

    final start = selection.start.clamp(0, content.length);
    final end = selection.end.clamp(0, content.length);

    final before = content.substring(0, start);
    final after = content.substring(end);

    controller.text = before + newText + after;
    controller.selection = newSelection;

    onChanged?.call();
  }
}
