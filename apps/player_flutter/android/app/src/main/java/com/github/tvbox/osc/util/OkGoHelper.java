package com.github.tvbox.osc.util;

import com.github.catvod.net.OkHttp;

import okhttp3.OkHttpClient;

public final class OkGoHelper {
    private static volatile OkHttpClient defaultClient;

    private OkGoHelper() {}

    public static OkHttpClient getDefaultClient() {
        if (defaultClient == null) defaultClient = OkHttp.client();
        return defaultClient;
    }

    public static void setDefaultClient(OkHttpClient client) {
        defaultClient = client;
    }
}
