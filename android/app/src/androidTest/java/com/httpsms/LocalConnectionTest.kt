package com.httpsms

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

/** Opt-in device check: no credentials, SMS reads, or SMS sends. */
@RunWith(AndroidJUnit4::class)
class LocalConnectionTest {
    @Test fun localHttpsRequiresAuthentication() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val base = context.getString(R.string.default_server_url).trimEnd('/')
        val client = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build()
        val request = Request.Builder().url("$base/v1/heartbeats")
            .post("{}".toRequestBody("application/json".toMediaType())).build()
        client.newCall(request).execute().use { response ->
            assertEquals("HTTPS upload route requires authentication", 401, response.code)
        }
    }

    @Test fun configuredPhoneCanSendHeartbeat() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("checkConfiguredPhone") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        org.junit.Assert.assertTrue("Phone is not configured", Settings.isLoggedIn(context))
        org.junit.Assert.assertTrue("Heartbeat failed", HttpSmsApiService.create(context).storeHeartbeat(
            arrayOf(Settings.getSIM1PhoneNumber(context)), Settings.isCharging(context)))
        Settings.setHeartbeatTimestampAsync(context, System.currentTimeMillis())
    }
}
