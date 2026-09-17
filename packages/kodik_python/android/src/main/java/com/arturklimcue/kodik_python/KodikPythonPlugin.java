package com.arturklimcue.kodik_python;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import com.chaquo.python.Python;
import com.chaquo.python.android.AndroidPlatform;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/// Мост Flutter ↔ настоящий CPython (Chaquopy).
public class KodikPythonPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "kodik/python";

    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        startPython();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("available".equals(call.method)) {
            result.success(Python.isStarted());
        } else if ("run".equals(call.method)) {
            String code = call.argument("code");
            List<String> stdin = call.argument("stdin");
            runPython(code == null ? "" : code, stdin == null ? new ArrayList<>() : stdin, result);
        } else {
            result.notImplemented();
        }
    }

    private void startPython() {
        try {
            if (!Python.isStarted()) {
                Python.start(new AndroidPlatform(context));
            }
        } catch (Throwable ignored) {
            // Python не поднялся — приложение откатится на встроенный движок.
        }
    }

    private void runPython(final String code, final List<String> stdin,
                           final MethodChannel.Result result) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                String json;
                try {
                    if (!Python.isStarted()) {
                        Python.start(new AndroidPlatform(context));
                    }
                    json = Python.getInstance()
                            .getModule("kodik_runtime")
                            .callAttr("run", code, new ArrayList<>(stdin))
                            .toString();
                } catch (Throwable t) {
                    json = errorJson(t.getMessage() == null ? t.toString() : t.getMessage());
                }
                final String payload = json;
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        result.success(payload);
                    }
                });
            }
        }).start();
    }

    private static String errorJson(String message) {
        try {
            return new JSONObject()
                    .put("ok", false)
                    .put("stdout", "")
                    .put("error", message)
                    .put("inputsMissing", 0)
                    .toString();
        } catch (Throwable t) {
            return "{\"ok\":false,\"stdout\":\"\",\"error\":\"internal\",\"inputsMissing\":0}";
        }
    }
}
