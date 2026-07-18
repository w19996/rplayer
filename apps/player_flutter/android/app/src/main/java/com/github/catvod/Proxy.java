// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from q215613905/TVBoxOS commit 0409954033a44582b431d89934e3980900f4a265.
package com.github.catvod;

public class Proxy {

    private static int port = 9978;

    public static void set(int port) {
        Proxy.port = port;
    }

    public static int getPort() {
        return port > 0 ? port : 9978;
    }

    public static String getUrl(boolean local) {
        return "http://127.0.0.1:" + getPort() + "/proxy";
    }
}
