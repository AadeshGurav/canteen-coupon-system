package com.canteen.canteen_coupon

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Adds a `tiffin/hotspot` MethodChannel so the app can run its own Wi-Fi with
 * no router — for canteens with no usable Wi-Fi. Uses [WifiManager.startLocalOnlyHotspot],
 * the only AP API open to non-system apps (API 26+). The host then sits at the
 * fixed local-only-hotspot gateway `192.168.49.1`.
 *
 * iOS has no equivalent; the Dart side treats a MissingPluginException /
 * `isSupported == false` as "not available".
 */
class MainActivity : FlutterActivity() {

    private val channelName = "tiffin/hotspot"
    private val permRequestCode = 4711

    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    "start" -> startHotspot(result)
                    "stop" -> stopHotspot(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requiredPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.NEARBY_WIFI_DEVICES
        else
            Manifest.permission.ACCESS_FINE_LOCATION

    private fun startHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "Needs Android 8.0 or newer.", null); return
        }
        reservation?.let { emitReservation(it, result); return }

        val perm = requiredPermission()
        if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
            pendingResult = result
            ActivityCompat.requestPermissions(this, arrayOf(perm), permRequestCode)
            return
        }
        launchLocalOnlyHotspot(result)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun launchLocalOnlyHotspot(result: MethodChannel.Result) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = res
                    emitReservation(res, result)
                }

                override fun onFailed(reason: Int) {
                    reservation = null
                    result.error("failed", "Couldn't start the hotspot (code $reason). " +
                        "Turn Wi-Fi off and retry, or check no other app is sharing a connection.", null)
                }

                override fun onStopped() {
                    reservation = null
                }
            }, null)
        } catch (e: Throwable) {
            result.error("failed", e.message ?: "Hotspot start threw.", null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun emitReservation(res: WifiManager.LocalOnlyHotspotReservation, result: MethodChannel.Result) {
        val ssid: String?
        val pass: String?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cfg = res.softApConfiguration
            @Suppress("DEPRECATION")
            ssid = cfg.ssid
            pass = cfg.passphrase
        } else {
            @Suppress("DEPRECATION")
            val cfg = res.wifiConfiguration
            @Suppress("DEPRECATION")
            ssid = cfg?.SSID?.trim('"')
            @Suppress("DEPRECATION")
            pass = cfg?.preSharedKey?.trim('"')
        }
        result.success(mapOf("ssid" to (ssid ?: ""), "passphrase" to (pass ?: ""), "host" to "192.168.49.1"))
    }

    private fun stopHotspot(result: MethodChannel.Result) {
        reservation?.close()
        reservation = null
        result.success(true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permRequestCode) return
        val res = pendingResult ?: return
        pendingResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) launchLocalOnlyHotspot(res)
            else res.error("unsupported", "Needs Android 8.0 or newer.", null)
        } else {
            res.error("permission", "Nearby-devices permission is needed to create a hotspot.", null)
        }
    }

    override fun onDestroy() {
        reservation?.close()
        reservation = null
        super.onDestroy()
    }
}
