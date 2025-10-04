package com.chuishui.Dext

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 过滤AccessibilityBridge日志
        System.setProperty("flutter.accessibility.disable_animations", "true")
    }
}
