package com.github.tvbox.osc.base;

import android.app.Application;

public final class App {
    private static Application instance;

    private App() {}

    public static void setInstance(Application application) {
        instance = application;
    }

    public static Application getInstance() {
        if (instance == null) throw new IllegalStateException("TVBox App host is not initialized");
        return instance;
    }
}
