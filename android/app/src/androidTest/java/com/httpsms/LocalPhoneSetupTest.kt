package com.httpsms

import androidx.preference.PreferenceManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.gms.tasks.Tasks
import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.URI
import java.util.concurrent.TimeUnit

/** Explicit USB provisioning only. Input is private, unbundled, and deleted after use. */
@RunWith(AndroidJUnit4::class)
class LocalPhoneSetupTest {
    @Test fun provisionLocalPhone() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("configureLocalPhone") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val input = File(context.filesDir, "local-phone-setup.json")
        assertTrue("Private provisioning input is missing", input.isFile)
        try {
            val config = try { JSONObject(input.readText()) } catch (_: Exception) {
                throw AssertionError("Invalid private provisioning input")
            }
            val server = config.getString("server")
            assertTrue("Unexpected server", server == context.getString(R.string.default_server_url).trimEnd('/'))
            val number = config.getString("phone")
            assertTrue("Invalid number format", number.matches(Regex("\\+[1-9][0-9]{6,14}")))
            val token = try {
                Tasks.await(FirebaseMessaging.getInstance().token, 30, TimeUnit.SECONDS)
            } catch (_: Exception) { null }
            assertTrue("FCM token unavailable; check Google services connectivity", !token.isNullOrBlank())
            val result = HttpSmsApiService(config.getString("api_key"), URI(server))
                .updateFcmToken(number, Constants.SIM1, token!!)
            assertTrue("Phone registration failed", result.first != null && result.second == null && result.third == null)
            assertTrue("Account mismatch", result.first!!.userID == config.getString("user_id"))
            val saved = PreferenceManager.getDefaultSharedPreferences(context).edit()
                .putString("SETTINGS_API_KEY", config.getString("api_key"))
                .putString("SETTINGS_SERVER_URL", server)
                .putString("SETTINGS_USER_ID", result.first!!.userID)
                .putString("SETTINGS_FCM_TOKEN", token)
                .putString("SETTINGS_SIM1_PHONE_NUMBER", number)
                .remove("SETTINGS_SIM2_PHONE_NUMBER")
                .putBoolean("SETTINGS_SIM1_ACTIVE_STATUS", true)
                .putBoolean("SETTINGS_SIM1_INCOMING_ACTIVE", true)
                .putBoolean("SETTINGS_SIM2_ACTIVE_STATUS", false)
                .putBoolean("SETTINGS_SIM2_INCOMING_ACTIVE", false)
                .putBoolean("SETTINGS_SIM1_INCOMING_CALL_ACTIVE", false)
                .putBoolean("SETTINGS_SIM2_INCOMING_CALL_ACTIVE", false)
                .putBoolean("SETTINGS_DEBUG_LOG_ENABLED", false)
                .commit()
            assertTrue("Could not persist phone configuration", saved && Settings.isLoggedIn(context))
        } finally {
            assertTrue("Could not remove provisioning input", !input.exists() || input.delete())
        }
    }
}
