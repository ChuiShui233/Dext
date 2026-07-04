// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// 在 Web 端触发浏览器下载，依旧web支持
/// 使用 Blob+Object URL，确保 UTF-8 BOM 原样保留，避免中文乱码。
Future<String?> downloadCsv(String suggestedFileName, List<int> bytes) async {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement;
  anchor.href = url;
  anchor.download = suggestedFileName;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return null;
}

Future<String?> downloadBytes(
  String suggestedFileName,
  List<int> bytes, {
  String? mimeType,
}) async {
  try {

    var fileName = suggestedFileName;
    if (mimeType == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
      if (!fileName.toLowerCase().endsWith('.xlsx')) {
        fileName = '$fileName.xlsx';
      }
    } else if (mimeType == 'text/csv' || mimeType == 'text/csv;charset=utf-8') {
      if (!fileName.toLowerCase().endsWith('.csv')) {
        fileName = '$fileName.csv';
      }
    }
    
    final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    
    await Future.delayed(const Duration(milliseconds: 200));
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return null;
  } catch (e) {

    return null;
  }
}
