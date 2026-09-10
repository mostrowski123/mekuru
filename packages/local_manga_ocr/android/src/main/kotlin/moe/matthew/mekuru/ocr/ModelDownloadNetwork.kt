package moe.matthew.mekuru.ocr

import android.content.Context
import android.net.ConnectivityManager
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

    fun isWifiConnected(): Boolean = connectivity.activeNetwork?.let {
        connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    } == true

    fun open(url: String): HttpURLConnection {
        val network = connectivity.activeNetwork ?: throw IOException("network_unavailable")
        val wifi = connectivity.getNetworkCapabilities(network)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        if (!allowMobileData && !wifi) throw IOException("wifi_required")
        return network.openConnection(URL(url)) as HttpURLConnection
    }
}
