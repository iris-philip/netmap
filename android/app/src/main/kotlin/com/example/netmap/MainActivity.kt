package com.example.netmap

import android.Manifest
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
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
    private var csvResult: MethodChannel.Result? = null
    private var csvContents: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val manager get() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
    private val localPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    private val ports = listOf(22, 80, 443, 445, 554, 631, 8008, 8080, 9100)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netmap/network").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveCsv" -> {
                    if (csvResult != null) {
                        result.error("BUSY", "A save dialog is already open.", null)
                    } else {
                        csvResult = result
                        csvContents = call.argument<String>("contents") ?: ""
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "text/csv"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "NetMap.csv")
                            }, 1002)
                        } catch (e: Exception) {
                            csvResult = null; csvContents = null
                            result.error("SAVE", "Could not open the file picker.", null)
                        }
                    }
                }
                "openChrome" -> {
                    val ip = call.argument<String>("ip")
                    val parts = ip?.split('.')
                    if (parts == null || parts.size != 4 || parts.any {
                        it.isEmpty() || it.any { c -> c !in '0'..'9' } ||
                            (it.toIntOrNull() ?: -1) !in 0..255
                    }) {
                        result.error("ARGS", "Invalid device IP address.", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://$ip"))
                                .setPackage("com.android.chrome"))
                            result.success(null)
                        } catch (_: ActivityNotFoundException) {
                            result.error("CHROME", "Chrome is not installed or enabled on this phone.", null)
                        } catch (_: SecurityException) {
                            result.error("CHROME", "Android could not open Chrome.", null)
                        }
                    }
                }
                "network" -> {
                    if (Build.VERSION.SDK_INT >= 37 && applicationInfo.targetSdkVersion >= 37 &&
                        checkSelfPermission(localPermission) != PackageManager.PERMISSION_GRANTED) {
                        if (pending != null) result.error("BUSY", "A permission request is already pending.", null)
                        else { pending = result; requestPermissions(arrayOf(localPermission), 1001) }
                    } else getNetwork(result)
                }
                "acquireMdnsMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld != true) {
                            val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                            multicastLock = wifiManager.createMulticastLock("netmap-mdns").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    } catch (e: SecurityException) {
                        result.error("MDNS", "Could not enable Wi-Fi multicast for device-name lookup.", null)
                    }
                }
                "releaseMdnsMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1002) return
        val result = csvResult ?: return
        val contents = csvContents ?: ""
        csvResult = null; csvContents = null
        if (resultCode != android.app.Activity.RESULT_OK) { result.success(null); return }
        val uri = data?.data
        if (uri == null) { result.error("SAVE", "No file selected.", null); return }
        try {
            val stream = contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Cannot write the selected file.")
            stream.use { it.write(contents.toByteArray(Charsets.UTF_8)) }
            result.success("selected file")
        } catch (e: Exception) { result.error("SAVE", "Could not save the CSV file.", null) }
    }
    private fun releaseMulticastLock() {
        multicastLock?.let {
            if (it.isHeld) it.release()
        }
        multicastLock = null
    }

    override fun onDestroy() {
        workers.shutdownNow()
        releaseMulticastLock()
        super.onDestroy()
    }
}
