package com.vyra.kids.core

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Thread-safe local cache manager that maintains a rolling history of captured
 * chats, call records, and notifications on the child device.
 * Used to instantly serve full history to the Parent App over Same-Wi-Fi Direct LAN Sync
 * without needing an active internet connection or consuming cloud quotas.
 */
class LocalDataManager private constructor(private val context: Context) {

    private val gson = Gson()
    private val vaultDir: File by lazy {
        File(context.filesDir, "local_vault").apply {
            if (!exists()) mkdirs()
        }
    }

    private val chatsFile by lazy { File(vaultDir, "chats.json") }
    private val callsFile by lazy { File(vaultDir, "calls.json") }
    private val notifsFile by lazy { File(vaultDir, "notifications.json") }
    private val statusFile by lazy { File(vaultDir, "status.json") }

    private val MAX_ITEMS = 1500

    companion object {
        @Volatile
        private var instance: LocalDataManager? = null

        fun getInstance(context: Context): LocalDataManager {
            return instance ?: synchronized(this) {
                instance ?: LocalDataManager(context.applicationContext).also { instance = it }
            }
        }
    }

    @Synchronized
    fun saveStatus(statusData: Map<String, Any>) {
        try {
            statusFile.writeText(gson.toJson(statusData))
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error saving local status", e)
        }
    }

    @Synchronized
    fun getStatus(): Map<String, Any> {
        return try {
            if (!statusFile.exists()) return emptyMap()
            val type = object : TypeToken<Map<String, Any>>() {}.type
            gson.fromJson(statusFile.readText(), type) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    @Synchronized
    fun saveChat(chatItem: Map<String, Any>) {
        appendRollingItem(chatsFile, chatItem, "id")
    }

    @Synchronized
    fun getChats(): List<Map<String, Any>> {
        return readItems(chatsFile)
    }

    @Synchronized
    fun saveCall(callItem: Map<String, Any>) {
        appendRollingItem(callsFile, callItem, "id")
    }

    @Synchronized
    fun getCalls(): List<Map<String, Any>> {
        return readItems(callsFile)
    }

    @Synchronized
    fun saveNotification(notifItem: Map<String, Any>) {
        appendRollingItem(notifsFile, notifItem, "id")
    }

    @Synchronized
    fun getNotifications(): List<Map<String, Any>> {
        return readItems(notifsFile)
    }

    @Synchronized
    fun getAllData(): Map<String, Any> {
        return mapOf(
            "status" to getStatus(),
            "chats" to getChats(),
            "calls" to getCalls(),
            "notifications" to getNotifications(),
            "exportedAt" to System.currentTimeMillis()
        )
    }

    private fun appendRollingItem(targetFile: File, item: Map<String, Any>, keyField: String) {
        try {
            val list: MutableList<Map<String, Any>> = if (targetFile.exists()) {
                val type = object : TypeToken<MutableList<Map<String, Any>>>() {}.type
                gson.fromJson(targetFile.readText(), type) ?: mutableListOf()
            } else {
                mutableListOf()
            }

            val targetId = item[keyField]?.toString()
            if (!targetId.isNullOrEmpty()) {
                list.removeAll { it[keyField]?.toString() == targetId }
            }

            // Insert newest at top
            list.add(0, item)

            // Trim to MAX_ITEMS
            if (list.size > MAX_ITEMS) {
                list.subList(MAX_ITEMS, list.size).clear()
            }

            targetFile.writeText(gson.toJson(list))
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error appending to local vault file ${targetFile.name}", e)
        }
    }

    private fun readItems(targetFile: File): List<Map<String, Any>> {
        return try {
            if (!targetFile.exists()) return emptyList()
            val type = object : TypeToken<List<Map<String, Any>>>() {}.type
            gson.fromJson(targetFile.readText(), type) ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }
}
