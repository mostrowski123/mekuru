package moe.matthew.mekuru.ocr

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Consent applies to this transfer only. A Wi-Fi request stays bound to the
 * checked network, so a later default-network switch cannot upload/download
 * model bytes over cellular without confirmation. VPN transports are included
 * in the default network's capabilities by Android. */
class ModelDownloadNetwork(context: Context, private val allowMobileData: Boolean) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    fun isWifiConnected(): Boolean = connectivity.activeNetwork?.let(::isUnmeteredWifi) == true

    /** A VPN carries the traffic. Android counts most VPNs as metered, so Wi-Fi under one
     * still gets the mobile-data question; the app then says the VPN is why. */
    fun isVpn(): Boolean = connectivity.activeNetwork
        ?.let(connectivity::getNetworkCapabilities)
        ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

    fun open(url: String): HttpURLConnection {
        val network = connectivity.activeNetwork ?: throw IOException("network_unavailable")
        if (!allowMobileData && !isUnmeteredWifi(network)) throw IOException("wifi_required")
        return network.openConnection(URL(url)) as HttpURLConnection
    }

    /** Wi-Fi that isn't metered. A phone's hotspot, or a Wi-Fi the user marked
     * metered, costs data like mobile does, so it gets the mobile-data question
     * (like iOS's isUnmetered), and WorkManager's UNMETERED constraint, which
     * Dart downloads started "on Wi-Fi" use, would never run on it. */
    private fun isUnmeteredWifi(network: Network): Boolean =
        connectivity.getNetworkCapabilities(network)?.let {
            it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } == true
}
