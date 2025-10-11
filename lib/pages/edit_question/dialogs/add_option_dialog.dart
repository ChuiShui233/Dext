import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/question.dart';
import '../../../services/api_service.dart';
import '../../../services/config.dart';

class AddOptionDialog extends StatefulWidget {
  final QuestionOption? option;
  final ApiService apiService;
  final int surveyId;

  const AddOptionDialog({
    super.key,
    this.option,
    required this.apiService,
    required this.surveyId,
  });

  @override
  State<AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<AddOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  String? _mediaUrl;
  bool _isUploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    if (widget.option != null) {
      _textController.text = widget.option!.text;
      _mediaUrl = widget.option!.mediaUrl;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        String url;
        
        // Web平台使用字节数据，移动端使用文件路径
        if (kIsWeb) {
          if (file.bytes != null && file.name.isNotEmpty) {
            url = await widget.apiService.uploadMediaUniversal(
              widget.surveyId,
              fileBytes: file.bytes!,
              fileName: file.name,
            );
          } else {
            throw '无法获取文件数据';
          }
        } else {
          if (file.path != null) {
            url = await widget.apiService.uploadMediaUniversal(
              widget.surveyId,
              filePath: file.path!,
            );
          } else {
            throw '无法获取文件路径';
          }
        }
        
        if (mounted) {
          setState(() {
            _mediaUrl = url;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadError = '上传失败: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _removeMedia() {
    setState(() {
      _mediaUrl = null;
    });
  }

  Widget _buildMediaPreview(String url) {
    final absUrl = toAbsoluteUrl(url);
    if (absUrl.toLowerCase().endsWith('.jpg') || absUrl.toLowerCase().endsWith('.jpeg') || absUrl.toLowerCase().endsWith('.png')) {
      return CachedNetworkImage(
        imageUrl: absUrl,
        fit: BoxFit.cover,
        progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else if (url.toLowerCase().endsWith('.mp4')) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.video_file, size: 50),
      );
    } else if (url.toLowerCase().endsWith('.mp3')) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.audio_file, size: 50),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.file_present, size: 50),
      );
    }
  }

  Widget _buildMediaSection() {
    if (_isUploading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mediaUrl != null && _mediaUrl!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选项媒体文件'),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildMediaPreview(_mediaUrl!),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: GestureDetector(
                    onTap: _removeMedia,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return FButton(
        style: FButtonStyle.outline,
        onPress: _pickAndUploadMedia,
        child: const Text('上传媒体文件 (可选)'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      direction: Axis.horizontal,
      title: Text(widget.option == null ? '添加选项' : '编辑选项'),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FTextFormField(
                  controller: _textController,
                  label: const Text('选项文本'),
                  hint: '请输入选项文本',
                  validator: (value) => (value == null || value.isEmpty) ? '请输入选项文本' : null,
                ),
                const SizedBox(height: 16),
                _buildMediaSection(),
                if (_uploadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _uploadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          intrinsicWidth: true,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          intrinsicWidth: true,
          child: const Text('确定'),
          onPress: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                QuestionOption(
                  id: widget.option?.id ?? DateTime.now().millisecondsSinceEpoch,
                  text: _textController.text,
                  mediaUrl: _mediaUrl,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
