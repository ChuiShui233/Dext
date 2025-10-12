import 'package:forui/forui.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dext/widgets/app_navigator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // 检查用户是否选择了不再提示
      final prefs = await SharedPreferences.getInstance();
      final dontAskAgain = prefs.getBool('window_close_dont_ask') ?? false;
      final defaultAction = prefs.getString('window_close_default_action') ?? 'ask';
      
      if (dontAskAgain && defaultAction != 'ask') {
        // 直接执行默认操作
        if (defaultAction == 'hide') {
          await windowManager.hide();
        } else if (defaultAction == 'close') {
          await windowManager.destroy();
        }
        return;
      }
      
      if (!mounted) return;
      final navCtx = appNavigatorKey.currentContext;
      if (navCtx == null || !navCtx.mounted) return;
      
      bool dontAskAgainChecked = false;
      
      await showDialog(
        context: navCtx,
        barrierDismissible: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (builderContext, setDialogState) {
              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: FDialog(
                    direction: Axis.horizontal,
                    title: const Text('确认操作'),
                    body: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('你要关闭应用还是最小化到任务栏？'),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              dontAskAgainChecked = !dontAskAgainChecked;
                            });
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: dontAskAgainChecked,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      dontAskAgainChecked = value ?? false;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('下次不再提示，记住我的选择'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      FButton(
                        style: FButtonStyle.ghost,
                        onPress: () => Navigator.of(dialogContext).pop(),
                        child: const Text('取消'),
                      ),
                      FButton(
                        style: FButtonStyle.outline,
                        onPress: () async {
                          if (dontAskAgainChecked) {
                            await prefs.setBool('window_close_dont_ask', true);
                            await prefs.setString('window_close_default_action', 'hide');
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          await windowManager.hide();
                        },
                        child: const Text('隐藏到托盘'),
                      ),
                      FButton(
                        style: FButtonStyle.outline,
                        onPress: () async {
                          if (dontAskAgainChecked) {
                            await prefs.setBool('window_close_dont_ask', true);
                            await prefs.setString('window_close_default_action', 'close');
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
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
        },
      );
    }

    return Container(
      height: 40,
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(color: Colors.transparent),
            ),
          ),
          _CaptionIconButton(
            icon: FIcons.minus,
            onPressed: () => windowManager.minimize(),
            color: iconColor,
          ),
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
