package com.arth.taxgap

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.arth.taxgap/app_updates"
    private val updateManifestUrl =
        "https://github.com/rish106-hub/ARTH/releases/latest/download/arth-update.json"
    private val updateExecutor = Executors.newSingleThreadExecutor()

    override fun getInitialRoute(): String? {
        return intent.getStringExtra("route") ?: super.getInitialRoute()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkForUpdates" -> checkForUpdates(result)
                    "downloadAndInstallUpdate" -> downloadAndInstallUpdate(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkForUpdates(result: MethodChannel.Result) {
        if (!isDirectDistribution()) {
            result.error(
                "UPDATES_UNAVAILABLE",
                "This build receives updates from its app store.",
                null,
            )
            return
        }

        updateExecutor.execute {
            try {
                val manifest = JSONObject(downloadText(updateManifestUrl))
                val versionCode = manifest.getLong("versionCode")
                val versionName = manifest.getString("versionName")
                val apkUrl = manifest.getString("apkUrl")
                val sha256 = manifest.getString("sha256").lowercase()
                val releaseNotes = manifest.optString("releaseNotes", "")

                require(versionCode > 0) { "Invalid update version." }
                require(versionName.isNotBlank()) { "Invalid update name." }
                require(sha256.matches(Regex("^[a-f0-9]{64}$"))) {
                    "Invalid update checksum."
                }
                validateDownloadUrl(apkUrl)

                success(
                    result,
                    mapOf(
                        "status" to if (versionCode > BuildConfig.VERSION_CODE) {
                            "available"
                        } else {
                            "current"
                        },
                        "currentVersionCode" to BuildConfig.VERSION_CODE.toLong(),
                        "versionCode" to versionCode,
                        "versionName" to versionName,
                        "apkUrl" to apkUrl,
                        "sha256" to sha256,
                        "releaseNotes" to releaseNotes,
                    ),
                )
            } catch (error: Exception) {
                failure(result, "UPDATE_CHECK_FAILED", safeMessage(error))
            }
        }
    }

    private fun downloadAndInstallUpdate(arguments: Any?, result: MethodChannel.Result) {
        if (!isDirectDistribution()) {
            result.error(
                "UPDATES_UNAVAILABLE",
                "This build receives updates from its app store.",
                null,
            )
            return
        }

        val values = arguments as? Map<*, *>
        val apkUrl = values?.get("apkUrl") as? String
        val expectedSha256 = (values?.get("sha256") as? String)?.lowercase()
        val expectedVersionCode = (values?.get("versionCode") as? Number)?.toLong()
        if (
            apkUrl == null ||
            expectedSha256 == null ||
            expectedVersionCode == null ||
            expectedVersionCode <= BuildConfig.VERSION_CODE ||
            !expectedSha256.matches(Regex("^[a-f0-9]{64}$"))
        ) {
            result.error("INVALID_UPDATE", "The update metadata is invalid.", null)
            return
        }

        try {
            validateDownloadUrl(apkUrl)
        } catch (error: Exception) {
            result.error("INVALID_UPDATE", safeMessage(error), null)
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.error(
                "INSTALL_PERMISSION_REQUIRED",
                "Allow ARTH to install updates, then tap Check for updates again.",
                null,
            )
            return
        }

        updateExecutor.execute {
            val updateDirectory = File(cacheDir, "updates")
            val apk = File(updateDirectory, "ARTH-$expectedVersionCode.apk")
            try {
                updateDirectory.mkdirs()
                downloadApk(apkUrl, apk)
                verifyChecksum(apk, expectedSha256)
                verifyPackage(apk, expectedVersionCode)
                runOnUiThread {
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.update_files",
                            apk,
                        )
                        startActivity(
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            },
                        )
                        result.success(mapOf("status" to "installer_opened"))
                    } catch (error: Exception) {
                        failure(result, "INSTALLER_FAILED", safeMessage(error))
                    }
                }
            } catch (error: Exception) {
                apk.delete()
                failure(result, "UPDATE_DOWNLOAD_FAILED", safeMessage(error))
            }
        }
    }

    private fun isDirectDistribution() = BuildConfig.FLAVOR == "internal"

    private fun downloadText(source: String): String {
        val connection = openConnection(source)
        return connection.inputStream.bufferedReader().use { it.readText() }
    }

    private fun downloadApk(source: String, destination: File) {
        val connection = openConnection(source)
        val declaredSize = connection.contentLengthLong
        require(declaredSize == -1L || declaredSize in 1..MAX_APK_BYTES) {
            "The update file size is invalid."
        }
        var total = 0L
        connection.inputStream.use { input ->
            destination.outputStream().use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= MAX_APK_BYTES) { "The update file is too large." }
                    output.write(buffer, 0, count)
                }
            }
        }
        require(total > 0) { "The downloaded update is empty." }
    }

    private fun openConnection(source: String): HttpURLConnection {
        var current = source
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            validateDownloadUrl(current)
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 60_000
            connection.setRequestProperty(
                "Accept",
                "application/octet-stream, application/json",
            )
            connection.setRequestProperty(
                "User-Agent",
                "ARTH-Android/${BuildConfig.VERSION_NAME}",
            )
            connection.connect()
            if (connection.responseCode in 300..399) {
                val location = connection.getHeaderField("Location")
                    ?: error("The update redirect is invalid.")
                require(redirectCount < MAX_REDIRECTS) { "Too many update redirects." }
                current = URL(URL(current), location).toString()
                connection.disconnect()
            } else {
                require(connection.responseCode in 200..299) {
                    "Update server returned ${connection.responseCode}."
                }
                return connection
            }
        }
        error("Too many update redirects.")
    }

    private fun validateDownloadUrl(source: String) {
        val uri = Uri.parse(source)
        require(uri.scheme == "https") { "Updates must use HTTPS." }
        require(uri.host in ALLOWED_UPDATE_HOSTS) { "Untrusted update server." }
    }

    private fun verifyChecksum(file: File, expected: String) {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        require(actual == expected) { "The update checksum does not match." }
    }

    @Suppress("DEPRECATION")
    private fun verifyPackage(file: File, expectedVersionCode: Long) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: error("Android could not read the update package.")
        require(archive.packageName == packageName) { "The update package name does not match." }
        require(archive.longVersionCode == expectedVersionCode) {
            "The update version does not match."
        }
        require(expectedVersionCode > BuildConfig.VERSION_CODE) { "The update is not newer." }

        val installed = packageManager.getPackageInfo(packageName, flags)
        require(signingDigests(archive) == signingDigests(installed)) {
            "The update signing certificate does not match ARTH."
        }
    }

    private fun signingDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    private fun success(result: MethodChannel.Result, value: Any) {
        runOnUiThread { result.success(value) }
    }

    private fun failure(result: MethodChannel.Result, code: String, message: String) {
        runOnUiThread { result.error(code, message, null) }
    }

    private fun safeMessage(error: Exception): String =
        error.message?.takeIf { it.isNotBlank() } ?: "The update could not be verified."

    override fun onDestroy() {
        updateExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val MAX_APK_BYTES = 200L * 1024L * 1024L
        private const val MAX_REDIRECTS = 5
        private val ALLOWED_UPDATE_HOSTS = setOf(
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com",
            "github-releases.githubusercontent.com",
        )
    }
}
