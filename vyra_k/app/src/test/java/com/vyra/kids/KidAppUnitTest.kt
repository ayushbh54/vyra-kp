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
        assertTrue(profiles.contains(DisguiseProfile.SIM_TOOLKIT))
        assertTrue(profiles.contains(DisguiseProfile.CALCULATOR))
        assertTrue(profiles.contains(DisguiseProfile.NOTES))
        assertTrue(profiles.contains(DisguiseProfile.DEVICE_SUPPORT))
        assertTrue(profiles.contains(DisguiseProfile.GHOST_HIDDEN))

        assertEquals("System Toolkit", DisguiseProfile.SIM_TOOLKIT.title)
        assertEquals("com.vyra.kids.AliasSimToolkit", DisguiseProfile.SIM_TOOLKIT.aliasClass)
        assertEquals("", DisguiseProfile.GHOST_HIDDEN.aliasClass)
    }
}
