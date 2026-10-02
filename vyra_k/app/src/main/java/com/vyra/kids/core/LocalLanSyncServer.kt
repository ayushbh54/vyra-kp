package com.vyra.kids.core

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.*
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.*

/**
 * Lightweight, zero-dependency Local LAN Sync Server and UDP Broadcaster.
 * Enables zero-quota, high-speed direct peer-to-peer data syncing whenever
 * Parent and Child devices are connected to the same Wi-Fi network.
 */
class LocalLanSyncServer private constructor(private val context: Context) {

    private val gson = Gson()
    private var isRunning = false
    private var serverSocket: ServerSocket? = null
    private var udpSocket: DatagramSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        const val HTTP_PORT = 8899
        const val UDP_DISCOVERY_PORT = 8898

        @Volatile
        private var instance: LocalLanSyncServer? = null

        fun getInstance(context: Context): LocalLanSyncServer {
            return instance ?: synchronized(this) {
                instance ?: LocalLanSyncServer(context.applicationContext).also { instance = it }
            }
        }
    }

    private val pairingCode: String
        get() = PrefsManager.getInstance(context).pairingCode.ifEmpty { "VYRA-13533" }

    @Synchronized
    fun start() {
        if (isRunning) return
        isRunning = true
        Log.i(AppConstants.TAG, "Starting Local LAN Sync Server on port $HTTP_PORT...")

        scope.launch { startHttpServer() }
        scope.launch { startUdpDiscoveryListener() }
    }

    @Synchronized
    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
            udpSocket?.close()
        } catch (_: Exception) {}
        scope.cancel()
        Log.i(AppConstants.TAG, "Stopped Local LAN Sync Server")
    }

    private fun startHttpServer() {
        try {
            serverSocket = ServerSocket(HTTP_PORT)
            while (isRunning) {
                try {
                    val client = serverSocket?.accept() ?: continue
                    scope.launch { handleClientRequest(client) }
                } catch (e: Exception) {
                    if (!isRunning) break
                }
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in HTTP LAN Server", e)
        }
    }

    private fun handleClientRequest(client: Socket) {
        try {
            client.soTimeout = 10000
            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
            val firstLine = reader.readLine() ?: return
            val parts = firstLine.split(" ")
            if (parts.size < 2) return

            val method = parts[0]
            val uri = parts[1]

            val localData = LocalDataManager.getInstance(context)
            val responseBody: String
            val statusCode: Int

            when {
                uri.startsWith("/api/ping") -> {
                    statusCode = 200
                    responseBody = gson.toJson(mapOf("status" to "ok", "code" to pairingCode, "device" to android.os.Build.MODEL))
                }
                uri.startsWith("/api/sync") -> {
                    statusCode = 200
                    responseBody = gson.toJson(localData.getAllData())
                }
                uri.startsWith("/api/status") -> {
                    statusCode = 200
                    responseBody = gson.toJson(localData.getStatus())
                }
                uri.startsWith("/api/chats") -> {
                    statusCode = 200
                    responseBody = gson.toJson(localData.getChats())
                }
                uri.startsWith("/api/calls") -> {
                    statusCode = 200
                    responseBody = gson.toJson(localData.getCalls())
                }
                uri.startsWith("/api/notifications") -> {
                    statusCode = 200
                    responseBody = gson.toJson(localData.getNotifications())
                }
                else -> {
                    statusCode = 404
                    responseBody = "{\"error\":\"Not Found\"}"
                }
            }

            val bodyBytes = responseBody.toByteArray(Charsets.UTF_8)
            val os: OutputStream = client.getOutputStream()
            val header = "HTTP/1.1 $statusCode OK\r\n" +
                    "Content-Type: application/json; charset=utf-8\r\n" +
                    "Content-Length: ${bodyBytes.size}\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Connection: close\r\n\r\n"

            os.write(header.toByteArray(Charsets.UTF_8))
            os.write(bodyBytes)
            os.flush()
            client.close()
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "LAN client handle error", e)
        }
    }

    private fun startUdpDiscoveryListener() {
        try {
            udpSocket = DatagramSocket(UDP_DISCOVERY_PORT)
            val buffer = ByteArray(1024)

            while (isRunning) {
                val packet = DatagramPacket(buffer, buffer.size)
                udpSocket?.receive(packet)

                val message = String(packet.data, 0, packet.length).trim()
                if (message.contains("VYRA_DISCOVER") || message.contains(pairingCode)) {
                    val localIp = getLocalIpAddress()
                    val reply = gson.toJson(mapOf(
                        "type" to "VYRA_ANNOUNCE",
                        "code" to pairingCode,
                        "ip" to localIp,
                        "port" to HTTP_PORT,
                        "model" to android.os.Build.MODEL
                    ))
                    val replyBytes = reply.toByteArray(Charsets.UTF_8)
                    val responsePacket = DatagramPacket(
                        replyBytes,
                        replyBytes.size,
                        packet.address,
                        packet.port
                    )
                    udpSocket?.send(responsePacket)
                    Log.d(AppConstants.TAG, "Responded to LAN discovery probe from ${packet.address.hostAddress}")
                }
            }
        } catch (e: Exception) {
            if (isRunning) {
                Log.e(AppConstants.TAG, "Error in UDP discovery listener", e)
            }
        }
    }

    fun getLocalIpAddress(): String {
        try {
            val interfaces = java.util.Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                val addrs = java.util.Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return addr.hostAddress ?: "127.0.0.1"
                    }
                }
            }
        } catch (_: Exception) {}
        return "127.0.0.1"
    }
}
