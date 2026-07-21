package com.github.catvod.crawler.js;

import android.content.SharedPreferences;

import androidx.annotation.Keep;

import com.github.tvbox.osc.base.App;
import com.whl.quickjs.wrapper.Function;

public class local {
    private SharedPreferences store() {
        return App.getInstance().getSharedPreferences("tvbox_js_runtime", 0);
    }

    private String key(String str, String str2) {
        return "jsRuntime_" + str + "_" + str2;
    }

    @Keep@Function
    public void delete(String str, String str2) {
        try {
            store().edit().remove(key(str, str2)).apply();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    @Keep@Function
    public String get(String str, String str2) {
        try {
            return store().getString(key(str, str2), "");
        } catch (Exception e) {
            return str2;
        }
    }

    @Keep@Function
    public void set(String str, String str2, String str3) {
        try {
            store().edit().putString(key(str, str2), str3).apply();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
