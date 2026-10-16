package com.vyra.kids.core

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Thread-safe PCM audio chunk queue.
 * LiveAudioStreamService produces chunks; LocalLanSyncServer consumes them for live WAV streaming.
 */
object AudioChunkBuffer {
    // Max ~3 seconds of 16kHz mono PCM at 4096-byte chunks = ~12 chunks/sec → 36 max
    private val queue = LinkedBlockingQueue<ByteArray>(50)

    @Volatile
    var isActive: Boolean = false

    fun offer(chunk: ByteArray) {
        // Drop oldest chunk if buffer is full to avoid lag accumulation
        if (queue.size >= 48) queue.poll()
        queue.offer(chunk.copyOf())
    }

    /** Blocks up to [timeoutMs] waiting for the next PCM chunk, returns null on timeout. */
    fun poll(timeoutMs: Long = 200L): ByteArray? =
        queue.poll(timeoutMs, TimeUnit.MILLISECONDS)

    fun clear() = queue.clear()
}
