import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../components/video_player_widget.dart';
import '../services/config.dart';
import '../components/loading_indicator.dart';

class MediaGallery extends StatelessWidget {
  final List<String> mediaUrls;
  final double imageItemSize;
  final Size? videoItemSize; 
  final bool enableVideoPlayer;
  final bool showVideoOverlay; 
  final void Function(int index, String url, List<String> all, {VideoPlayerController? controller})? onOpen;
  /// 是否启用自适应高度模式（只限制高度，宽度自适应图片比例）
  final bool adaptiveHeight;
  final String? authToken;

  const MediaGallery({
    super.key,
    required this.mediaUrls,
    this.imageItemSize = 120,
    this.videoItemSize,
    this.enableVideoPlayer = true,
    this.showVideoOverlay = true,
    this.onOpen,
    this.adaptiveHeight = false,
    this.authToken,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: mediaUrls.asMap().entries.map((entry) {
        final index = entry.key;
        final url = entry.value;
        final absUrl = toAbsoluteUrl(url);
        final lower = absUrl.toLowerCase();
        final isImage = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.gif') || lower.endsWith('.webp');
        final isVideo = lower.endsWith('.mp4') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.webm');
        final isAudio = lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.aac');

        Widget mediaWidget;
        double w = imageItemSize;
        double h = imageItemSize;

        if (isImage) {
          mediaWidget = CachedNetworkImage(
            imageUrl: absUrl,
            httpHeaders: authToken != null && authToken!.isNotEmpty
                ? { 'Authorization': 'Bearer ${authToken!}' }
                : null,
            fit: adaptiveHeight ? BoxFit.contain : BoxFit.cover,
            progressIndicatorBuilder: (context, url, progress) {
              final pct = progress.progress != null
                  ? '加载中 ${(progress.progress! * 100).toInt()}%'
                  : '加载中...';
              return SizedBox(
                width: adaptiveHeight ? w : null,
                height: adaptiveHeight ? h : null,
                child: Center(child: LoadingIndicator.inline(message: pct)),
              );
            },
            errorWidget: (context, _, __) => Container(color: Colors.grey.shade200, child: const Icon(Icons.error)),
          );
        } else if (isVideo) {
          if (enableVideoPlayer) {
            final Size vs = videoItemSize ?? const Size(240, 180);
            w = vs.width;
            h = vs.height;
            mediaWidget = VideoPlayerWidget(
              videoUrl: absUrl,
              width: vs.width,
              height: vs.height,
              autoPlay: false,
              showControls: true,
              httpHeaders: authToken != null && authToken!.isNotEmpty
                  ? { 'Authorization': 'Bearer ${authToken!}' }
                  : null,
              onOpen: onOpen == null ? null : (controller) => onOpen!(index, absUrl, mediaUrls.map(toAbsoluteUrl).toList(), controller: controller),
              showFullscreenButton: onOpen != null,
            );
          } else {
            mediaWidget = const Center(child: Icon(Icons.video_file, size: 40));
          }
        } else if (isAudio) {
          mediaWidget = const Center(child: Icon(Icons.audio_file, size: 40));
        } else {
          mediaWidget = const Center(child: Icon(Icons.file_present, size: 40));
        }

        Widget thumb = AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.centerLeft,
          child: Container(
            width: adaptiveHeight ? null : w,
            height: adaptiveHeight ? null : h,
            constraints: adaptiveHeight 
                ? BoxConstraints(maxHeight: h, maxWidth: w * 2) 
                : null,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: adaptiveHeight ? StackFit.passthrough : StackFit.loose,
                children: [
                  adaptiveHeight ? mediaWidget : Positioned.fill(child: Center(child: mediaWidget)),
                if (isVideo && showVideoOverlay && !enableVideoPlayer)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 48),
                    ),
                  ),
                if (isImage)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
        );

        // 仅在非视频或未启用内置播放器时，用外层点击打开全屏；
        // 视频启用播放器时由内部按钮处理，避免手势冲突。
        if (onOpen != null && (!isVideo || (isVideo && !enableVideoPlayer))) {
          thumb = GestureDetector(
            onTap: () => onOpen!(index, absUrl, mediaUrls.map(toAbsoluteUrl).toList()),
            child: thumb,
          );
        }
        return thumb;
      }).toList(),
    );
  }
}
