import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:crop_image_plus/crop_image_plus.dart';
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
          title: Text('裁剪失败: $e'),
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
    
    return FDialog(
      direction: Axis.horizontal,
      title: const Text('裁剪头像'),
      body: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          children: [
            const Text('拖动边角调整裁剪区域，将裁剪为 1:1 正方形'),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: CropImage(
                    controller: _cropController,
                    image: widget.imageBytes != null
                        ? Image.memory(widget.imageBytes!, fit: BoxFit.contain)
                        : Image.file(widget.imageFile!, fit: BoxFit.contain),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FButton.icon(
                  style: FButtonStyle.outline,
                  onPress: _isProcessing ? null : () => _cropController.rotateLeft(),
                  child: const Icon(FIcons.rotateCcw, size: 20),
                ),
                const SizedBox(width: 16),
                FButton.icon(
                  style: FButtonStyle.outline,
                  onPress: _isProcessing ? null : () => _cropController.rotateRight(),
                  child: const Icon(FIcons.rotateCw, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline,
          intrinsicWidth: true,
          onPress: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FButton(
          intrinsicWidth: true,
          onPress: _isProcessing
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
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确定'),
        ),
      ],
    );
  }
}
