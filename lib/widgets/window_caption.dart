import 'dart:io';
import 'package:forui/forui.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:dext/widgets/app_navigator.dart';
import '../services/settings_service.dart';

class WindowCaption extends StatefulWidget {
  const WindowCaption({super.key});

  @override
  State<WindowCaption> createState() => _WindowCaptionState();
}

class _WindowCaptionState extends State<WindowCaption> with WindowListener {
  bool _isMaximized = false;
  bool _isDialogOpen = false;

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
      // 防止重复打开弹窗
      if (_isDialogOpen) return;
      
      // 检查用户是否选择了不再提示
      final settings = SettingsService();
      final dontAskAgain = settings.windowCloseDontAsk;
      final defaultAction = settings.windowCloseDefaultAction;
      
      if (dontAskAgain && defaultAction != 'ask') {
        // 直接执行默认操作
        if (defaultAction == 'hide') {
          await windowManager.hide();
        } else if (defaultAction == 'close') {
          await TrayManager.instance.destroy();
          await windowManager.destroy();
          exit(0);
        }
        return;
      }
      
      if (!mounted) return;
      final navCtx = appNavigatorKey.currentContext;
      if (navCtx == null || !navCtx.mounted) return;
      
      _isDialogOpen = true;
      
      bool dontAskAgainChecked = false;
      
      await showDialog(
        context: navCtx,
        barrierDismissible: true,
        builder: (dialogContext) {
          bool animateIn = false;
          bool isClosing = false;
          const animationDuration = Duration(milliseconds: 220);

          return StatefulBuilder(
            builder: (builderContext, setDialogState) {
              if (!animateIn && !isClosing) {
                Future.microtask(() {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      animateIn = true;
                    });
                  }
                });
              }

              Future<void> closeDialogWithAnimation(Future<void> Function()? afterPop) async {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  animateIn = false;
                  isClosing = true;
                });
                await Future.delayed(animationDuration);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  setState(() {
                    _isDialogOpen = false;
                  });
                }
                if (afterPop != null) {
                  await afterPop();
                }
              }

              return AnimatedOpacity(
                opacity: animateIn ? 1.0 : 0.0,
                duration: animationDuration,
                curve: animateIn ? Curves.easeOutCubic : Curves.easeInCubic,
                child: AnimatedScale(
                  scale: animateIn ? 1.0 : 0.92,
                  duration: animationDuration,
                  curve: animateIn ? Curves.easeOutBack : Curves.easeInCubic,
                  child: Center(
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
                            FCheckbox(
                              label: const Text('下次不再提示，记住我的选择'),
                              semanticsLabel: '记住关闭行为',
                              value: dontAskAgainChecked,
                              onChange: (value) {
                                setDialogState(() {
                                  dontAskAgainChecked = value;
                                });
                              },
                            ),
                          ],
                        ),
                        actions: [
                          FButton(
                            style: context.theme.buttonStyles.ghost.call,
                            onPress: () => closeDialogWithAnimation(null),
                            child: const Text('取消'),
                          ),
                          FButton(
                            style: context.theme.buttonStyles.outline.call,
                            onPress: () async {
                              if (dontAskAgainChecked) {
                                final settings = SettingsService();
                                await settings.setWindowCloseDontAsk(true);
                                await settings.setWindowCloseDefaultAction('hide');
                              }
                              await closeDialogWithAnimation(() async {
                                await windowManager.hide();
                              });
                            },
                            child: const Text('隐藏'),
                          ),
                          FButton(
                            style: context.theme.buttonStyles.outline.call,
                            onPress: () async {
                              if (dontAskAgainChecked) {
                                final settings = SettingsService();
                                await settings.setWindowCloseDontAsk(true);
                                await settings.setWindowCloseDefaultAction('close');
                              }
                              await closeDialogWithAnimation(() async {
                                await TrayManager.instance.destroy();
                                await windowManager.destroy();
                                exit(0);
                              });
                            },
                            child: const Text('关闭应用'),
                          ),
                        ],
                      ),
                    ),
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
