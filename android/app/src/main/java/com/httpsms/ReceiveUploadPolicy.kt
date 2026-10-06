package com.httpsms

/** Only a committed, parsed API acknowledgement may remove an upload task. */
object ReceiveUploadPolicy {
    fun acknowledged(status: Int, validPayload: Boolean): Boolean = status == 200 && validPayload
}
