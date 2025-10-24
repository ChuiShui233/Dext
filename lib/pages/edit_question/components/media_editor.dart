import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/config.dart';
import '../../../components/video_player_widget.dart';

class MediaEditor extends StatefulWidget {
  final List<String> mediaUrls;
  final Map<String, double> uploadProgress;
  final Map<String, bool> uploadingFiles;
  final Map<String, String> uploadStatus;
  final Function() onUploadMedia;
  final Function(String) onDeleteMedia;
  final Function(String) onCancelUpload;
  final Function(List<PlatformFile>) onDropFiles;
  final double imageScale;
  final Function(double) onImageScaleChanged;

  const MediaEditor({
    super.key,
    required this.mediaUrls,
    required this.uploadProgress,
    required this.uploadingFiles,
    required this.uploadStatus,
    required this.onUploadMedia,
    required this.onDeleteMedia,
    required this.onCancelUpload,
    required this.onDropFiles,
    required this.imageScale,
    required this.onImageScaleChanged,
  });

  @override
  State<MediaEditor> createState() => _MediaEditorState();
}

class _MediaEditorState extends State<MediaEditor> {
  bool _isDragOver = false;

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    if (files.isEmpty) return;
    
    final platformFiles = <PlatformFile>[];
    
    for (final file in files) {
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
        continue; // 跳过不支持的文件
      }

      try {
        final bytes = await file.readAsBytes();
        final platformFile = PlatformFile(
          name: file.name,
          size: bytes.length,
          bytes: bytes,
        );
        platformFiles.add(platformFile);
      } catch (e) {
        // 忽略读取失败的文件
        continue;
      }
    }
    
    if (platformFiles.isNotEmpty) {
      widget.onDropFiles(platformFiles);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isDragOver 
              ? Colors.blue.withAlpha(128)
              : Colors.transparent,
            width: _isDragOver ? 2 : 0,
          ),
          color: _isDragOver 
            ? Colors.blue.withAlpha(20)
            : Colors.transparent,
        ),
        padding: EdgeInsets.all(_isDragOver ? 8 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('问题媒体文件（视频/图片/音频）'),
                if (_isDragOver) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.cloud_upload,
                    size: 16,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '拖放文件到此处',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
            ...widget.mediaUrls.map((url) {
              Widget mediaWidget;
              final absUrl = toAbsoluteUrl(url);
              final isImage = absUrl.toLowerCase().endsWith('.jpg') || 
                             absUrl.toLowerCase().endsWith('.jpeg') || 
                             absUrl.toLowerCase().endsWith('.png') ||
                             absUrl.toLowerCase().endsWith('.gif');
              final isVideo = absUrl.toLowerCase().endsWith('.mp4') || 
                             absUrl.toLowerCase().endsWith('.avi') || 
                             absUrl.toLowerCase().endsWith('.mov') ||
                             absUrl.toLowerCase().endsWith('.webm');
              final isAudio = absUrl.toLowerCase().endsWith('.mp3') || 
                             absUrl.toLowerCase().endsWith('.wav') || 
                             absUrl.toLowerCase().endsWith('.aac');

              if (isImage) {
                mediaWidget = CachedNetworkImage(
                  imageUrl: absUrl,
                  fit: BoxFit.cover,
                  progressIndicatorBuilder: (context, url, progress) => 
                      Center(child: CircularProgressIndicator(value: progress.progress)),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                );
              } else if (isVideo) {
                mediaWidget = VideoPlayerWidget(
                  videoUrl: absUrl,
                  width: 200,
                  height: 150,
                  autoPlay: false,
                  showControls: true,
                );
              } else if (isAudio) {
                mediaWidget = const Center(child: Icon(Icons.audio_file, size: 40));
              } else {
                mediaWidget = const Center(child: Icon(Icons.file_present, size: 40));
              }

              return Stack(
                children: [
                  Container(
                    width: isVideo ? 200 : 100,
                    height: isVideo ? 150 : 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7), 
                      child: mediaWidget,
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
                        onTap: () => widget.onDeleteMedia(url),
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
              );
            }),
            ...widget.uploadingFiles.keys.map((fileName) {
              final progress = widget.uploadProgress[fileName] ?? 0.0;
              final statusText = widget.uploadStatus[fileName];
              final isImage = fileName.toLowerCase().endsWith('.jpg') || 
                             fileName.toLowerCase().endsWith('.jpeg') || 
                             fileName.toLowerCase().endsWith('.png') ||
                             fileName.toLowerCase().endsWith('.gif');
              final isVideo = fileName.toLowerCase().endsWith('.mp4') || 
                             fileName.toLowerCase().endsWith('.avi') || 
                             fileName.toLowerCase().endsWith('.mov') ||
                             fileName.toLowerCase().endsWith('.webm');
              
              return Container(
                width: isVideo ? 200 : 100,
                height: isVideo ? 150 : 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade100,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isImage ? Icons.image : 
                            isVideo ? Icons.video_file : 
                            Icons.audio_file,
                            size: 30,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileName.length > 15 
                                ? '${fileName.substring(0, 12)}...'
                                : fileName,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusText != null && statusText.isNotEmpty
                                ? statusText
                                : '${(progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
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
                          onTap: () => widget.onCancelUpload(fileName),
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
              );
            }),
          ],
            ),
            const SizedBox(height: 8),
            FButton(
              style: FButtonStyle.outline,
              onPress: widget.onUploadMedia,
              child: const Text('上传媒体文件'),
            ),
            if (widget.mediaUrls.any((url) => _isImageUrl(url))) ...[
              const SizedBox(height: 16),
              const Text('图片显示大小'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('50%'),
                  Expanded(
                    child: Slider(
                      value: widget.imageScale,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      label: '${(widget.imageScale * 100).round()}%',
                      onChanged: widget.onImageScaleChanged,
                    ),
                  ),
                  const Text('200%'),
                ],
              ),
              Text(
                '当前大小: ${(widget.imageScale * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isImageUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.jpg') || 
           lowerUrl.endsWith('.jpeg') || 
           lowerUrl.endsWith('.png') ||
           lowerUrl.endsWith('.gif') ||
           lowerUrl.endsWith('.webp');
  }
}
