package com.vyra.kids.core

import java.util.concurrent.atomic.AtomicReference

/**
 * Thread-safe singleton ring buffer for the latest JPEG frame captured by Camera2.
 * LocalLanSyncServer reads from this to serve MJPEG / single-frame endpoints.
 */
object CameraFrameBuffer {
    private val frameRef = AtomicReference<ByteArray?>(null)

    @Volatile
    var isActive: Boolean = false

    @Volatile
    var lastFrameTimestampMs: Long = 0L

    fun putFrame(jpegBytes: ByteArray) {
        frameRef.set(jpegBytes)
        lastFrameTimestampMs = System.currentTimeMillis()
    }

    fun getFrame(): ByteArray? = frameRef.get()

    fun clear() {
        frameRef.set(null)
        lastFrameTimestampMs = 0L
    }
}
