import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:crop_image_plus/crop_image_plus.dart';
import '../components/loading_indicator.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

class CropImageDialog extends StatefulWidget {
  final Uint8List? imageBytes;
  final File? imageFile;

  const CropImageDialog({
    super.key,
    this.imageBytes,
    this.imageFile,
  }) : assert(imageBytes != null || imageFile != null);

  @override
  State<CropImageDialog> createState() => _CropImageDialogState();
}

class _CropImageDialogState extends State<CropImageDialog> {
  late final CropController _cropController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cropController = CropController(
      aspectRatio: 1.0,
      defaultCrop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
    );
  }

  @override
  void dispose() {
    _cropController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _getCroppedImage() async {
    setState(() => _isProcessing = true);
    
    try {
      final ui.Image bitmap = await _cropController.croppedBitmap();
      final ByteData? data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      
      if (data == null) return null;
      
      return data.buffer.asUint8List();
    } catch (e) {
      if (mounted) {
        showFToast(
          context: context,
          alignment: FToastAlignment.bottomRight,
          title: const Text('裁剪失败'),
          description: Text('$e'),
          suffixBuilder: (context, entry) => IntrinsicHeight(
            child: FButton(
              style: context.theme.buttonStyles.primary.call,
              onPress: entry.dismiss.call,
              child: const Text('关闭'),
            ),
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: size.width.clamp(0, 700).toDouble(),
              maxHeight: size.height.clamp(0, 800).toDouble(),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '裁剪头像',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CropImage(
                            controller: _cropController,
                            image: widget.imageBytes != null
                                ? Image.memory(widget.imageBytes!, fit: BoxFit.cover)
                                : Image.file(widget.imageFile!, fit: BoxFit.cover),
                            gridColor: Colors.white.withValues(alpha: 0.7),
                            gridCornerSize: 30,
                            gridThinWidth: 2,
                            gridThickWidth: 4,
                            scrimColor: Colors.black.withValues(alpha: 0.54),
                            alwaysShowThirdLines: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          FButton.icon(
                            style: context.theme.buttonStyles.outline.call,
                            onPress: _isProcessing
                                ? null
                                : () {
                                    _cropController.rotateLeft();
                                    _cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                  },
                            child: const Icon(FIcons.rotateCcw, size: 20),
                          ),
                          const SizedBox(width: 8),
                          FButton.icon(
                            style: context.theme.buttonStyles.outline.call,
                            onPress: _isProcessing
                                ? null
                                : () {
                                    _cropController.rotateRight();
                                    _cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                  },
                            child: const Icon(FIcons.rotateCw, size: 20),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _isProcessing ? null : () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isProcessing
                                ? null
                                : () async {
                                    final navigator = Navigator.of(context);
                                    final croppedBytes = await _getCroppedImage();
                                    if (!mounted) return;
                                    if (croppedBytes != null) {
                                      navigator.pop(croppedBytes);
                                    }
                                  },
                            child: _isProcessing
                                ? const LoadingIndicator.button()
                                : const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
