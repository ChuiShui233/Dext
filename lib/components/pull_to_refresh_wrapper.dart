import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class PullToRefreshWrapper extends StatelessWidget {
  final RefreshController controller;
  final VoidCallback onRefresh;
  final Widget child;
  final bool enablePullDown;
  final bool enablePullUp;

  const PullToRefreshWrapper({
    super.key,
    required this.controller,
    required this.onRefresh,
    required this.child,
    this.enablePullDown = true,
    this.enablePullUp = false,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      child: SmartRefresher(
        controller: controller,
        onRefresh: onRefresh,
        enablePullDown: enablePullDown,
        enablePullUp: enablePullUp,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        header: ClassicHeader(
          height: 60,
          refreshingIcon: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          completeIcon: const Icon(Icons.check, size: 20),
          failedIcon: const Icon(Icons.error_outline, size: 20),
          idleIcon: const Icon(Icons.arrow_downward, size: 20),
          releaseIcon: const Icon(Icons.refresh, size: 20),
          idleText: '下拉刷新',
          refreshingText: '加载中...',
          completeText: '刷新完成',
          failedText: '刷新失败',
          releaseText: '松开刷新',
        ),
        child: child,
      ),
    );
  }
}
