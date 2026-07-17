// SPDX-License-Identifier: AGPL-3.0-only
package com.example.player_flutter

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.github.catvod.crawler.ProtectedInitJar
import com.github.catvod.crawler.Spider
import com.github.catvod.crawler.SpiderApi
import dalvik.system.DexClassLoader
import fi.iki.elonen.NanoHTTPD
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class TvboxBridge(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(18)
    private val engine = TvboxJarEngine(activity.applicationContext)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
            ?: return result.error("TVBOX_ARGS", "缺少 TVBox 调用参数", null)
        executor.execute {
            try {
                val response = engine.call(arguments)
                if (arguments["action"] == "player") {
                    main.post { finishPlayer(response, result) }
                } else {
                    main.post { result.success(response) }
                }
            } catch (error: Throwable) {
                main.post {
                    result.error("TVBOX_RUNTIME", error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun finishPlayer(response: String, result: MethodChannel.Result) {
        try {
            val json = JSONObject(response)
            var url = firstPlayableUrl(json.opt("url"))
            if (url.isBlank()) throw IllegalStateException("Spider 未返回播放地址")
            val headers = playerHeaders(json)
            if (url.startsWith("video://")) {
                url = url.removePrefix("video://")
                json.put("parse", 1)
            } else if (url.startsWith("proxy://")) {
                url = engine.localUrl(url)
                json.put("parse", 0)
            }
            val parse = json.optString("parse", "1") == "1" || json.optString("jx", "0") == "1"
            val playUrl = json.optString("playUrl") + url
            if (!parse) {
                json.put("url", engine.localPlaybackUrl(playUrl, headers.toMap()))
                result.success(json.toString())
                return
            }
            sniff(url = playUrl, headers = headers, result = result)
        } catch (error: Throwable) {
            result.error("TVBOX_PLAY", error.message ?: "播放地址解析失败", null)
        }
    }

    private fun firstPlayableUrl(value: Any?): String = when (value) {
        is JSONArray -> when {
            value.length() > 1 -> value.optString(1)
            value.length() == 1 -> value.optString(0)
            else -> ""
        }
        is String -> runCatching {
            if (value.trim().startsWith("[")) firstPlayableUrl(JSONArray(value)) else value
        }.getOrDefault(value)
        else -> value?.toString().orEmpty()
    }

    private fun playerHeaders(json: JSONObject): JSONObject {
        val result = JSONObject()
        listOf("header", "headers").forEach { name ->
            val headers = when (val value = json.opt(name)) {
                is JSONObject -> value
                is String -> runCatching { JSONObject(value) }.getOrNull()
                else -> null
            } ?: return@forEach
            headers.keys().forEach { key -> result.put(key, headers.optString(key)) }
        }
        return result
    }

    private fun JSONObject.toMap() = keys().asSequence().associateWith(::optString)

    @SuppressLint("SetJavaScriptEnabled")
    private fun sniff(url: String, headers: JSONObject?, result: MethodChannel.Result) {
        val finished = AtomicBoolean(false)
        val webView = WebView(activity)
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        root.addView(webView, FrameLayout.LayoutParams(1, 1))
        webView.setBackgroundColor(Color.TRANSPARENT)
        webView.alpha = 0.01f
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false

        fun complete(mediaUrl: String?, error: String? = null) {
            if (!finished.compareAndSet(false, true)) return
            root.removeView(webView)
            webView.stopLoading()
            webView.destroy()
            if (mediaUrl != null) {
                result.success(
                    JSONObject()
                        .put("url", engine.localPlaybackUrl(mediaUrl, headers?.toMap().orEmpty()))
                        .put("header", headers ?: JSONObject())
                        .toString(),
                )
            } else {
                result.error("TVBOX_SNIFF", error ?: "未嗅探到视频地址", null)
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): android.webkit.WebResourceResponse? {
                val candidate = request?.url?.toString().orEmpty()
                if (isMediaUrl(candidate)) main.post { complete(candidate) }
                return super.shouldInterceptRequest(view, request)
            }

            override fun onLoadResource(view: WebView?, candidate: String?) {
                if (candidate != null && isMediaUrl(candidate)) complete(candidate)
                super.onLoadResource(view, candidate)
            }
        }
        val headerMap = mutableMapOf<String, String>()
        headers?.keys()?.forEach { key -> headerMap[key] = headers.optString(key) }
        webView.loadUrl(url, headerMap)
        main.postDelayed({ complete(null, "20 秒内未嗅探到视频地址") }, 20_000)
    }

    private fun isMediaUrl(url: String): Boolean {
        val clean = url.substringBefore('?').substringBefore('#').lowercase()
        return clean.endsWith(".m3u8") || clean.endsWith(".mp4") ||
            clean.endsWith(".mkv") || clean.endsWith(".flv") ||
            clean.endsWith(".mpd") || clean.endsWith(".ts")
    }

    fun close() {
        executor.shutdownNow()
        engine.close()
    }
}

private class TvboxJarEngine(private val context: Context) {
    private data class LoadedJar(
        val loader: DexClassLoader,
        val proxy: java.lang.reflect.Method?,
    )

    private val loaded = ConcurrentHashMap<String, LoadedJar>()
    private val spiders = ConcurrentHashMap<String, Spider>()
    private val playbackHeaders = ConcurrentHashMap<String, Map<String, String>>()
    private val protectedInit = ProtectedInitJar(context)
    private val proxyServer = TvboxProxyServer(this).also { it.start() }
    @Volatile private var recentJar = ""
    @Volatile private var recentSpider: Spider? = null

    fun call(arguments: Map<*, *>): String {
        val action = arguments["action"]?.toString().orEmpty()
        val siteKey = arguments["key"]?.toString().orEmpty()
        val api = arguments["api"]?.toString().orEmpty().removePrefix("csp_")
        val ext = arguments["ext"]?.toString().orEmpty()
        val jarUrl = arguments["jarUrl"]?.toString().orEmpty()
        val jarMd5 = arguments["jarMd5"]?.toString().orEmpty()
        require(api.matches(Regex("[A-Za-z0-9_]+"))) { "非法 Spider 类名" }
        require(jarUrl.startsWith("https://") || jarUrl.startsWith("http://")) {
            "Spider/JAR 地址必须是 HTTP(S)"
        }

        val jar = loadJar(jarUrl, jarMd5)
        val spiderKey = "$jarUrl#$siteKey#$api"
        val spider = spiders.computeIfAbsent(spiderKey) {
            val value = jar.loader.loadClass("com.github.catvod.spider.$api")
                .getDeclaredConstructor().newInstance() as Spider
            value.siteKey = siteKey
            value.initApi(SpiderApi(context))
            value.init(context, ext)
            value
        }
        recentJar = jarUrl
        recentSpider = spider

        return when (action) {
            "home" -> spider.homeContent(true)
            "category" -> spider.categoryContent(
                arguments["typeId"]?.toString().orEmpty(),
                arguments["page"]?.toString() ?: "1",
                true,
                hashMapOf(),
            )
            "detail" -> spider.detailContent(listOf(arguments["id"]?.toString().orEmpty()))
            "search" -> spider.searchContent(
                arguments["keyword"]?.toString().orEmpty(),
                false,
                arguments["page"]?.toString() ?: "1",
            )
            "player" -> spider.playerContent(
                arguments["flag"]?.toString().orEmpty(),
                arguments["id"]?.toString().orEmpty(),
                emptyList(),
            )
            else -> throw IllegalArgumentException("未知 Spider 操作：$action")
        }.ifBlank { throw IllegalStateException("Spider 未返回数据") }
    }

    private fun loadJar(url: String, expectedMd5: String): LoadedJar = loaded.computeIfAbsent(url) {
        val directory = File(context.filesDir, "tvbox/jars").also { it.mkdirs() }
        val file = File(directory, sha256(url) + ".jar")
        if (!file.exists() || (expectedMd5.isNotBlank() && md5(file) != expectedMd5.lowercase())) {
            val temporary = File(directory, file.name + ".download")
            download(url, temporary)
            if (expectedMd5.isNotBlank() && md5(temporary) != expectedMd5.lowercase()) {
                temporary.delete()
                throw SecurityException("Spider/JAR MD5 校验失败")
            }
            if (file.exists()) file.delete()
            if (!temporary.renameTo(file)) throw IllegalStateException("无法保存 Spider/JAR")
        }
        check(file.setReadOnly() || !file.canWrite()) { "无法将 Spider/JAR 设为只读" }
        val optimized = File(context.codeCacheDir, "tvbox").also { it.mkdirs() }
        val loader = DexClassLoader(file.absolutePath, optimized.absolutePath, optimized.absolutePath, context.classLoader)
        initialize(loader, file)
        val proxy = runCatching {
            loader.loadClass("com.github.catvod.spider.Proxy").getMethod("proxy", Map::class.java)
        }.getOrNull()
        LoadedJar(loader, proxy)
    }

    private fun initialize(loader: DexClassLoader, file: File) {
        val init = runCatching { loader.loadClass("com.github.catvod.spider.Init") }.getOrNull() ?: return
        if (protectedInit.check(file.absolutePath)) {
            protectedInit.init(init)
        } else {
            runCatching { init.getMethod("init", Context::class.java).invoke(null, context) }
                .getOrElse { throw IllegalStateException("Spider/JAR 初始化失败", it) }
        }
    }

    private fun download(url: String, target: File) {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 20_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("User-Agent", "rplayer-tvbox/1.0")
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Spider/JAR 下载返回 HTTP ${connection.responseCode}")
            }
            connection.inputStream.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
        } finally {
            connection.disconnect()
        }
    }

    fun proxy(params: Map<String, String>): Array<Any?>? {
        val method = loaded[recentJar]?.proxy
        val result = runCatching { method?.invoke(null, params) as? Array<Any?> }.getOrNull()
        return result ?: runCatching { recentSpider?.proxy(params) }.getOrNull()
    }

    fun localUrl(url: String): String = if (url.startsWith("proxy://")) {
        "http://127.0.0.1:${TvboxProxyServer.PORT}/proxy?${url.removePrefix("proxy://")}" 
    } else url

    fun localPlaybackUrl(url: String, headers: Map<String, String>): String {
        val resolved = localUrl(url)
        if (!tvboxIsM3u8Url(resolved) || resolved.startsWith("http://127.0.0.1:${TvboxProxyServer.PORT}/")) {
            return resolved
        }
        val key = sha256(resolved + headers.toSortedMap().entries.joinToString { "${it.key}:${it.value}" })
        playbackHeaders[key] = headers
        return localM3u8Url(resolved, key)
    }

    fun localM3u8Url(url: String, key: String) =
        "http://127.0.0.1:${TvboxProxyServer.PORT}/playlist.m3u8?key=$key&url=${encode(url)}"

    fun localSegmentUrl(url: String, key: String) =
        "http://127.0.0.1:${TvboxProxyServer.PORT}/segment.ts?key=$key&url=${encode(url)}&format=.ts"

    fun playbackHeaders(key: String): Map<String, String> = playbackHeaders[key].orEmpty()

    private fun encode(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name())

    fun close() {
        proxyServer.stop()
        spiders.values.forEach { runCatching { it.destroy() } }
        spiders.clear()
        loaded.clear()
        playbackHeaders.clear()
        protectedInit.clear()
    }

    private fun md5(file: File) = digest("MD5", file.readBytes())
    private fun sha256(value: String) = digest("SHA-256", value.toByteArray())
    private fun digest(algorithm: String, bytes: ByteArray) =
        MessageDigest.getInstance(algorithm).digest(bytes).joinToString("") { "%02x".format(it) }
}

private class TvboxProxyServer(private val engine: TvboxJarEngine) : NanoHTTPD(PORT) {
    companion object { const val PORT = 9978 }

    private data class Download(val status: Int, val mime: String, val bytes: ByteArray)
    private val http = OkHttpClient()

    override fun serve(session: IHTTPSession): Response {
        if (session.uri == "/playlist.m3u8") return serveM3u8(session)
        if (session.uri == "/segment.ts") return serveSegment(session)
        if (session.uri != "/proxy" && session.uri != "/") {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "404")
        }
        val params = HashMap(session.parms)
        params.putAll(session.headers)
        val values = engine.proxy(params)
            ?: return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "proxy failed")
        if (values.firstOrNull() is Response) return values[0] as Response
        val status = (values.getOrNull(0) as? Number)?.toInt() ?: 200
        val mime = values.getOrNull(1)?.toString() ?: "application/octet-stream"
        val body = when (val value = values.getOrNull(2)) {
            is InputStream -> value
            is ByteArray -> ByteArrayInputStream(value)
            null -> ByteArrayInputStream(ByteArray(0))
            else -> ByteArrayInputStream(value.toString().toByteArray())
        }
        return newChunkedResponse(Response.Status.lookup(status), mime, body).also { response ->
            @Suppress("UNCHECKED_CAST")
            (values.getOrNull(3) as? Map<String, String>)?.forEach(response::addHeader)
        }
    }

    private fun serveM3u8(session: IHTTPSession): Response = runCatching {
        val url = session.parms["url"].orEmpty()
        val key = session.parms["key"].orEmpty()
        require(url.startsWith("http://") || url.startsWith("https://")) { "invalid m3u8 url" }
        val download = download(url, engine.playbackHeaders(key))
        if (download.status !in 200..299) return@runCatching response(download)
        newFixedLengthResponse(
            Response.Status.OK,
            "application/vnd.apple.mpegurl",
            rewriteM3u8(url, download.bytes.toString(Charsets.UTF_8), key),
        )
    }.getOrElse {
        newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, it.message)
    }

    private fun serveSegment(session: IHTTPSession): Response = runCatching {
        val url = session.parms["url"].orEmpty()
        val key = session.parms["key"].orEmpty()
        require(url.startsWith("http://") || url.startsWith("https://")) { "invalid segment url" }
        val download = download(url, engine.playbackHeaders(key))
        if (download.status !in 200..299) return@runCatching response(download)
        val payload = tvboxMpegTsPayload(download.bytes)
        val mime = if (payload !== download.bytes) "video/mp2t" else download.mime
        newFixedLengthResponse(
            Response.Status.OK,
            mime,
            ByteArrayInputStream(payload),
            payload.size.toLong(),
        )
    }.getOrElse {
        newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, it.message)
    }

    private fun rewriteM3u8(sourceUrl: String, content: String, key: String): String {
        val base = URL(sourceUrl)
        val uri = Regex("""URI="([^"]+)"""")
        fun rewrite(value: String, mediaSegment: Boolean = false): String {
            val absolute = URL(base, value).toString()
            val path = URL(absolute).path.lowercase()
            return when {
                path.endsWith(".m3u8") -> engine.localM3u8Url(absolute, key)
                mediaSegment || path.endsWith(".png") || path.endsWith(".jpg") || path.endsWith(".jpeg") ||
                    path.endsWith(".gif") || path.endsWith(".webp") -> engine.localSegmentUrl(absolute, key)
                else -> absolute
            }
        }
        return content.lineSequence().joinToString("\n") { line ->
            when {
                line.isBlank() -> line
                line.startsWith("#") -> uri.replace(line) { match ->
                    "URI=\"${rewrite(match.groupValues[1])}\""
                }
                else -> rewrite(line.trim(), mediaSegment = true)
            }
        }
    }

    private fun download(url: String, headers: Map<String, String>): Download {
        val request = Request.Builder().url(url).also { builder ->
            headers.forEach(builder::header)
        }.build()
        return http.newCall(request).execute().use { response ->
            Download(
                response.code,
                response.header("Content-Type") ?: "application/octet-stream",
                response.body?.bytes() ?: ByteArray(0),
            )
        }
    }

    private fun response(download: Download) = newFixedLengthResponse(
        Response.Status.lookup(download.status),
        download.mime,
        ByteArrayInputStream(download.bytes),
        download.bytes.size.toLong(),
    )
}

internal fun tvboxIsM3u8Url(url: String) = runCatching {
    val parsed = URL(url)
    val lower = parsed.toString().lowercase()
    lower.contains("getm3u8") || parsed.path.lowercase().endsWith(".m3u8")
}.getOrDefault(false)

internal fun tvboxMpegTsPayload(bytes: ByteArray): ByteArray {
    val limit = minOf(4096, bytes.size - 376)
    for (offset in 0 until limit) {
        if (bytes[offset] == 0x47.toByte() &&
            bytes[offset + 188] == 0x47.toByte() &&
            bytes[offset + 376] == 0x47.toByte()
        ) {
            return if (offset == 0) bytes else bytes.copyOfRange(offset, bytes.size)
        }
    }
    return bytes
}
