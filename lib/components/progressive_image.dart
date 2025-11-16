import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

/// 渐进式图片加载组件
/// 
/// 先加载缩略图，再异步加载高质量图替换
/// 支持占位符和错误处理
class ProgressiveImage extends StatefulWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool loadHighQuality;
  final String initialQuality;
  final BorderRadius? borderRadius;

  const ProgressiveImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.loadHighQuality = true,
    this.initialQuality = 'thumb',
    this.borderRadius,
  });

  @override
  State<ProgressiveImage> createState() => _ProgressiveImageState();
}

class _ProgressiveImageState extends State<ProgressiveImage> {
  String? _currentImageUrl;

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  @override
  void didUpdateWidget(ProgressiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _initializeImage();
    }
  }

  void _initializeImage() {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      setState(() {
        _currentImageUrl = null;
      });
      return;
    }

    // 先加载初始质量图片（缩略图或中等质量）
    setState(() {
      _currentImageUrl = ApiService.getImageUrl(
        widget.imageUrl,
        quality: widget.initialQuality,
      );
    });

    // 如果需要，异步加载高质量图
    if (widget.loadHighQuality && widget.initialQuality != 'original') {
      _loadHighQualityImage();
    }
  }

  Future<void> _loadHighQualityImage() async {
    if (!mounted) return;

    // 延迟一小段时间，确保低质量图先显示
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _currentImageUrl = ApiService.getMediumUrl(widget.imageUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentImageUrl == null || _currentImageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: _currentImageUrl!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: (context, url) => widget.placeholder ?? _buildPlaceholder(),
      errorWidget: (context, url, error) => 
          widget.errorWidget ?? _buildErrorWidget(),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 100),
    );

    // 如果有圆角，添加 ClipRRect
    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 48),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
      ),
    );
  }
}

/// 简单的图片加载组件（不使用渐进式加载）
class SimpleNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String quality;
  final BorderRadius? borderRadius;

  const SimpleNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.quality = 'medium',
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    final url = ApiService.getImageUrl(imageUrl, quality: quality);

    Widget imageWidget = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) => _buildErrorWidget(),
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
      ),
    );
  }
}
