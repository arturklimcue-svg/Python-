package com.arturklimcue.kodik

import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "kodik/python"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(applicationContext))
            }
        } catch (t: Throwable) {
            // Настоящий Python не поднялся — приложение откатится на
            // встроенный учебный интерпретатор.
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(Python.isStarted())
                    "run" -> runPython(call.argument<String>("code") ?: "",
                        call.argument<List<String>>("stdin") ?: emptyList(), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun runPython(code: String, stdin: List<String>, result: MethodChannel.Result) {
        Thread {
            val json = try {
                if (!Python.isStarted()) {
                    Python.start(AndroidPlatform(applicationContext))
                }
                val module = Python.getInstance().getModule("kodik_runtime")
                module.callAttr("run", code, ArrayList(stdin)).toString()
            } catch (t: Throwable) {
                JSONObject()
                    .put("ok", false)
                    .put("stdout", "")
                    .put("error", t.message ?: t.toString())
                    .put("inputsMissing", 0)
                    .toString()
            }
            runOnUiThread { result.success(json) }
        }.start()
    }
}
