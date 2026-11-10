package com.example.netmap

import android.Manifest
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.ConnectException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val workers = Executors.newFixedThreadPool(16)
    private var pending: MethodChannel.Result? = null
    private val manager get() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
    private val localPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    private val ports = listOf(22, 80, 443, 445, 554, 631, 8008, 8080, 9100)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netmap/network").setMethodCallHandler { call, result ->
            when (call.method) {
                "network" -> {
                    if (Build.VERSION.SDK_INT >= 37 && applicationInfo.targetSdkVersion >= 37 &&
                        checkSelfPermission(localPermission) != PackageManager.PERMISSION_GRANTED) {
                        if (pending != null) result.error("BUSY", "A permission request is already pending.", null)
                        else { pending = result; requestPermissions(arrayOf(localPermission), 1001) }
                    } else getNetwork(result)
                }
                "probe" -> {
                    val id = call.argument<String>("id")
                    val ip = call.argument<String>("ip")
                    if (id == null || ip == null) { result.error("ARGS", "Missing network or IP address.", null); return@setMethodCallHandler }
                    workers.execute {
                        try {
                            val network = manager.allNetworks.firstOrNull { it.toString() == id }
                                ?: throw IllegalStateException("Wi-Fi disconnected. Reconnect and scan again.")
                            // Always create sockets on the chosen Wi-Fi network, even when
                            // mobile data is the system's preferred Internet connection.
                            val properties = manager.getLinkProperties(network)
                                ?: throw IllegalStateException("Wi-Fi disconnected.")
                            val address = java.net.InetAddress.getByName(ip)
                            if (address !is Inet4Address || properties.linkAddresses.none {
                                    it.address is Inet4Address && sameSubnet(it.address.address, address.address, it.prefixLength)
                                }) throw IllegalArgumentException("Address is outside the Wi-Fi subnet.")
                            var reachable = false
                            val open = mutableListOf<Int>()
                            for (port in ports) {
                                try {
                                    network.socketFactory.createSocket().use { socket ->
                                        socket.connect(InetSocketAddress(address, port), 350)
                                        reachable = true
                                        open.add(port)
                                    }
                                } catch (e: ConnectException) {
                                    // Explicit refusal is evidence of an answering IP stack.
                                    if (e.cause is android.system.ErrnoException &&
                                        (e.cause as android.system.ErrnoException).errno == android.system.OsConstants.ECONNREFUSED ||
                                        e.message?.contains("ECONNREFUSED") == true) reachable = true
                                } catch (e: SecurityException) { throw e
                                } catch (_: java.io.IOException) { /* timeout / unreachable */ }
                            }
                            if (manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true)
                                throw IllegalStateException("Wi-Fi disconnected. Reconnect and scan again.")
                            runOnUiThread { result.success(mapOf("reachable" to reachable, "ports" to open)) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PROBE", e.message ?: "Network probe failed.", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sameSubnet(a: ByteArray, b: ByteArray, prefix: Int): Boolean {
        for (i in 0 until prefix) {
            val mask = 1 shl (7 - i % 8)
            if ((a[i / 8].toInt() and mask) != (b[i / 8].toInt() and mask)) return false
        }
        return true
    }

    private fun getNetwork(result: MethodChannel.Result) {
        try {
            val wifi = manager.allNetworks.firstOrNull {
                manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            } ?: throw IllegalStateException("Connect to a Wi-Fi network before scanning.")
            val properties = manager.getLinkProperties(wifi)
                ?: throw IllegalStateException("Wi-Fi details are unavailable.")
            val ipv4 = properties.linkAddresses.firstOrNull { it.address is Inet4Address }
                ?: throw IllegalStateException("This version requires a Wi-Fi network with IPv4.")
            val gateway = properties.routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress
            result.success(mapOf("ip" to ipv4.address.hostAddress, "prefix" to ipv4.prefixLength,
                "gateway" to gateway, "id" to wifi.toString()))
        } catch (e: Exception) { result.error("WIFI", e.message, null) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val result = pending ?: return
            pending = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) getNetwork(result)
            else result.error("PERMISSION", "Allow nearby/local network access in Android settings, then retry.", null)
        }
    }

    override fun onDestroy() { workers.shutdownNow(); super.onDestroy() }
}
