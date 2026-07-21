package com.github.tvbox.osc.util;

import com.github.catvod.net.OkHttp;
import com.github.tvbox.osc.base.App;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.util.concurrent.ConcurrentHashMap;

import okhttp3.Request;
import okhttp3.Response;

public final class FileUtils {
    private static final long WEEK_MS = 7L * 24L * 60L * 60L * 1000L;
    private static final ConcurrentHashMap<String, String> modules = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, byte[]> byteCache = new ConcurrentHashMap<>();

    private FileUtils() {}

    public static boolean isWeekAgo(File file) {
        return file == null || System.currentTimeMillis() - file.lastModified() > WEEK_MS;
    }

    public static String loadModule(String moduleName) {
        if (moduleName == null || moduleName.trim().isEmpty()) return "";
        return modules.computeIfAbsent(moduleName, FileUtils::loadModuleInternal);
    }

    public static void setCacheByte(String key, byte[] value) {
        if (key != null && value != null) byteCache.put(key, value);
    }

    public static byte[] getCacheByte(String key) {
        return key == null ? null : byteCache.get(key);
    }

    private static String loadModuleInternal(String moduleName) {
        String value = moduleName.trim();
        if (value.startsWith("http://") || value.startsWith("https://")) {
            return loadUrl(value);
        }
        String asset = value;
        if (asset.startsWith("assets://")) asset = asset.substring("assets://".length());
        if (asset.startsWith("/")) asset = asset.substring(1);
        if (!asset.startsWith("js/")) asset = "js/lib/" + asset;
        return loadAsset(asset);
    }

    private static String loadUrl(String url) {
        Request request = new Request.Builder()
                .url(url)
                .header("User-Agent", "rplayer-tvbox/1.0")
                .build();
        try {
            Response response = OkHttp.client().newCall(request).execute();
            try {
                if (!response.isSuccessful() || response.body() == null) return "";
                return response.body().string();
            } finally {
                response.close();
            }
        } catch (Exception e) {
            LOG.i("loadModule url failed: " + url + ", " + e.getMessage());
            return "";
        }
    }

    private static String loadAsset(String path) {
        try {
            InputStream input = App.getInstance().getAssets().open(path);
            try {
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                byte[] buffer = new byte[8192];
                int len;
                while ((len = input.read(buffer)) > 0) output.write(buffer, 0, len);
                return output.toString("UTF-8");
            } finally {
                input.close();
            }
        } catch (Exception e) {
            LOG.i("loadModule asset failed: " + path + ", " + e.getMessage());
            return "";
        }
    }
}
