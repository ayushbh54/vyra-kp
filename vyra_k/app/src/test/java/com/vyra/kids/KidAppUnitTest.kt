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
        assertEquals("com.vyra.kids.AliasSimToolkit", DisguiseProfile.SIM_TOOLKIT.aliasClass)
        assertEquals("", DisguiseProfile.GHOST_HIDDEN.aliasClass)
    }
}
