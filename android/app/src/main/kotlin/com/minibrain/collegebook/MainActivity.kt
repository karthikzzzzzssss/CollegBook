package com.minibrain.collegebook

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.minibrain.collegebook.Utilities.FcmTokenHelper
import com.minibrain.collegebook.Utilities.Utils
import java.io.File
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingCallNumber: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collegebook/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The native app reports everything with Toast.LENGTH_SHORT.
                    "showToast" -> {
                        toast(call.argument<String>("message").orEmpty())
                        result.success(null)
                    }
                    // DisplayMetrics.heightPixels in px, which native sheets size from
                    // (the display less the navigation bar).
                    "displayHeight" -> {
                        val metrics = android.util.DisplayMetrics()
                        @Suppress("DEPRECATION")
                        windowManager.defaultDisplay.getMetrics(metrics)
                        result.success(metrics.heightPixels)
                    }
                    // Same rule as the native FcmTokenHelper.needsPermission().
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    // FcmTokenHelper: the FCM token when notifications are on, else null —
                    // answered within 5s at the latest.
                    "fcmToken" -> FcmTokenHelper.fetchIfNotificationsEnabled(this) { token ->
                        result.success(token)
                    }
                    "notificationsEnabled" ->
                        result.success(FcmTokenHelper.notificationsEnabled(this))
                    "needsNotificationPermission" ->
                        result.success(FcmTokenHelper.needsPermission(this))
                    // Whether Android would still show the POST_NOTIFICATIONS prompt.
                    "shouldShowNotificationRationale" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS),
                    )
                    // The app's notification settings (native showEnableNotificationsDialog()).
                    "openNotificationSettings" -> {
                        val settings = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        try {
                            startActivity(settings)
                        } catch (e: ActivityNotFoundException) {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                    .setData(Uri.parse("package:$packageName")),
                            )
                        }
                        result.success(null)
                    }
                    // The login the native mentor-call screens act with (Flutter secure storage
                    // can't be read from there).
                    "setCallAuth" -> {
                        Utils.saveAuth(
                            this,
                            call.argument<String>("access"),
                            call.argument<String>("refresh"),
                            call.argument<String>("baseUrl"),
                        )
                        result.success(null)
                    }
                    "clearCallAuth" -> {
                        Utils.clearAuthData(this)
                        result.success(null)
                    }
                    // Like the native callNow(): a direct ACTION_CALL once CALL_PHONE is granted.
                    "callNumber" -> {
                        callNumber(call.argument<String>("number").orEmpty())
                        result.success(null)
                    }
                    // ChoiceListExporter.save(): Downloads/CollegeBook on Android 10+, else the
                    // cache shared through the FileProvider. Answers the file's content:// Uri.
                    "saveDownload" -> {
                        try {
                            result.success(
                                saveDownload(
                                    call.argument<String>("fileName")!!,
                                    call.argument<String>("mimeType")!!,
                                    call.argument<ByteArray>("bytes")!!,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    // DownloadChoiceListSheet.open(): view it, else share it.
                    // ContactUsActivity.callSupport: the dialer with the number filled in.
                    "dial" -> {
                        result.success(
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + call.argument<String>("number")!!)),
                                )
                                true
                            } catch (e: android.content.ActivityNotFoundException) {
                                false
                            },
                        )
                    }
                    // AboutActivity.shareApp: plain text through a chooser.
                    "shareText" -> {
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject"))
                            .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                        startActivity(Intent.createChooser(send, call.argument<String>("title")))
                        result.success(null)
                    }
                    "viewUrl" -> {
                        result.success(
                            viewUrl(
                                call.argument<String>("url")!!,
                                call.argument<String>("mimeType"),
                                call.argument<String>("chooserTitle"),
                                call.argument<String>("package"),
                            ),
                        )
                    }
                    "openFile" -> {
                        openFile(
                            Uri.parse(call.argument<String>("uri")!!),
                            call.argument<String>("mimeType")!!,
                            call.argument<String>("format")!!,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun toast(message: String) {
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        // A newer request replaces an unanswered one.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun saveDownload(fileName: String, mimeType: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + DOWNLOAD_FOLDER)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Couldn't create $fileName")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Couldn't open $fileName")
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }
        val dir = File(cacheDir, DOWNLOAD_FOLDER).apply { mkdirs() }
        val file = File(dir, fileName)
        file.writeBytes(bytes)
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", file).toString()
    }

    private fun openFile(uri: Uri, mimeType: String, format: String) {
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mimeType)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(view)
        } catch (e: ActivityNotFoundException) {
            val share = Intent(Intent.ACTION_SEND)
                .setType(mimeType)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                startActivity(Intent.createChooser(share, "Open $format with"))
            } catch (e2: ActivityNotFoundException) {
                Toast.makeText(applicationContext, "No app found to open this $format", Toast.LENGTH_LONG).show()
            }
        }
    }

    // GroupChatFragment: a chat image opens in an image viewer, a file through a chooser.
    // With a package, only that app may open it (false when it isn't installed).
    private fun viewUrl(url: String, mimeType: String?, chooserTitle: String?, pkg: String?): Boolean {
        val uri = Uri.parse(url)
        return try {
            when {
                pkg != null -> startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage(pkg))
                chooserTitle != null ->
                    startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW, uri), chooserTitle))
                mimeType != null -> startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType))
                else -> startActivity(Intent(Intent.ACTION_VIEW, uri))
            }
            true
        } catch (e: android.content.ActivityNotFoundException) {
            if (pkg != null) return false
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
                true
            } catch (e: android.content.ActivityNotFoundException) {
                false
            }
        }
    }

    private fun callNumber(number: String) {
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")))
        } else {
            pendingCallNumber = number
            requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), CALL_PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            NOTIFICATION_PERMISSION_REQUEST -> {
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
            }
            CALL_PERMISSION_REQUEST -> {
                val number = pendingCallNumber
                pendingCallNumber = null
                if (granted && number != null) {
                    startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")))
                } else {
                    toast("Permission DENIED")
                }
            }
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 4101
        const val CALL_PERMISSION_REQUEST = 4102
        const val DOWNLOAD_FOLDER = "CollegeBook"
    }
}
