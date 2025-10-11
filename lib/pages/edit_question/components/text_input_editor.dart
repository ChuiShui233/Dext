import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class TextInputEditor extends StatefulWidget {
  final String placeholder;
  final int maxLength;
  final bool multiline;
  final Function(String) onPlaceholderChanged;
  final Function(int) onMaxLengthChanged;
  final Function(bool) onMultilineChanged;

  const TextInputEditor({
    super.key,
    required this.placeholder,
    required this.maxLength,
    required this.multiline,
    required this.onPlaceholderChanged,
    required this.onMaxLengthChanged,
    required this.onMultilineChanged,
  });

  @override
  State<TextInputEditor> createState() => _TextInputEditorState();
}

class _TextInputEditorState extends State<TextInputEditor> {
  late TextEditingController _placeholderController;
  late TextEditingController _maxLengthController;

  @override
  void initState() {
    super.initState();
    _placeholderController = TextEditingController(text: widget.placeholder);
    _maxLengthController = TextEditingController(text: widget.maxLength.toString());
  }

  @override
  void dispose() {
    _placeholderController.dispose();
    _maxLengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 占位符设置
        FCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '输入框设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                
                // 占位符文本
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '占位符文本',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FTextField(
                      controller: _placeholderController,
                      hint: '请输入占位符文本...',
                      onChange: widget.onPlaceholderChanged,
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // 最大长度
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '最大字符数',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FTextField(
                      controller: _maxLengthController,
                      hint: '输入最大字符数',
                      keyboardType: TextInputType.number,
                      onChange: (value) {
                        final length = int.tryParse(value) ?? 500;
                        widget.onMaxLengthChanged(length);
                      },
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // 多行输入开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '多行输入',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    FSwitch(
                      value: widget.multiline,
                      onChange: widget.onMultilineChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 预览区域
        FCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '预览效果',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                
                // 预览输入框
                FTextField(
                  hint: widget.placeholder.isEmpty ? '请输入占位符文本...' : widget.placeholder,
                  maxLines: widget.multiline ? 5 : 1,
                  maxLength: widget.maxLength > 0 ? widget.maxLength : null,
                  enabled: false,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  '${widget.multiline ? '多行' : '单行'}输入框，最多 ${widget.maxLength} 个字符',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
