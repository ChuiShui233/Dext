package com.chuishui.Dext

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log
import android.content.Intent
import android.net.Uri
import android.app.Activity
import android.os.PowerManager
import android.os.Build
import android.content.Context
import android.provider.Settings
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.chuishui.Dext/storage"
    private val POWER_CHANNEL = "com.chuishui.Dext/power"
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

        // Power/battery optimization channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                        } else {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
                            result.success(isIgnoring)
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "check ignore battery optimization failed", e)
                        result.success(false)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                        } else {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (pm.isIgnoringBatteryOptimizations(packageName)) {
                                result.success(true)
                            } else {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "request ignore battery optimization failed", e)
                        result.success(false)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (ee: Exception) {
                            Log.e("MainActivity", "open settings failed", ee)
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
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
