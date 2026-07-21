package com.github.tvbox.osc.util;

import android.util.Log;

public final class LOG {
    private static final String TAG = "TvboxRuntime";

    private LOG() {}

    public static void i(String msg) {
        Log.i(TAG, msg == null ? "" : msg);
    }

    public static void e(String msg) {
        Log.e(TAG, msg == null ? "" : msg);
    }

    public static void e(String tag, String msg) {
        Log.e(tag == null ? TAG : tag, msg == null ? "" : msg);
    }
}
