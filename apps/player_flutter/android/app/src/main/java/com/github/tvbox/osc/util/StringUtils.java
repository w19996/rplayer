package com.github.tvbox.osc.util;

public final class StringUtils {
    private StringUtils() {}

    public static boolean isEmpty(String value) {
        return value == null || value.length() == 0;
    }

    public static boolean isNotEmpty(String value) {
        return !isEmpty(value);
    }
}
