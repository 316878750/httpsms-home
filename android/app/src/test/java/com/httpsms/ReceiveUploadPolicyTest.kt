package com.httpsms

import org.junit.Assert.*
import org.junit.Test

class ReceiveUploadPolicyTest {
    @Test fun retainsUnacknowledgedUploads() {
        for (status in listOf(202, 204, 301, 400, 401, 403, 408, 422, 429, 500, 503)) {
            assertFalse("status $status must not discard the SMS", ReceiveUploadPolicy.acknowledged(status, true))
        }
        assertFalse(ReceiveUploadPolicy.acknowledged(200, false))
        assertTrue(ReceiveUploadPolicy.acknowledged(200, true))
    }
}
