import 'package:forui/forui.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dext/widgets/app_navigator.dart';

class WindowCaption extends StatefulWidget {
  const WindowCaption({super.key});

  @override
  State<WindowCaption> createState() => _WindowCaptionState();
}

class _WindowCaptionState extends State<WindowCaption> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    windowManager.addListener(this);
    _updateMaximizedStatus();
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _updateMaximizedStatus() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted && isMaximized != _isMaximized) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black;

    Future<void> showCloseConfirmDialog() async {
      final navCtx = appNavigatorKey.currentContext;
      if (navCtx == null) return;
      await showDialog(
        context: navCtx,
        barrierDismissible: true,
        builder: (ctx) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: FDialog(
                direction: Axis.horizontal,
                title: const Text('确认操作'),
                body: const Text('你要关闭应用还是最小化到任务栏？'),
                actions: [
                  FButton(
                    style: FButtonStyle.ghost,
                    onPress: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  FButton(
                    style: FButtonStyle.outline,
                    onPress: () async {
                      Navigator.of(ctx).pop();
                      await windowManager.hide();
                    },
                    child: const Text('隐藏到托盘'),
                  ),
                  FButton(
                    style: FButtonStyle.outline,
                    onPress: () async {
                      Navigator.of(ctx).pop();
                      // 直接销毁应用，绕过 preventClose 拦截
                      await windowManager.destroy();
                    },
                    child: const Text('关闭应用'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      height: 40,
      color: Colors.transparent,
      child: Row(
        children: [
          // 拖动区域
          Expanded(
            child: DragToMoveArea(
              child: Container(color: Colors.transparent),
            ),
          ),
          // 最小化按钮
          _CaptionIconButton(
            icon: FIcons.minus,
            onPressed: () => windowManager.minimize(),
            color: iconColor,
          ),
          // 最大化/还原切换按钮
          _CaptionIconButton(
            icon: _isMaximized ? FIcons.copy : FIcons.square,
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.restore();
              } else {
                await windowManager.maximize();
              }
            },
            color: iconColor,
          ),
          // 关闭按钮
          _CaptionIconButton(
            icon: FIcons.x,
            onPressed: showCloseConfirmDialog,
            color: iconColor,
            hoverColor: Colors.red.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}

// 自定义方形按钮组件
class _CaptionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final Color? hoverColor;

  const _CaptionIconButton({
    required this.icon,
    required this.onPressed,
    required this.color,
    this.hoverColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverColor ?? Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.zero, // 方角
          child: Center(
            child: Icon(icon, color: color, size: 16),
          ),
        ),
      ),
    );
  }
}
