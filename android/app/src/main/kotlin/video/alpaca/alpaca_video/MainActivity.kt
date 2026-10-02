package video.alpaca.alpaca_video

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "video.run/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            val wifi =
                                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock =
                                wifi.createMulticastLock("video-run").apply {
                                    setReferenceCounted(false)
                                }
                        }
                        multicastLock?.let { lock ->
                            if (!lock.isHeld) lock.acquire()
                        }
                        result.success(true)
                    }
                    "release" -> {
                        multicastLock?.let { lock ->
                            if (lock.isHeld) lock.release()
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
