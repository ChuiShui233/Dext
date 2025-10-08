import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:forui/forui.dart';
import '../services/config.dart';

class FullscreenMediaViewer extends StatefulWidget {
  final String mediaUrl;
  final String? title;
  final List<String>? allMediaUrls;
  final int? currentIndex;
  final String? authToken;

  const FullscreenMediaViewer({
    super.key,
    required this.mediaUrl,
    this.title,
    this.allMediaUrls,
    this.currentIndex,
    this.authToken,
  });


  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer>
    with TickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  late AnimationController _entryAnimationController;
  late AnimationController _dismissAnimationController;
  late Animation<Matrix4> _animation;
  late Animation<double> _entryScaleAnimation;
  late Animation<double> _entryFadeAnimation;
  late Animation<Offset> _dismissSlideAnimation;
  late Animation<double> _dismissScaleAnimation;
  
  int _currentIndex = 0;
  bool _showControls = true;
  bool _isZoomed = false;
  bool _isDismissing = false;
  
  double _dragDistance = 0.0;
  bool _isDragging = false;
  
  final GlobalKey<_FullscreenVideoPlayerState> _videoPlayerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _entryAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _dismissAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _entryScaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _entryAnimationController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutBack),
    ));
    
    _entryFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _entryAnimationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));
    
    _dismissSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -1.0),
    ).animate(CurvedAnimation(
      parent: _dismissAnimationController,
      curve: Curves.easeInCubic,
    ));
    
    _dismissScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _dismissAnimationController,
      curve: Curves.easeInCubic,
    ));
    
    _currentIndex = widget.currentIndex ?? 0;
    
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    
    _entryAnimationController.forward();
    
    // 3秒后自动隐藏控制栏
    _hideControlsAfterDelay();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    _entryAnimationController.dispose();
    _dismissAnimationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _hideControlsAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
        
        if (_videoPlayerKey.currentState != null) {
          _videoPlayerKey.currentState!.updateControlsVisibility(false);
        }
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    
    if (_videoPlayerKey.currentState != null) {
      _videoPlayerKey.currentState!.updateControlsVisibility(_showControls);
    }
    
    if (_showControls) {
      _hideControlsAfterDelay();
    }
  }

  String get _currentMediaUrl {
    if (widget.allMediaUrls != null && widget.allMediaUrls!.isNotEmpty) {
      return toAbsoluteUrl(widget.allMediaUrls![_currentIndex]);
    }
    return toAbsoluteUrl(widget.mediaUrl);
  }

  bool _isImage(String url) {
    return url.toLowerCase().endsWith('.jpg') ||
        url.toLowerCase().endsWith('.jpeg') ||
        url.toLowerCase().endsWith('.png') ||
        url.toLowerCase().endsWith('.gif') ||
        url.toLowerCase().endsWith('.webp');
  }

  bool _isVideo(String url) {
    return url.toLowerCase().endsWith('.mp4') ||
        url.toLowerCase().endsWith('.avi') ||
        url.toLowerCase().endsWith('.mov') ||
        url.toLowerCase().endsWith('.webm');
  }

  void _resetZoom() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward(from: 0).then((_) {
      setState(() {
        _isZoomed = false;
      });
    });
    
    _animation.addListener(() {
      _transformationController.value = _animation.value;
    });
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    setState(() {
      _isZoomed = scale > 1.0;
    });
  }

  void _previousMedia() {
    if (widget.allMediaUrls != null && widget.allMediaUrls!.isNotEmpty) {
      setState(() {
        _currentIndex = (_currentIndex - 1 + widget.allMediaUrls!.length) % widget.allMediaUrls!.length;
        _resetZoom();
      });
    }
  }

  void _nextMedia() {
    if (widget.allMediaUrls != null && widget.allMediaUrls!.isNotEmpty) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.allMediaUrls!.length;
        _resetZoom();
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isZoomed) return; // 如果正在缩放，不处理滑动
    _isDragging = true;
    _dragDistance = 0.0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed || !_isDragging) return;
    
    setState(() {
      _dragDistance += details.delta.dy;
      if (_dragDistance > 0) {
        _dragDistance = 0;
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed || !_isDragging) return;
    
    _isDragging = false;
    
    const double dismissThreshold = -200.0;
    const double velocityThreshold = -300.0;
    
    if (_dragDistance < dismissThreshold || details.velocity.pixelsPerSecond.dy < velocityThreshold) {
      _dismissViewer();
    } else {
      _animateBackToPosition();
    }
  }

  void _animateBackToPosition() {
    final startDistance = _dragDistance;
    final animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    final animation = Tween<double>(
      begin: startDistance,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
    ));
    
    animation.addListener(() {
      setState(() {
        _dragDistance = animation.value;
      });
    });
    
    animationController.forward().then((_) {
      animationController.dispose();
    });
  }

  void _dismissViewer() {
    if (_isDismissing) return;
    
    setState(() {
      _isDismissing = true;
    });
    
    final currentOffset = _dragDistance / MediaQuery.of(context).size.height;
    final currentScale = _entryScaleAnimation.value * (1.0 + (_dragDistance.abs() * 0.0005));
    
    _dismissSlideAnimation = Tween<Offset>(
      begin: Offset(0.0, currentOffset),
      end: const Offset(0.0, -1.0),
    ).animate(CurvedAnimation(
      parent: _dismissAnimationController,
      curve: Curves.easeInCubic,
    ));
    
    _dismissScaleAnimation = Tween<double>(
      begin: currentScale,
      end: 0.7,
    ).animate(CurvedAnimation(
      parent: _dismissAnimationController,
      curve: Curves.easeInCubic,
    ));
    
    _dismissAnimationController.forward().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = _currentMediaUrl;
    final isImage = _isImage(currentUrl);
    final isVideo = _isVideo(currentUrl);
    final hasMultipleMedia = widget.allMediaUrls != null && widget.allMediaUrls!.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: AnimatedBuilder(
                animation: Listenable.merge([_entryAnimationController, _dismissAnimationController]),
                builder: (context, child) {
                  double currentScale = _entryScaleAnimation.value;
                  Offset currentOffset = Offset.zero;
                  
                  if (_isDismissing) {
                    currentScale = _dismissScaleAnimation.value;
                    currentOffset = _dismissSlideAnimation.value;
                  } else if (_dragDistance != 0.0) {
                    final dampedDistance = _dragDistance * 0.7;
                    currentOffset = Offset(0.0, dampedDistance / MediaQuery.of(context).size.height);
                    currentScale = _entryScaleAnimation.value * (1.0 + (_dragDistance.abs() * 0.0005));
                  }
                  
                  return Transform.translate(
                    offset: Offset(
                      currentOffset.dx * MediaQuery.of(context).size.width,
                      currentOffset.dy * MediaQuery.of(context).size.height,
                    ),
                    child: FadeTransition(
                      opacity: _isDismissing 
                          ? _dismissAnimationController 
                          : _entryFadeAnimation,
                      child: ScaleTransition(
                        scale: AlwaysStoppedAnimation(currentScale),
                        child: isImage
                            ? GestureDetector(
                                onTap: _toggleControls,
                                child: InteractiveViewer(
                                  transformationController: _transformationController,
                                  onInteractionUpdate: _onInteractionUpdate,
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  child: Center(
                                    child: CachedNetworkImage(
                                      imageUrl: currentUrl,
                                      httpHeaders: (widget.authToken != null && widget.authToken!.isNotEmpty)
                                          ? { 'Authorization': 'Bearer ${widget.authToken!}' }
                                          : null,
                                      fit: BoxFit.contain,
                                      placeholder: (context, url) => const Center(
                                        child: CircularProgressIndicator(color: Colors.white),
                                      ),
                                      errorWidget: (context, url, error) => const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.error, color: Colors.white, size: 64),
                                            SizedBox(height: 16),
                                            Text(
                                              '图片加载失败',
                                              style: TextStyle(color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : isVideo
                                ? _FullscreenVideoPlayer(
                                    key: _videoPlayerKey,
                                    videoUrl: currentUrl,
                                    autoPlay: true,
                                    showControls: true,
                                    parentControlsVisible: false,
                                    onToggleControls: null,
                                    httpHeaders: (widget.authToken != null && widget.authToken!.isNotEmpty)
                                        ? { 'Authorization': 'Bearer ${widget.authToken!}' }
                                        : null,
                                  )
                                : GestureDetector(
                                    onTap: _toggleControls,
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(FIcons.file, color: Colors.white, size: 64),
                                          SizedBox(height: 16),
                                          Text(
                                            '不支持的媒体格式',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (!isVideo)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(FIcons.x, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (widget.title != null)
                                Text(
                                  widget.title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (hasMultipleMedia)
                                Text(
                                  '${_currentIndex + 1} / ${widget.allMediaUrls!.length}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isImage && _isZoomed)
                          GestureDetector(
                            onTap: _resetZoom,
                            child: const Icon(FIcons.zoomOut, color: Colors.white, size: 24),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (hasMultipleMedia && _showControls && !isVideo) ...[
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: GestureDetector(
                    onTap: _previousMedia,
                    child: const Icon(FIcons.chevronLeft, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: GestureDetector(
                    onTap: _nextMedia,
                    child: const Icon(FIcons.chevronRight, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
          ],

          if (!isVideo)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              bottom: _showControls ? 0 : -80,
              left: 0,
              right: 0,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isImage ? '图片' : isVideo ? '视频' : '文件',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isImage)
                                const Text(
                                  '双指缩放 • 拖拽移动',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              if (isVideo)
                                const Text(
                                  '双击播放/暂停 • 点击视频显示/隐藏控制',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 专门用于全屏播放的视频播放器组件，支持双击播放/暂停
class _FullscreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool showControls;
  final bool parentControlsVisible;
  final VoidCallback? onToggleControls;
  // 可选：HTTP 头用于鉴权播放
  final Map<String, String>? httpHeaders;

  const _FullscreenVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.showControls = true,
    this.parentControlsVisible = false,
    this.onToggleControls,
    this.httpHeaders,
  });

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showVideoControls = true;
  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;
  bool _isMuted = false;
  final GlobalKey _volumeIconKey = GlobalKey();
  OverlayEntry? _volumeOverlayEntry;
  bool _volumeOverlayVisible = false;
  bool _isScrubbing = false;
  // 拖动中的临时进度（0..1），仅在_scrubbing时生效
  double? _scrubFraction;
  bool _wasPlayingBeforeScrub = false;
  // 进度条测量用 key
  final GlobalKey _barKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();
  Timer? _volumeAdjustTimer;
  LogicalKeyboardKey? _currentPressedKey;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _showVideoControls = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: widget.httpHeaders ?? const <String, String>{},
      );
      await _controller.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        if (widget.autoPlay) {
          _controller.play();
        }
        _controller.setVolume(_volume);
        
        _controller.addListener(_videoListener);
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
    
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    
    if (duration > Duration.zero && position > Duration.zero) {
      final remaining = duration - position;
      // 当剩余时间少于100毫秒时暂停
      if (remaining <= const Duration(milliseconds: 100) && _controller.value.isPlaying) {
        _controller.pause();
        _controller.seekTo(duration);
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _hideVolumeOverlay();
    _volumeAdjustTimer?.cancel();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }


  void updateControlsVisibility(bool visible) {
    setState(() {
      _showVideoControls = visible;
    });
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  void _setVolume(double v) {
    v = v.clamp(0.0, 1.0);
    _controller.setVolume(v);
    setState(() {
      _volume = v;
      if (v > 0) {
        _lastNonZeroVolume = v;
      }
      _isMuted = v == 0.0;
    });
    
    if (_volumeOverlayEntry != null) {
      _volumeOverlayEntry!.markNeedsBuild();
    }
  }

  void _toggleMute() {
    if (_isMuted || _volume == 0.0) {
      _setVolume(_lastNonZeroVolume == 0 ? 1.0 : _lastNonZeroVolume);
    } else {
      _setVolume(0.0);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp || 
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        
        if (_currentPressedKey != event.logicalKey) {
          _volumeAdjustTimer?.cancel();
          _currentPressedKey = event.logicalKey;
          
          _adjustVolume(event.logicalKey);
          
          // 启动定时器进行连续调整（延迟300ms开始，然后每100ms重复）
          Timer(const Duration(milliseconds: 300), () {
            if (_currentPressedKey == event.logicalKey) {
              _volumeAdjustTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
                if (_currentPressedKey == event.logicalKey) {
                  _adjustVolume(event.logicalKey);
                } else {
                  timer.cancel();
                }
              });
            }
          });
        }
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == _currentPressedKey) {
        _volumeAdjustTimer?.cancel();
        _currentPressedKey = null;
      }
    }
  }

  void _adjustVolume(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      final newVolume = (_volume + 0.05).clamp(0.0, 1.0);
      _setVolume(newVolume);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final newVolume = (_volume - 0.05).clamp(0.0, 1.0);
      _setVolume(newVolume);
    }
  }

  void _toggleVolumeOverlay() {
    if (_volumeOverlayEntry != null) {
      _hideVolumeOverlay();
    } else {
      _showVolumeOverlay();
    }
  }

  void _showVolumeOverlay() {
    final overlay = Overlay.of(context);

    _volumeOverlayVisible = false; // 初始为不可见，用于入场动画
    _volumeOverlayEntry = OverlayEntry(
      builder: (context) {
        double tempVolume = _volume;
        
        final RenderBox? iconBox = _volumeIconKey.currentContext?.findRenderObject() as RenderBox?;
        final RenderBox overlayBox = overlay.context.findRenderObject() as RenderBox;
        if (iconBox == null) {
          return const SizedBox.shrink();
        }

        final Offset iconGlobal = iconBox.localToGlobal(Offset.zero);
        final Size iconSize = iconBox.size;

        const double panelWidth = 56;
        const double panelHeight = 172;
        final double left = iconGlobal.dx + iconSize.width / 2 - panelWidth / 2;
        final double top = iconGlobal.dy - panelHeight - 16;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideVolumeOverlay,
              ),
            ),
            Positioned(
              left: left.clamp(16.0, overlayBox.size.width - panelWidth - 18.0), //右侧留出空白
              top: top.clamp(8.0, overlayBox.size.height - panelHeight - 10.0),
              width: panelWidth,
              height: panelHeight,
              child: Material(
                color: Colors.transparent,
                child: StatefulBuilder(
                  builder: (context, setStateDialog) {
                    const duration = Duration(milliseconds: 180);
                    // 使用 AnimatedOpacity + TweenAnimationBuilder 实现向上淡入/向下淡出
                    return AnimatedOpacity(
                      opacity: _volumeOverlayVisible ? 1 : 0,
                      duration: duration,
                      curve: Curves.easeOut,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(_volumeOverlayVisible),
                        tween: Tween<double>(
                          begin: _volumeOverlayVisible ? 8 : 0, // 离场从0->8，下移
                          end: _volumeOverlayVisible ? 0 : 6,   // 入场从8->0，上移
                        ),
                        duration: duration,
                        curve: Curves.easeOut,
                        builder: (context, dy, child) {
                          return Transform.translate(
                            offset: Offset(0, dy),
                            child: child,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: -1,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                                    ),
                                    child: Slider(
                                      value: tempVolume,
                                      min: 0.0,
                                      max: 1.0,
                                      activeColor: Color(0xFFFB7299),
                                      inactiveColor: Colors.white24,
                                      onChanged: (val) {
                                        setStateDialog(() {
                                          tempVolume = val;
                                        });
                                        _setVolume(val);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(tempVolume * 100).round()}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_volumeOverlayEntry!);
    Future.delayed(const Duration(milliseconds: 16), () {
      if (_volumeOverlayEntry == null) return;
      _volumeOverlayVisible = true;
      _volumeOverlayEntry!.markNeedsBuild();
    });
  }

  void _hideVolumeOverlay() {
    if (_volumeOverlayEntry == null) return;
    _volumeOverlayVisible = false;
    _volumeOverlayEntry!.markNeedsBuild();
    Future.delayed(const Duration(milliseconds: 200), () {
      _volumeOverlayEntry?.remove();
      _volumeOverlayEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

return KeyboardListener(
  focusNode: _focusNode,
  onKeyEvent: _handleKeyEvent,
  child: GestureDetector(
    onTap: () {
      _hideVolumeOverlay();
      setState(() {
        _showVideoControls = !_showVideoControls;
      });
    },
    onDoubleTap: _togglePlayPause,
    child: Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        if (widget.showControls && _showVideoControls) _buildVideoControls(),
        // 视频模式下的关闭按钮（始终可用），间距参考顶部控制栏（高度100，水平内边距16，垂直居中）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: SizedBox(
              height: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(0x80), // 这里使用 withAlpha 替代 withValues
                      shape: BoxShape.circle,
                    ),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(FIcons.x, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 双击播放/暂停的视觉反馈
        if (!_controller.value.isPlaying)
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(0x80), // 这里使用 withAlpha 替代 withValues
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(20),
            child: const Icon(
              FIcons.play,
              color: Colors.white,
              size: 48,
            ),
          ),
      ],
    ),
  ),
);
  }


  Widget _buildVideoControls() {
    double bottomPosition = widget.parentControlsVisible ? 120 : 40;
    
    return Positioned(
      bottom: bottomPosition,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _togglePlayPause,
              child: Icon(
                _controller.value.isPlaying ? FIcons.pause : FIcons.play,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildAnimatedProgressBar()),
            const SizedBox(width: 12),
            Text(
              _formatDuration(_controller.value.position),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            Text(
              ' / ${_formatDuration(_controller.value.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              key: _volumeIconKey,
              onTap: _toggleVolumeOverlay,
              onLongPress: _toggleMute,
              child: Icon(
                _isMuted || _volume == 0
                    ? FIcons.volumeX
                    : (_volume < 0.5 ? FIcons.volume1 : FIcons.volume2),
                color: Colors.white,
              ),
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
        _wasPlayingBeforeScrub = _controller.value.isPlaying;
        if (_wasPlayingBeforeScrub) {
          _controller.pause();
        }
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: bufferedWidth,
                        color: bufferedColor,
                      ),
                    ),
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
