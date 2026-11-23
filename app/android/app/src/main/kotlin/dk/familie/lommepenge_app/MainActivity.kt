package dk.familie.lommepenge_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * The app's small bridge to Android (channel "lommepenge/native"):
 *
 * - links from Home Assistant's install page (`lommepenge://pair?...`)
 * - search for Home Assistant on the home network (see [HaDiscovery])
 * - the app's own version, so it can be compared with HA's latest
 * - installation of an update fetched from HA (PackageInstaller - on
 *   Android 12+ without an extra tap when the app installed the last version
 *   itself)
 * - a notification when there is a new version (texts in the app's language
 *   come from Flutter)
 * - starting/stopping the child's tablet's background service ([LockService])
 *   and telling Flutter when that service has changed something in HA
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingLink = linkFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    "appVersion" -> result.success(appVersion())
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                        )
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")!!
                        thread {
                            try {
                                installApk(path)
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("install", e.message, null) }
                            }
                        }
                    }
                    "discoverHa" -> HaDiscovery(this@MainActivity) { result.success(it) }.start()
                    "childService" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val texts = call.argument<Map<String, String>>("texts") ?: emptyMap()
                        if (enabled) askForNotificationPermission()
                        try {
                            LockService.configure(this@MainActivity, enabled, texts)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("childService", e.message, null)
                        }
                    }
                    "notify" -> {
                        notifyUpdate(
                            call.argument<String>("title")!!,
                            call.argument<String>("text")!!,
                            call.argument<String>("channelName") ?: "Updates",
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        LockService.stateListener = { channel?.invokeMethod("refresh", null) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LockService.stateListener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Android 13+: notifications need the user's permission. */
    private fun askForNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_INSTALL_STATUS) {
            handleInstallStatus(intent)
            return
        }
        val link = linkFrom(intent) ?: return
        val current = channel
        if (current != null) current.invokeMethod("link", link) else pendingLink = link
    }

    private fun linkFrom(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == "lommepenge" }?.toString()

    private fun appVersion(): Map<String, Any?> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf("name" to info.versionName, "code" to code)
    }

    private fun installApk(path: String) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            File(path).inputStream().use { input ->
                session.openWrite("lommepenge.apk", 0, -1).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val status = Intent(this, MainActivity::class.java).setAction(ACTION_INSTALL_STATUS)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getActivity(this, sessionId, status, flags).intentSender)
        }
    }

    private fun handleInstallStatus(intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            PackageInstaller.STATUS_SUCCESS -> Unit // the app is restarted by Android
            else -> channel?.invokeMethod(
                "installFailed",
                intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
            )
        }
    }

    private fun notifyUpdate(title: String, text: String, channelName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(UPDATE_CHANNEL, channelName, NotificationManager.IMPORTANCE_DEFAULT)
            )
            Notification.Builder(this, UPDATE_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )
        manager.notify(
            UPDATE_NOTIFICATION_ID,
            builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
    }

    companion object {
        private const val CHANNEL = "lommepenge/native"
        private const val ACTION_INSTALL_STATUS = "dk.familie.lommepenge_app.INSTALL_STATUS"
        private const val UPDATE_CHANNEL = "updates"
        private const val UPDATE_NOTIFICATION_ID = 1
    }
}
