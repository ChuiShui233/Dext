import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

Future<bool> showExitConfirmDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
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

          Future<void> closeDialogWithAnimation(bool result) async {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              animateIn = false;
              isClosing = true;
            });
            await Future.delayed(animationDuration);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(result);
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
                    title: const Text('确认退出'),
                    body: const Text('确定要退出应用吗？'),
                    actions: [
                      FButton(
                        style: context.theme.buttonStyles.outline.call,
                        onPress: () => closeDialogWithAnimation(false),
                        child: const Text('取消'),
                      ),
                      FButton(
                        onPress: () => closeDialogWithAnimation(true),
                        child: const Text('退出'),
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

  return result == true;
}