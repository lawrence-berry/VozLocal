package com.vozlocal.screensaver

import android.graphics.Color
import android.service.dreams.DreamService
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import kotlin.concurrent.thread

private const val PAGE = "https://appassets.androidplatform.net/assets/index.html"
private const val TIMEOUT_MS = 10_000

// The screensaver: one WebView on the bundled page (assets/index.html). The page does everything it can on its
// own; this class only fetches the personal phrases, because the Worker sends no CORS headers for the page to
// call it, and hands them over. That keeps the token out of the page.
class VozDream : DreamService() {
    private var web: WebView? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = false
        isFullscreen = true
        val assets = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()
        web = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true // the page caches the last phrases in localStorage
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            webViewClient = object : WebViewClient() {
                // Only the bundled page's own origin loads; anything else gets an empty 403 instead of the network.
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                    assets.shouldInterceptRequest(request.url)
                        ?: WebResourceResponse("text/plain", "utf-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(ByteArray(0)))

                override fun onPageFinished(view: WebView, url: String) = fetchPersonal(view)
            }
            loadUrl(PAGE)
        }
        setContentView(web)
    }

    override fun onDetachedFromWindow() {
        web?.destroy()
        web = null
        super.onDetachedFromWindow()
    }

    // GET /phrases with the bearer token, off the main thread, then window.vozPersonal(text) in the page. Any
    // failure (offline, wrong token) leaves the page with what it cached last time.
    private fun fetchPersonal(view: WebView) {
        val base = BuildConfig.VOZ_URL.trimEnd('/')
        if (!base.startsWith("https://") || BuildConfig.VOZ_TOKEN.isEmpty()) return // never send the token in clear
        thread {
            try {
                val connection = URL("$base/phrases?since=0").openConnection() as HttpURLConnection
                connection.connectTimeout = TIMEOUT_MS
                connection.readTimeout = TIMEOUT_MS
                connection.setRequestProperty("Authorization", "Bearer ${BuildConfig.VOZ_TOKEN}")
                try {
                    if (connection.responseCode != 200) return@thread
                    val text = connection.inputStream.bufferedReader().use { it.readText() }
                    view.post { if (web === view) view.evaluateJavascript("window.vozPersonal(${JSONObject.quote(text)})", null) }
                } finally {
                    connection.disconnect()
                }
            } catch (_: Exception) {
            }
        }
    }
}
