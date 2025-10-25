import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:forui/forui.dart';

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
        header: CustomHeader(
          builder: (context, mode) {
            Widget icon;
            if (mode == RefreshStatus.idle) {
              icon = Icon(FIcons.chevronDown, size: 25);
            } else if (mode == RefreshStatus.refreshing) {
              icon = const SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            } else if (mode == RefreshStatus.completed) {
              icon = Icon(FIcons.check, size: 25, color: Colors.green);
            } else if (mode == RefreshStatus.failed) {
              icon = Icon(FIcons.x, size: 25, color: Colors.red);
            } else {
              icon = Icon(FIcons.chevronDown, size: 20);
            }
            
            return Container(
              height: 60,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(mode),
                  child: icon,
                ),
              ),
            );
          },
        ),
        child: child,
      ),
    );
  }
}
