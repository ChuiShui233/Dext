package com.chuishui.Dext

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log
import android.content.Intent
import android.net.Uri
import android.app.Activity
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.chuishui.Dext/storage"
    private val CREATE_FILE_REQUEST = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var pendingFilePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 过滤AccessibilityBridge日志
        System.setProperty("flutter.accessibility.disable_animations", "true")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFileWithDialog" -> {
                    val hashMap = call.arguments as HashMap<*, *>
                    val path = hashMap["path"] as String
                    val fileName = hashMap["fileName"] as String
                    
                    pendingResult = result
                    pendingFilePath = path
                    
                    // 启动文件保存对话框
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, CREATE_FILE_REQUEST)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == CREATE_FILE_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                data.data?.let { uri ->
                    try {
                        val sourceFile = File(pendingFilePath!!)
                        contentResolver.openOutputStream(uri)?.use { output ->
                            sourceFile.inputStream().use { input ->
                                input.copyTo(output)
                            }
                        }
                        sourceFile.delete()
                        pendingResult?.success(uri.toString())
                    } catch (e: Exception) {
                        Log.e("MainActivity", "保存文件失败", e)
                        pendingResult?.error("SAVE_ERROR", e.message, null)
                    }
                }
            } else {
                pendingResult?.error("CANCELLED", "用户取消保存", null)
            }
            pendingResult = null
            pendingFilePath = null
        }
    }
}
