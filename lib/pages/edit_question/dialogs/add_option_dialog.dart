import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../../models/question.dart';
import '../../../services/api_service.dart';
import '../../../services/config.dart';
import '../../../components/video_player_widget.dart';

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
  final _placeholderController = TextEditingController();
  String? _mediaUrl;
  bool _isUploading = false;
  String? _uploadError;
  bool _isDragOver = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.option != null) {
      _textController.text = widget.option!.text == '__custom_input__' ? '__custom_input__' : widget.option!.text;
      _mediaUrl = widget.option!.mediaUrl;
      _placeholderController.text = widget.option!.customInputPlaceholder ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _placeholderController.dispose();
    super.dispose();
  }

  Future<void> _uploadFile(PlatformFile file) async {
    String url;
    
    // Web平台使用字节数据，移动端使用文件路径
    if (kIsWeb) {
      if (file.bytes != null && file.name.isNotEmpty) {
        url = await widget.apiService.uploadMediaUniversal(
          widget.surveyId,
          fileBytes: file.bytes!,
          fileName: file.name,
          onProgress: (sent, total) {
            if (mounted && total > 0) {
              setState(() {
                _uploadProgress = sent / total;
              });
            }
          },
        );
      } else {
        throw '无法获取文件数据';
      }
    } else {
      if (file.path != null) {
        url = await widget.apiService.uploadMediaUniversal(
          widget.surveyId,
          filePath: file.path!,
          onProgress: (sent, total) {
            if (mounted && total > 0) {
              setState(() {
                _uploadProgress = sent / total;
              });
            }
          },
        );
      } else {
        throw '无法获取文件路径';
      }
    }
    
    if (mounted) {
      setState(() {
        _mediaUrl = url;
        _uploadProgress = 1.0;
      });
    }
  }

  Future<void> _pickAndUploadMedia() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media);
      if (result != null && result.files.isNotEmpty) {
        await _uploadFile(result.files.single);
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


  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    if (files.isEmpty) return;
    
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final file = files.first;
      
      // 检查文件类型
      final fileName = file.name.toLowerCase();
      if (!fileName.endsWith('.jpg') && 
          !fileName.endsWith('.jpeg') && 
          !fileName.endsWith('.png') && 
          !fileName.endsWith('.gif') && 
          !fileName.endsWith('.webp') &&
          !fileName.endsWith('.mp4') && 
          !fileName.endsWith('.avi') && 
          !fileName.endsWith('.mov') &&
          !fileName.endsWith('.webm') &&
          !fileName.endsWith('.mp3') && 
          !fileName.endsWith('.wav') && 
          !fileName.endsWith('.aac')) {
        throw '不支持的文件类型';
      }

      // 尝试获取文件路径（桌面端）
      PlatformFile platformFile;
      try {
        final path = file.path;
        if (path != null && path.isNotEmpty) {
          // 桌面端：使用文件路径
          platformFile = PlatformFile(
            name: file.name,
            size: await file.length(),
            path: path,
          );
        } else {
          // Web端：使用字节数据
          final bytes = await file.readAsBytes();
          platformFile = PlatformFile(
            name: file.name,
            size: bytes.length,
            bytes: bytes,
          );
        }
      } catch (e) {
        // 如果获取路径失败，回退到字节数据
        final bytes = await file.readAsBytes();
        platformFile = PlatformFile(
          name: file.name,
          size: bytes.length,
          bytes: bytes,
        );
      }
      
      await _uploadFile(platformFile);
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
    final lowerUrl = absUrl.toLowerCase();
    
    if (lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg') || lowerUrl.endsWith('.png') || lowerUrl.endsWith('.gif') || lowerUrl.endsWith('.webp')) {
      return CachedNetworkImage(
        imageUrl: absUrl,
        fit: BoxFit.cover,
        progressIndicatorBuilder: (context, url, progress) => Center(child: CircularProgressIndicator(value: progress.progress)),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else if (lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.avi') || lowerUrl.endsWith('.mov') || lowerUrl.endsWith('.webm')) {
      return VideoPlayerWidget(
        videoUrl: absUrl,
        width: 150,
        height: 150,
        autoPlay: false,
        showControls: true,
      );
    } else if (lowerUrl.endsWith('.mp3') || lowerUrl.endsWith('.wav') || lowerUrl.endsWith('.aac')) {
      return const Center(
        child: Icon(Icons.audio_file, size: 50),
      );
    } else {
      return const Center(
        child: Icon(Icons.file_present, size: 50),
      );
    }
  }

  Widget _buildMediaSection() {
    if (_isUploading) {
      final percentage = (_uploadProgress * 100).toInt();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('上传中 $percentage%'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.grey.shade300,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          const SizedBox(height: 4),
          Text(
            percentage < 100 ? '请稍候...' : '上传完成',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
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
    }

    return DropTarget(
      onDragDone: (detail) {
        _handleDroppedFiles(detail.files);
        setState(() {
          _isDragOver = false;
        });
      },
      onDragEntered: (detail) {
        setState(() {
          _isDragOver = true;
        });
      },
      onDragExited: (detail) {
        setState(() {
          _isDragOver = false;
        });
      },
      child: GestureDetector(
        onTap: _pickAndUploadMedia,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isDragOver 
                ? Colors.blue.withAlpha(128)
                : Colors.grey.shade300,
              width: _isDragOver ? 2 : 1,
            ),
            color: _isDragOver 
              ? Colors.blue.withAlpha(20)
              : Colors.transparent,
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isDragOver ? Icons.cloud_upload : Icons.upload_file,
                size: 20,
                color: _isDragOver ? Colors.blue.shade600 : null,
              ),
              const SizedBox(width: 8),
              Text(
                _isDragOver ? '松开上传文件' : '上传媒体文件',
                style: TextStyle(
                  color: _isDragOver ? Colors.blue.shade600 : null,
                  fontWeight: _isDragOver ? FontWeight.w500 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                if (widget.option?.text == '__custom_input__') ...[
                  const Text(
                    '自定义填写选项',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '此选项将在答题时显示为可输入的文本框',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FTextFormField(
                    controller: _placeholderController,
                    label: const Text('输入框占位符（可选）'),
                    hint: '例如：请输入其他选项',
                  ),
                ] else ...[
                  FTextFormField(
                    controller: _textController,
                    label: const Text('选项文本'),
                    hint: '请输入选项文本',
                    validator: (value) => (value == null || value.isEmpty) ? '请输入选项文本' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildMediaSection(),
                ],
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
          style: context.theme.buttonStyles.outline.call,
          child: const Text('取消'),
          onPress: () => Navigator.pop(context),
        ),
        FButton(
          child: const Text('确定'),
          onPress: () {
            if (_formKey.currentState!.validate()) {
              final isCustomInput = widget.option?.text == '__custom_input__';
              Navigator.pop(
                context,
                QuestionOption(
                  id: widget.option?.id ?? DateTime.now().millisecondsSinceEpoch,
                  text: isCustomInput ? '__custom_input__' : _textController.text,
                  mediaUrl: isCustomInput ? null : _mediaUrl,
                  customInputPlaceholder: isCustomInput ? _placeholderController.text : null,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
