package com.example.player_flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertSame
import org.junit.Test

class TvboxBridgeTest {
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
