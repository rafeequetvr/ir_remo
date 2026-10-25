package com.custom.ir_remote

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.custom.ir_remote/ir"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val irManager = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
            
            when (call.method) {
                "hasIrEmitter" -> {
                    result.success(irManager?.hasIrEmitter() ?: false)
                }
                "transmit" -> {
                    if (irManager == null || !irManager.hasIrEmitter()) {
                        result.error("NO_IR", "No IR Blaster found on this device", null)
                        return@setMethodCallHandler
                    }
                    val frequency = call.argument<Int>("frequency") ?: 38000
                    val pattern = call.argument<List<Int>>("pattern")?.toIntArray()
                    
                    if (pattern != null) {
                        irManager.transmit(frequency, pattern)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATTERN", "Invalid IR pattern", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
