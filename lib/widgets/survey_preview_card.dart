import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../services/config.dart';

@immutable
class SurveyPreview {
  final String name;
  final String creatorName;
  final String creatorAvatar;
  final String createdAt;

  const SurveyPreview({
    required this.name,
    required this.creatorName,
    this.creatorAvatar = '',
    required this.createdAt,
  });

  static SurveyPreview? tryFrom(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    final name = (data['surveyName'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    final creator = (data['createdBy'] as String?)?.trim() ?? '';
    final avatar = (data['creatorAvatar'] as String?)?.trim() ?? '';
    final created = (data['createdAt'] as String?)?.trim() ?? '';
    return SurveyPreview(
      name: name,
      creatorName: creator,
      creatorAvatar: avatar,
      createdAt: created,
    );
  }

  String get formattedCreatedAt {
    if (createdAt.isEmpty) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return createdAt;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class SurveyPreviewCard extends StatelessWidget {
  final SurveyPreview preview;

  final bool prominent;

  const SurveyPreviewCard({
    super.key,
    required this.preview,
    this.prominent = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final subFg = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.55);

    final titleStyle = TextStyle(
      fontSize: prominent ? 18 : 15,
      fontWeight: FontWeight.w600,
      color: fg,
      fontFamily: 'PingFangSuper',
    );
    final subStyle = TextStyle(
      fontSize: prominent ? 12 : 11,
      color: subFg,
      fontFamily: 'PingFangSuper',
    );

    final hasCreator = preview.creatorName.isNotEmpty;
    final hasCreatedAt = preview.formattedCreatedAt.isNotEmpty;
    final subParts = <String>[
      if (hasCreator) '发布者：${preview.creatorName}',
      if (hasCreatedAt) '发布时间：${preview.formattedCreatedAt}',
    ];

    final avatarSize = prominent ? 42.0 : 36.0;
    final showAvatar = hasCreator;
    final avatarWidget = showAvatar
        ? _CreatorAvatar(
            url: preview.creatorAvatar,
            fallbackText: preview.creatorName,
            size: avatarSize,
            isDark: isDark,
          )
        : SizedBox(width: avatarSize, height: avatarSize);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: prominent ? 22 : 20,
          sigmaY: prominent ? 22 : 20,
          tileMode: TileMode.clamp,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.80),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: prominent ? 16 : 12,
              vertical: prominent ? 14 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                avatarWidget,
                if (showAvatar) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            FIcons.clipboardList,
                            size: prominent ? 18 : 14,
                            color: subFg,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              preview.name,
                              style: titleStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (subParts.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subParts.join('  ·  '),
                          style: subStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 作者头像
class _CreatorAvatar extends StatelessWidget {
  final String url;
  final String fallbackText;
  final double size;
  final bool isDark;

  const _CreatorAvatar({
    required this.url,
    required this.fallbackText,
    required this.size,
    required this.isDark,
  });

  String get _initial {
    final t = fallbackText.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: isDark ? Colors.black : Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          fontFamily: 'PingFangSuper',
        ),
      ),
    );

    if (url.isEmpty) return placeholder;

    return _NetworkImageWithFallback(
      primaryUrl: toAbsoluteUrl(url),
      fallbackUrl: _cdnFallback(url),
      width: size,
      height: size,
      placeholder: placeholder,
      isDark: isDark,
    );
  }

  // 旧路径头像降级：/uploads/avatars/xxx.jpg → /openassets/files/user-avatars/xxx
  String? _cdnFallback(String originalUrl) {
    if (originalUrl.isEmpty) return null;
    final normalized = originalUrl.startsWith('/')
        ? originalUrl
        : '/$originalUrl';
    if (normalized.startsWith('/uploads/avatars/')) {
      final rest = normalized.substring('/uploads/avatars/'.length);
      final dot = rest.lastIndexOf('.');
      final publicName = dot > 0 ? rest.substring(0, dot) : rest;
      return toAbsoluteUrl('/openassets/files/user-avatars/$publicName');
    }
    return null;
  }
}

class _NetworkImageWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String? fallbackUrl;
  final double width;
  final double height;
  final Widget placeholder;
  final bool isDark;

  const _NetworkImageWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.width,
    required this.height,
    required this.placeholder,
    required this.isDark,
  });

  @override
  State<_NetworkImageWithFallback> createState() => _NetworkImageWithFallbackState();
}

class _NetworkImageWithFallbackState extends State<_NetworkImageWithFallback> {
  String? _currentUrl;
  int _retryKey = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.primaryUrl;
  }

  void _onError() {
    if (!mounted) return;
    final fb = widget.fallbackUrl;
    if (fb != null && _currentUrl != fb) {
      setState(() {
        _currentUrl = fb;
        _retryKey++;
      });
    } else {
      setState(() {
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.placeholder;

    return ClipOval(
      child: Image.network(
        _currentUrl!,
        key: ValueKey('$_retryKey-$_currentUrl'),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded) return child;
          if (frame == null) return widget.placeholder;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: ClipOval(child: child),
          );
        },
        errorBuilder: (_, __, ___) {
          _onError();
          return widget.placeholder;
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return widget.placeholder;
        },
      ),
    );
  }
}
