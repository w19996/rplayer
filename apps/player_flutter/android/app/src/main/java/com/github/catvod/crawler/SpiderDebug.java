// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from q215613905/TVBoxOS commit 0409954033a44582b431d89934e3980900f4a265.
package com.github.catvod.crawler;

public class SpiderDebug {
    public static void log(Throwable error) {
        try {
            android.util.Log.d("SpiderLog", error.getMessage(), error);
        } catch (Throwable ignored) {
        }
    }

    public static void log(String message) {
        try {
            android.util.Log.d("SpiderLog", message);
        } catch (Throwable ignored) {
        }
    }

    public static String ec(int value) {
        return "";
    }
}
