package com.vyra.kids.core

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract
import android.util.Log

data class ResolvedContact(
    val name: String,
    val photoUri: String? = null,
    val isSavedInPhone: Boolean = false
)

object ContactResolver {

    /**
     * Resolves a phone number or sender ID against the device's ContactsContract.
     * Returns the exact saved name (e.g. "Chacha Ji", "Rohan Class") and photo URI.
     */
    fun resolve(context: Context, rawSender: String): ResolvedContact {
        if (rawSender.isBlank()) return ResolvedContact(name = "Unknown")

        // If it already looks like a contact name rather than a raw phone number, return it
        val digitsOnly = rawSender.filter { it.isDigit() }
        if (digitsOnly.length < 5) {
            return ResolvedContact(name = rawSender, isSavedInPhone = true)
        }

        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(rawSender))
            val projection = arrayOf(
                ContactsContract.PhoneLookup.DISPLAY_NAME,
                ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI
            )

            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    val photoIndex = cursor.getColumnIndex(ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI)

                    val savedName = if (nameIndex >= 0) cursor.getString(nameIndex) else rawSender
                    val photoUri = if (photoIndex >= 0) cursor.getString(photoIndex) else null

                    ResolvedContact(
                        name = savedName.ifBlank { rawSender },
                        photoUri = photoUri,
                        isSavedInPhone = true
                    )
                } else {
                    ResolvedContact(name = rawSender, isSavedInPhone = false)
                }
            } ?: ResolvedContact(name = rawSender, isSavedInPhone = false)
        } catch (e: SecurityException) {
            Log.w(AppConstants.TAG, "READ_CONTACTS permission not granted yet", e)
            ResolvedContact(name = rawSender, isSavedInPhone = false)
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error resolving contact for $rawSender", e)
            ResolvedContact(name = rawSender, isSavedInPhone = false)
        }
    }
}
