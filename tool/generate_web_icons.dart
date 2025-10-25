import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  try {
    final sourceImagePath = 'assets/images/Dext.png';
    final faviconIcoPath = 'assets/images/favicon.ico';
    final webIconsDir = 'web/icons';
    final faviconPngPath = 'web/favicon.png';

    final sourceFile = File(sourceImagePath);
    if (!await sourceFile.exists()) exit(1);
    
    final sourceBytes = await sourceFile.readAsBytes();
    final sourceImage = img.decodeImage(sourceBytes);
    
    if (sourceImage == null) exit(1);

    final iconsDir = Directory(webIconsDir);
    if (!await iconsDir.exists()) {
      await iconsDir.create(recursive: true);
    }

    final iconSizes = [
      {'size': 192, 'name': 'Icon-192.png', 'maskable': false},
      {'size': 512, 'name': 'Icon-512.png', 'maskable': false},
      {'size': 192, 'name': 'Icon-maskable-192.png', 'maskable': true},
      {'size': 512, 'name': 'Icon-maskable-512.png', 'maskable': true},
    ];

    for (final iconConfig in iconSizes) {
      final size = iconConfig['size'] as int;
      final name = iconConfig['name'] as String;
      final isMaskable = iconConfig['maskable'] as bool;
      
      img.Image icon;
      
      if (isMaskable) {

        icon = img.Image(width: size, height: size);
        
        img.fill(icon, color: img.ColorRgba8(255, 255, 255, 0));
        
        final scaledSize = (size * 0.8).round();
        final scaledImage = img.copyResize(
          sourceImage,
          width: scaledSize,
          height: scaledSize,
          interpolation: img.Interpolation.linear,
        );
        
        final offset = ((size - scaledSize) / 2).round();
        img.compositeImage(icon, scaledImage, dstX: offset, dstY: offset);
      } else {

        icon = img.copyResize(
          sourceImage,
          width: size,
          height: size,
          interpolation: img.Interpolation.linear,
        );
      }
      
      final iconPath = '$webIconsDir/$name';
      final iconFile = File(iconPath);
      await iconFile.writeAsBytes(img.encodePng(icon));
    }

    final faviconIcoFile = File(faviconIcoPath);
    
    if (!await faviconIcoFile.exists()) {
      
      final faviconImage = img.copyResize(
        sourceImage,
        width: 48,
        height: 48,
        interpolation: img.Interpolation.linear,
      );
      
      final faviconFile = File(faviconPngPath);
      await faviconFile.writeAsBytes(img.encodePng(faviconImage));
    } else {

      final icoBytes = await faviconIcoFile.readAsBytes();
      final icoImage = img.decodeIco(icoBytes);
      
      if (icoImage == null) exit(1);
      
      final faviconFile = File(faviconPngPath);
      await faviconFile.writeAsBytes(img.encodePng(icoImage));
    }

    // ignore: avoid_print
    print('Done');
    
  } catch (e) {
    exit(1);
  }
}
