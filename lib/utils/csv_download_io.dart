import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('com.chuishui.Dext/storage');

Future<String?> downloadCsv(String suggestedFileName, List<int> bytes) async {
  try {
    // Android
    if (Platform.isAndroid) {
      // 先保存到临时目录
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$suggestedFileName');
      await tempFile.writeAsBytes(bytes, flush: true);
      
      try {
        // 调用原生方法
        await platform.invokeMethod('saveFileWithDialog', {
          'path': tempFile.path,
          'fileName': suggestedFileName,
        });
        return ' $suggestedFileName';
      } catch (e) {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
        return null;
      }
    }
    
    // iOS: 使用文档目录
    if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$suggestedFileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    
    // 桌面端使用文件选择器
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '保存为 CSV',
      fileName: suggestedFileName,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      lockParentWindow: true,
    );
    if (picked != null) {
      final file = File(picked);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    return null;
  } catch (e) {
    return null;
  }
}

/// 保存任意二进制数据到本地，返回保存路径
Future<String?> downloadBytes(String suggestedFileName, List<int> bytes, {String? mimeType}) async {
  try {
    // Android: 使用文件保存对话框
    if (Platform.isAndroid) {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$suggestedFileName');
      await tempFile.writeAsBytes(bytes, flush: true);
      
      try {
        await platform.invokeMethod('saveFileWithDialog', {
          'path': tempFile.path,
          'fileName': suggestedFileName,
        });
        return '已保存: $suggestedFileName';
      } catch (e) {
        // 用户取消或失败，删除临时文件
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
        return null;
      }
    }
    
    // iOS: 使用文档目录
    if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$suggestedFileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    
    // 桌面端使用文件选择器
    String ext = '';
    final dot = suggestedFileName.lastIndexOf('.');
    if (dot != -1 && dot < suggestedFileName.length - 1) {
      ext = suggestedFileName.substring(dot + 1).toLowerCase();
    }
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '保存文件',
      fileName: suggestedFileName,
      type: ext.isNotEmpty ? FileType.custom : FileType.any,
      allowedExtensions: ext.isNotEmpty ? [ext] : null,
      lockParentWindow: true,
    );
    if (picked != null) {
      final file = File(picked);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    return null;
  } catch (e) {
    return null;
  }
}

