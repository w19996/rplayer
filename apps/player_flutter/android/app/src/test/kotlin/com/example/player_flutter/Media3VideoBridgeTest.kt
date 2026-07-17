package com.example.player_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class Media3VideoBridgeTest {
    @Test
    fun decodesBilibiliMcdnIpHostnames() {
        assertEquals(
            "36.131.78.154",
            media3McdnIp("xy36x131x78x154xy.mcdn.bilivideo.cn"),
        )
        assertNull(media3McdnIp("xy999x131x78x154xy.mcdn.bilivideo.cn"))
        assertNull(media3McdnIp("example.com"))
    }
}
