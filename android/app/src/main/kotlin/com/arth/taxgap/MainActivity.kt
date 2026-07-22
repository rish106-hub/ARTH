package com.arth.taxgap

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.appdistribution.FirebaseAppDistribution
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.arth.taxgap/app_updates"
    private val notificationPermissionRequest = 4102
    private var pendingUpdateResult: MethodChannel.Result? = null

    override fun getInitialRoute(): String? {
        return intent.getStringExtra("route") ?: super.getInitialRoute()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkForUpdates" -> requestUpdateCheck(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestUpdateCheck(result: MethodChannel.Result) {
        if (BuildConfig.FLAVOR != "internal") {
            result.error(
                "UPDATES_UNAVAILABLE",
                "This build receives updates from its app store.",
                null,
            )
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingUpdateResult != null) {
                result.error("UPDATE_IN_PROGRESS", "An update check is already running.", null)
                return
            }
            pendingUpdateResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequest,
            )
            return
        }

        checkForUpdates(result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequest) {
            val result = pendingUpdateResult
            pendingUpdateResult = null
            if (result != null) checkForUpdates(result)
        }
    }

    private fun checkForUpdates(result: MethodChannel.Result) {
        FirebaseAppDistribution.getInstance()
            .updateIfNewReleaseAvailable()
            .addOnSuccessListener { result.success("checked") }
            .addOnFailureListener { error ->
                result.error(
                    "UPDATE_CHECK_FAILED",
                    error.localizedMessage ?: "Could not check for updates.",
                    null,
                )
            }
    }
}
