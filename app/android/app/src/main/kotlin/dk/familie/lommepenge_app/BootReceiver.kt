package dk.familie.lommepenge_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Starts the child's tablet's [LockService] again after a reboot and after
 * the app has updated itself (both are allowed to start a foreground service
 * from the background). Does nothing on other devices.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> LockService.startIfEnabled(context)
        }
    }
}
