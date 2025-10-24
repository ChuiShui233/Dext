import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:forui/forui.dart';
import 'loading_indicator.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final bool autoPlay;
  final bool showControls;
  // When provided, a fullscreen button can be shown which will call this.
  final VoidCallback? onOpen;
  // Whether to show the built-in fullscreen button (top-right)
  final bool showFullscreenButton;
  // Optional HTTP headers for authenticated requests
  final Map<String, String>? httpHeaders;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.width,
    this.height,
    this.autoPlay = false,
    this.showControls = true,
    this.onOpen,
    this.showFullscreenButton = false,
    this.httpHeaders,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  // 进度条拖动动画状态
  bool _isScrubbing = false;
  // 拖动中的临时进度（0..1），仅在_scrubbing时生效
  double? _scrubFraction;
  // 进度条测量用 key
  final GlobalKey _barKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: widget.httpHeaders ?? const <String, String>{},
      );
      await _controller.initialize();
      
      if (mounted) {
        _controller.addListener(_videoListener);
        setState(() {
          _isInitialized = true;
        });
        
        if (widget.autoPlay) {
          _controller.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = '视频加载失败: $e';
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted) return;
    
    // 检查视频是否接近结尾，提前100毫秒暂停避免画面抽搐
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    
    if (duration > Duration.zero && position > Duration.zero) {
      final remaining = duration - position;
      // 当剩余时间少于100毫秒时暂停
      if (remaining <= const Duration(milliseconds: 100) && _controller.value.isPlaying) {
        _controller.pause();
        // 将播放位置设置到结尾
        _controller.seekTo(duration);
      }
    }
    
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: widget.width ?? 200,
        height: widget.height ?? 150,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: widget.width ?? 200,
        height: widget.height ?? 150,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: LoadingIndicator.inline(message: '视频加载中...'),
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: widget.showControls
            ? Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  if (_controller.value.isBuffering)
                    const Positioned(
                      child: Center(
                        child: LoadingIndicator.inline(message: '缓冲中...'),
                      ),
                    ),
                  // Built-in fullscreen button (top-right). It pauses before opening
                  if (widget.showFullscreenButton && widget.onOpen != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            // Pause first, then open
                            if (_controller.value.isPlaying) {
                              _controller.pause();
                            }
                            widget.onOpen?.call();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(60),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(FIcons.maximize, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),
                  _buildControls(),
                ],
              )
            : AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 16, // 固定底部边距
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // 暂停/播放按钮
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
              child: Icon(
                _controller.value.isPlaying ? FIcons.pause : FIcons.play,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // 进度条（自定义，拖动时变粗并带动画）
            Expanded(child: _buildAnimatedProgressBar()),
            const SizedBox(width: 12),
            // 时间显示
            Text(
              '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 自定义可拖动进度条：拖动时高度从4动画到8
  Widget _buildAnimatedProgressBar() {
    final value = _controller.value;
    final duration = value.duration;
    final position = value.position;
    final totalMs = duration.inMilliseconds;

    double playedFraction = 0.0;
    if (totalMs > 0) {
      playedFraction = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    }
    // 拖动中优先用临时进度
    final effectivePlayed = (_isScrubbing && _scrubFraction != null)
        ? _scrubFraction!.clamp(0.0, 1.0)
        : playedFraction;

    // 计算缓存进度（取最后一个bufferedRange的end）
    double bufferedFraction = 0.0;
    if (value.buffered.isNotEmpty && totalMs > 0) {
      final last = value.buffered.last;
      bufferedFraction = (last.end.inMilliseconds / totalMs).clamp(0.0, 1.0);
    }

    const Color playedColor = Color(0xFFFB7299);
    const Color bufferedColor = Colors.grey;
    const Color backgroundColor = Colors.white30;

    final double baseHeight = 4.0;
    final double thickHeight = 8.0;
    final double barHeight = _isScrubbing ? thickHeight : baseHeight;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => _seekByLocalDx(details.localPosition.dx),
      onHorizontalDragStart: (details) {
        setState(() {
          _isScrubbing = true;
        });
      },
      onHorizontalDragUpdate: (details) {
        _updateScrubFraction(details.localPosition.dx);
      },
      onHorizontalDragEnd: (details) {
        _commitScrub();
      },
      onHorizontalDragCancel: () {
        setState(() {
          _isScrubbing = false;
          _scrubFraction = null;
        });
      },
      child: SizedBox(
        height: 24, // 提高可触达区域
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final playedWidth = width * effectivePlayed;
            final bufferedWidth = width * bufferedFraction;

            return Center(
              child: AnimatedContainer(
                key: _barKey,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                height: barHeight,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 缓冲条
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: bufferedWidth,
                        color: bufferedColor,
                      ),
                    ),
                    // 已播放
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: playedWidth,
                        color: playedColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _updateScrubFraction(double localDx) {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;
    final f = (localDx / width).clamp(0.0, 1.0);
    setState(() {
      _scrubFraction = f;
    });
  }

  void _commitScrub() {
    final duration = _controller.value.duration;
    if (duration <= Duration.zero) {
      setState(() {
        _isScrubbing = false;
        _scrubFraction = null;
      });
      return;
    }
    final fraction = (_scrubFraction ?? 0.0).clamp(0.0, 1.0);
    final target = Duration(milliseconds: (duration.inMilliseconds * fraction).round());
    _controller.seekTo(target).whenComplete(() {
      if (mounted) {
        setState(() {
          _isScrubbing = false;
          _scrubFraction = null;
        });
      }
    });
  }

  void _seekByLocalDx(double localDx) {
    // 点击定位进度
    final duration = _controller.value.duration;
    if (duration <= Duration.zero) return;
    // 通过进度条自身context计算宽度
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;
    final f = (localDx / width).clamp(0.0, 1.0);
    final target = Duration(milliseconds: (duration.inMilliseconds * f).round());
    _controller.seekTo(target);
  }


  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
