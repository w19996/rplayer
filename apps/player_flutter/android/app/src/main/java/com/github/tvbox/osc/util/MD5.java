package com.github.tvbox.osc.util;

import java.io.File;
import java.io.FileInputStream;
import java.security.MessageDigest;

public final class MD5 {
    private MD5() {}

    public static String encode(String value) {
        return digest(value == null ? new byte[0] : value.getBytes());
    }

    public static String string2MD5(String value) {
        return encode(value);
    }

    public static String getFileMd5(File file) {
        if (file == null || !file.exists()) return "";
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            FileInputStream input = new FileInputStream(file);
            try {
                byte[] buffer = new byte[8192];
                int len;
                while ((len = input.read(buffer)) > 0) md.update(buffer, 0, len);
            } finally {
                input.close();
            }
            return hex(md.digest());
        } catch (Exception e) {
            return "";
        }
    }

    private static String digest(byte[] bytes) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            return hex(md.digest(bytes));
        } catch (Exception e) {
            return "";
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) builder.append(String.format("%02x", value & 0xff));
        return builder.toString();
    }
}
