package com.example.player_flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class TvboxBridgeTest {
    @Test
    fun deletesTvboxCacheDirectory() {
        val directory = Files.createTempDirectory("tvbox-cache-test").toFile()
        directory.resolve("nested/spider.jar").also {
            it.parentFile.mkdirs()
            it.writeText("jar")
        }

        tvboxDeleteDirectory(directory)

        assertFalse(directory.exists())
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
