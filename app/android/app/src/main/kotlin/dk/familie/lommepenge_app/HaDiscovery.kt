package dk.familie.lommepenge_app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address

/**
 * Finder Home Assistant på hjemmenettet via mDNS (`_home-assistant._tcp`),
 * som HA selv annoncerer. Så skal man kun taste koden fra "Tilføj enhed".
 *
 * Søger i [TIMEOUT_MS] og svarer med en liste af `{name, url}`. URL'en
 * bygges af den fundne IP-adresse (`.local`-navne kan ikke altid slås op
 * fra appen) og HA's port.
 */
class HaDiscovery(
    context: Context,
    private val done: (List<Map<String, String>>) -> Unit,
) {
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<NsdServiceInfo>()
    private val found = mutableListOf<Map<String, String>>()
    private var resolving = false
    private var finished = false

    private val listener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) = Unit
        override fun onDiscoveryStopped(serviceType: String) = Unit
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            handler.post { finish(stopDiscovery = false) }
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            handler.post {
                pending.addLast(serviceInfo)
                resolveNext()
            }
        }
    }

    fun start() {
        if (nsd == null) {
            done(emptyList())
            return
        }
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        handler.postDelayed({ finish(stopDiscovery = true) }, TIMEOUT_MS)
    }

    // Ældre Android kan kun slå én tjeneste op ad gangen.
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (resolving || finished) return
        val info = pending.removeFirstOrNull() ?: return
        resolving = true
        nsd!!.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                handler.post {
                    resolving = false
                    resolveNext()
                }
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                handler.post {
                    add(serviceInfo)
                    resolving = false
                    resolveNext()
                }
            }
        })
    }

    private fun add(info: NsdServiceInfo) {
        val attributes = info.attributes.mapValues { String(it.value ?: ByteArray(0)) }
        @Suppress("DEPRECATION")
        val host = info.host ?: return
        val address = if (host is Inet4Address) host.hostAddress else "[${host.hostAddress}]"
        val configured = attributes["internal_url"].orEmpty().ifBlank { attributes["base_url"].orEmpty() }
        val scheme = if (configured.startsWith("https")) "https" else "http"
        val url = "$scheme://$address:${info.port}"
        if (found.none { it["url"] == url }) {
            found.add(mapOf("name" to (attributes["location_name"] ?: info.serviceName), "url" to url))
        }
    }

    private fun finish(stopDiscovery: Boolean) {
        if (finished) return
        finished = true
        if (stopDiscovery) {
            try {
                nsd?.stopServiceDiscovery(listener)
            } catch (_: IllegalArgumentException) {
                // allerede stoppet
            }
        }
        done(found.toList())
    }

    companion object {
        private const val SERVICE_TYPE = "_home-assistant._tcp."
        private const val TIMEOUT_MS = 4000L
    }
}
