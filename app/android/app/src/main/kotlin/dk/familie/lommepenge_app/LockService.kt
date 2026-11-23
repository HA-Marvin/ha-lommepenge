package dk.familie.lommepenge_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The child's tablet's foreground service (Del H3/H4). It runs only on a
 * device paired as a child's tablet, starts with the app and after a reboot
 * or an app update ([BootReceiver]), and:
 *
 * - shows a permanent, discreet notification ("Lommepenge is active"; while a
 *   lock runs: the end time, a countdown and the reason),
 * - fetches `GET /api/lommepenge/state` about every minute,
 * - reports `SCREEN_ON` and `USER_PRESENT` to HA (`report_use`), which starts
 *   a pending lock,
 * - shows an Android notification for every new item in the child's
 *   `notifications` (each id once; the shown ids are remembered).
 *
 * It reads the connection the Flutter app stored after pairing (the legacy
 * shared_preferences file `FlutterSharedPreferences`, keys `flutter.*`) and
 * signs requests exactly like `ha_client.dart`: lowercase hex
 * HMAC-SHA256(deviceKey, `timestamp\nMETHOD\npath\n` + body), with the stored
 * clock correction. A wrong clock is corrected from HA's `serverTime` and
 * never forgets the pairing; a revoked device is left to the app (which
 * forgets the connection and stops this service).
 *
 * All network work runs on one background thread, so polls and reports
 * never overlap.
 */
class LockService : Service() {
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private var receiverRegistered = false

    private val poll = Runnable { pollNow() }

    private val useReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val event = when (intent.action) {
                Intent.ACTION_SCREEN_ON -> "screen_on"
                Intent.ACTION_USER_PRESENT -> "user_present"
                else -> return
            }
            val at = System.currentTimeMillis() / 1000
            handler.post { reportUse(event, at) }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels(this)
        worker = HandlerThread("LommepengeService").apply { start() }
        handler = Handler(worker.looper)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        // Screen on / unlocked are system broadcasts; they can only be received
        // by a receiver registered at runtime (not in the manifest).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(useReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(useReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must be called soon after startForegroundService - also when the
        // service is about to stop again.
        goForeground(statusNotification(null))
        if (Connection.read(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacks(poll)
        handler.post(poll)
        return START_STICKY
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(useReceiver)
            receiverRegistered = false
        }
        handler.removeCallbacksAndMessages(null)
        worker.quitSafely()
        super.onDestroy()
    }

    private fun goForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(STATUS_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(STATUS_NOTIFICATION_ID, notification)
        }
    }

    // ---- Talking to Home Assistant (background thread) -------------------------

    private fun pollNow() {
        handler.removeCallbacks(poll)
        var next = POLL_INTERVAL_MS
        val connection = Connection.read(this)
        if (connection == null) {
            // The app was disconnected or is no longer a child's tablet.
            stopSelf()
            return
        }
        val state = request(connection, "GET", "$API/state", ByteArray(0))
        if (state != null) next = handleState(connection, state)
        handler.postDelayed(poll, next)
    }

    private fun reportUse(event: String, at: Long) {
        val connection = Connection.read(this) ?: return
        val body = JSONObject()
            .put("type", "report_use")
            .put(
                "payload",
                JSONObject()
                    .put("childId", connection.childId)
                    .put("event", event)
                    .put("at", at),
            )
            .toString()
            .toByteArray(Charsets.UTF_8)
        val state = request(connection, "POST", "$API/action", body) ?: return
        val next = handleState(connection, state)
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, next)
        // The app (if open) shows HA's new state at once, e.g. the countdown.
        val listener = stateListener ?: return
        Handler(Looper.getMainLooper()).post { listener() }
    }

    /**
     * Shows HA's state: the lock in the permanent notification and new
     * notifications. Returns when to poll next (sooner when a lock is about
     * to end, so the notification does not show an ended lock for long).
     */
    private fun handleState(connection: Connection, state: JSONObject): Long {
        val children = state.optJSONArray("children") ?: return POLL_INTERVAL_MS
        var child: JSONObject? = null
        for (i in 0 until children.length()) {
            val candidate = children.optJSONObject(i) ?: continue
            if (child == null || candidate.optString("id") == connection.childId) child = candidate
        }
        if (child == null) return POLL_INTERVAL_MS

        val lock = RunningLock.from(child.optJSONObject("lock"), state.optString("now"))
        notificationManager().notify(STATUS_NOTIFICATION_ID, statusNotification(lock))
        child.optJSONArray("notifications")?.let { showNew(it) }

        val remaining = lock?.remainingMs ?: return POLL_INTERVAL_MS
        return (remaining + 2_000).coerceIn(5_000, POLL_INTERVAL_MS)
    }

    /** Signed request; the JSON answer on 200, otherwise `null`. */
    private fun request(connection: Connection, method: String, path: String, body: ByteArray, retry: Boolean = true): JSONObject? {
        var http: HttpURLConnection? = null
        try {
            http = (URL(connection.baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                useCaches = false
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                signedHeaders(connection, method, path, body).forEach { (k, v) -> setRequestProperty(k, v) }
                if (body.isNotEmpty()) {
                    doOutput = true
                    setFixedLengthStreamingMode(body.size)
                    outputStream.use { it.write(body) }
                }
            }
            val status = http.responseCode
            val stream = if (status in 200..299) http.inputStream else http.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            val json = try { JSONObject(text) } catch (e: Exception) { null }
            if (status == 401 && json != null && json.optString("code") == "clock_skew" && json.has("serverTime")) {
                // Wrong clock: correct it (shared with the app) and try once more.
                val offset = (json.optDouble("serverTime") * 1000).toLong() - System.currentTimeMillis()
                Connection.saveClockOffset(this, offset)
                if (retry) {
                    http.disconnect()
                    http = null
                    return request(connection.copy(clockOffsetMs = offset), method, path, body, retry = false)
                }
            }
            return if (status == 200) json else null
        } catch (e: Exception) {
            return null // no connection: try again at the next poll
        } finally {
            http?.disconnect()
        }
    }

    private fun signedHeaders(connection: Connection, method: String, path: String, body: ByteArray): Map<String, String> {
        val timestamp = ((System.currentTimeMillis() + connection.clockOffsetMs) / 1000).toString()
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(connection.key.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        mac.update("$timestamp\n${method.uppercase(Locale.ROOT)}\n$path\n".toByteArray(Charsets.UTF_8))
        mac.update(body)
        val signature = mac.doFinal().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val (versionName, versionCode) = appVersion()
        return mapOf(
            "X-Device-Id" to connection.deviceId,
            "X-Timestamp" to timestamp,
            "X-Signature" to signature,
            "X-App-Version" to versionName,
            "X-App-Version-Code" to versionCode.toString(),
            "X-Lommepenge-Language" to connection.language,
        )
    }

    private fun appVersion(): Pair<String, Long> = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        Pair(info.versionName ?: "", code)
    } catch (e: Exception) {
        Pair("", 0L)
    }

    // ---- Notifications --------------------------------------------------------

    private fun notificationManager() = getSystemService(NotificationManager::class.java)

    private fun builder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE,
    )

    /** The permanent notification: discreet, or the running lock. */
    private fun statusNotification(lock: RunningLock?): Notification {
        val texts = Texts(this)
        val b = builder(STATUS_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(openApp())
        if (lock == null) {
            return b.setContentTitle(texts.active).setShowWhen(false).build()
        }
        b.setContentTitle(texts.lockedUntil.replace("{time}", lock.endsAtText))
            .setContentText(lock.reason)
            .setStyle(Notification.BigTextStyle().bigText(lock.reason))
            .setWhen(System.currentTimeMillis() + lock.remainingMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
        return b.build()
    }

    /**
     * Shows each notification HA has not been shown before, oldest first. The
     * first time (no remembered ids yet, e.g. just after pairing) the existing
     * ones are only remembered, so the child does not get a week's worth at
     * once. Ids HA no longer sends (older than 7 days) are forgotten.
     */
    private fun showNew(items: JSONArray) {
        val prefs = getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE)
        val seeded = prefs.getBoolean(KEY_SEEDED, false)
        val seen = prefs.getStringSet(KEY_SEEN_IDS, emptySet()) ?: emptySet()
        val current = mutableSetOf<String>()
        val texts = Texts(this)
        for (i in items.length() - 1 downTo 0) {
            val item = items.optJSONObject(i) ?: continue
            val id = item.optString("id")
            if (id.isEmpty()) continue
            current.add(id)
            if (!seeded || id in seen) continue
            val message = item.optString("message")
            if (message.isEmpty()) continue
            notificationManager().notify(
                MESSAGE_NOTIFICATION_BASE + (id.hashCode() and 0x0fffffff) % 1_000_000,
                builder(MESSAGES_CHANNEL)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(texts.appName)
                    .setContentText(message)
                    .setStyle(Notification.BigTextStyle().bigText(message))
                    .setContentIntent(openApp())
                    .setAutoCancel(true)
                    .build(),
            )
        }
        prefs.edit()
            .putBoolean(KEY_SEEDED, true)
            .putStringSet(KEY_SEEN_IDS, HashSet(current))
            .apply()
    }

    /** A running lock from HA's state, with times relative to HA's `now`. */
    private class RunningLock(val remainingMs: Long, val endsAtText: String, val reason: String) {
        companion object {
            fun from(lock: JSONObject?, now: String): RunningLock? {
                if (lock == null || lock.optString("status") != "running") return null
                val endsAt = lock.optString("endsAt")
                val end = parse(endsAt) ?: return null
                val start = parse(now) ?: return null
                val remaining = end - start
                if (remaining <= 0) return null
                val reason = if (lock.isNull("reason")) "" else lock.optString("reason")
                // HA's local time of day, shown as it is ("HH:MM").
                return RunningLock(remaining, endsAt.substring(11, 16), reason)
            }

            /** HA's local time without offset; only differences are used. */
            private fun parse(text: String): Long? {
                for (pattern in arrayOf("yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss")) {
                    try {
                        val format = SimpleDateFormat(pattern, Locale.US)
                        format.timeZone = TimeZone.getTimeZone("UTC")
                        format.isLenient = false
                        return format.parse(text)?.time
                    } catch (e: Exception) {
                        // try the next pattern
                    }
                }
                return null
            }
        }
    }

    /** The pairing the app stored, if this device is a connected child's tablet. */
    data class Connection(
        val baseUrl: String,
        val deviceId: String,
        val key: String,
        val childId: String,
        val language: String,
        val clockOffsetMs: Long,
    ) {
        companion object {
            private const val FLUTTER_PREFS = "FlutterSharedPreferences"

            fun read(context: Context): Connection? {
                val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                if (prefs.getString("flutter.role", null) != "child_tablet") return null
                val url = prefs.getString("flutter.ha_url", null) ?: return null
                val id = prefs.getString("flutter.ha_device_id", null) ?: return null
                val key = prefs.getString("flutter.ha_device_key", null) ?: return null
                val childId = prefs.getString("flutter.bound_child_id", null) ?: return null
                val offset = try {
                    prefs.getLong("flutter.clock_offset_ms", 0L)
                } catch (e: ClassCastException) {
                    0L
                }
                return Connection(
                    baseUrl = url,
                    deviceId = id,
                    key = key,
                    childId = childId,
                    language = prefs.getString("flutter.language", null) ?: "en",
                    clockOffsetMs = offset,
                )
            }

            /** Same key and type (Long) as the app's `SettingsService.clockOffsetMs`. */
            fun saveClockOffset(context: Context, offsetMs: Long) {
                context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putLong("flutter.clock_offset_ms", offsetMs)
                    .apply()
            }
        }
    }

    /** The texts in the app's language, sent by the app (see [configure]). */
    private class Texts(context: Context) {
        private val prefs = context.getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE)
        val statusChannel = prefs.getString("text_statusChannel", null) ?: "Status"
        val messagesChannel = prefs.getString("text_messagesChannel", null) ?: "Messages"
        val active = prefs.getString("text_active", null) ?: "Lommepenge is active"
        val lockedUntil = prefs.getString("text_lockedUntil", null) ?: "Locked until {time}"
        val appName = "Lommepenge"
    }

    companion object {
        private const val API = "/api/lommepenge"
        private const val POLL_INTERVAL_MS = 60_000L
        private const val TIMEOUT_MS = 8_000
        private const val STATUS_CHANNEL = "service_status"
        private const val MESSAGES_CHANNEL = "child_messages"
        private const val STATUS_NOTIFICATION_ID = 2
        private const val MESSAGE_NOTIFICATION_BASE = 1000
        private const val SERVICE_PREFS = "lommepenge_service"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SEEDED = "notifications_seeded"
        private const val KEY_SEEN_IDS = "notification_ids_seen"

        /** Called on the main thread after HA's state changed (set by [MainActivity]). */
        @Volatile
        var stateListener: (() -> Unit)? = null

        /**
         * Called by the app: starts the service with the [texts] in the app's
         * language, or stops it. Whether it should run is remembered for
         * [BootReceiver].
         */
        fun configure(context: Context, enabled: Boolean, texts: Map<String, String>) {
            val editor = context.getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE).edit()
            editor.putBoolean(KEY_ENABLED, enabled)
            texts.forEach { (key, value) -> editor.putString("text_$key", value) }
            if (!enabled) editor.remove(KEY_SEEDED).remove(KEY_SEEN_IDS)
            editor.apply()
            createChannels(context)
            val intent = Intent(context, LockService::class.java)
            if (enabled) start(context) else context.stopService(intent)
        }

        /** After a reboot or an app update: start again if the app said so. */
        fun startIfEnabled(context: Context) {
            val enabled = context.getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)
            if (enabled && Connection.read(context) != null) start(context)
        }

        private fun start(context: Context) {
            val intent = Intent(context, LockService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** The channels' names follow the app's language. */
        private fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val texts = Texts(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(STATUS_CHANNEL, texts.statusChannel, NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(MESSAGES_CHANNEL, texts.messagesChannel, NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }
}
