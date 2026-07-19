package com.example.player_flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class TvboxBridgeTest {
    @Test
    fun injectsTvboxProxyPort() {
        com.github.catvod.Proxy.set(12345)

        assertEquals(12345, com.github.catvod.Proxy.getPort())
        assertEquals("http://127.0.0.1:12345/proxy", com.github.catvod.Proxy.getUrl(true))
    }

    @Test
    fun deletesOnlySelectedTvboxJars() {
        val directory = Files.createTempDirectory("tvbox-jar-test").toFile()
        val removed = directory.resolve(tvboxJarCacheName("https://example.com/a.jar"))
            .also { it.writeText("a") }
        val retained = directory.resolve(tvboxJarCacheName("https://example.com/b.jar"))
            .also { it.writeText("b") }

        tvboxDeleteJars(directory, listOf("https://example.com/a.jar"))

        assertFalse(removed.exists())
        assertTrue(retained.exists())
        directory.deleteRecursively()
    }

    @Test
    fun detectsM3u8UrlsWithoutM3u8Suffix() {
        assertTrue(tvboxIsM3u8Url("https://api.example/getm3u8?vid=1"))
        assertTrue(tvboxIsM3u8Url("https://cdn.example/video.m3u8?token=1"))
        assertFalse(tvboxIsM3u8Url("https://cdn.example/video.mp4"))
    }

    @Test
    fun stripsImageWrapperBeforeMpegTsPayload() {
        val bytes = ByteArray(68 + 188 * 3)
        bytes[0] = 0x89.toByte()
        bytes[1] = 0x50
        bytes[68] = 0x47
        bytes[68 + 188] = 0x47
        bytes[68 + 376] = 0x47

        assertArrayEquals(bytes.copyOfRange(68, bytes.size), tvboxMpegTsPayload(bytes))
    }

    @Test
    fun leavesNormalMpegTsPayloadUntouched() {
        val bytes = ByteArray(188 * 3)
        bytes[0] = 0x47
        bytes[188] = 0x47
        bytes[376] = 0x47

        assertSame(bytes, tvboxMpegTsPayload(bytes))
    }
}
