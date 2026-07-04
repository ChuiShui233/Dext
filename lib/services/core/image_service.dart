import '../config.dart';

class ImageService {
  static String getImageUrl(String? imageUrl, {String quality = 'medium'}) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    
    String absoluteUrl = imageUrl.startsWith('http') 
        ? imageUrl 
        : toAbsoluteUrl(imageUrl);
    
    if (quality != 'medium') {
      final separator = absoluteUrl.contains('?') ? '&' : '?';
      absoluteUrl = '$absoluteUrl${separator}type=$quality';
    }
    
    return absoluteUrl;
  }

  static String getThumbUrl(String? imageUrl) => getImageUrl(imageUrl, quality: 'thumb');
  static String getMediumUrl(String? imageUrl) => getImageUrl(imageUrl, quality: 'medium');
  static String getOriginalUrl(String? imageUrl) => getImageUrl(imageUrl, quality: 'original');
}
