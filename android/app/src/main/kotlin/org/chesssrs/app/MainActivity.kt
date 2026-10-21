package org.chesssrs.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
  private val SYSTEM_CHANNEL = "mobile.lichess.org/system"
  private val SHARE_CHANNEL = "mobile.lichess.org/share"
  private val SHARE_EVENTS_CHANNEL = "mobile.lichess.org/share/events"

  // PGN the app was cold-started with, served once via the `getInitialPgn` method
  // call. Also holds a PGN shared while running if Flutter isn't listening yet.
  private var initialPgn: String? = null
  private var shareEventSink: EventChannel.EventSink? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    installSplashScreen()
    initialPgn = readPgnFromIntent(intent)
    super.onCreate(savedInstanceState)
  }

  // Deep links (study/broadcast/puzzle/share/open-web, etc.) delivered while the app is already
  // running arrive here. Flutter's default handling leaves getIntent() pointing at the stale launch
  // intent, so app_links would read the wrong URI; setIntent() updates the activity's current intent
  // to the freshly received one so app_links surfaces it correctly. (OAuth callbacks no longer pass
  // through here — flutter_appauth captures them in its own RedirectUriReceiverActivity.)
  override fun onNewIntent(intent: Intent) {
    setIntent(intent)
    super.onNewIntent(intent)
    readPgnFromIntent(intent)?.let { pgn ->
      val sink = shareEventSink
      if (sink != null) sink.success(pgn) else initialPgn = pgn
    }
  }

  // Reads the text of a shared/opened PGN file. The manifest only routes the
  // chess-pgn mime types and *.pgn content URIs here, so we can read the stream
  // directly without inspecting the mime type.
  private fun readPgnFromIntent(intent: Intent?): String? {
    val uri: Uri? = when (intent?.action) {
      Intent.ACTION_VIEW -> intent.data
      Intent.ACTION_SEND -> {
        @Suppress("DEPRECATION")
        intent.getParcelableExtra(Intent.EXTRA_STREAM)
      }
      else -> null
    }
    return uri?.let {
      try {
        contentResolver.openInputStream(it)?.use { stream ->
          stream.readBytes().toString(Charsets.UTF_8)
        }
      } catch (e: Exception) {
        Log.w("SharePgn", "Failed to read shared PGN", e)
        null
      }
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler {
      call, result ->
      when (call.method) {
          "clearApplicationUserData" -> {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            result.success(activityManager.clearApplicationUserData())
          }
          "getTotalRam" -> {
            val memoryInfo = getAvailableMemory()
            val totalMemInMb = memoryInfo.totalMem / 1048576L
            result.success(totalMemInMb.toInt())
          }
          // Returns the default browser's package and version, used to attribute login failures.
          "getDefaultBrowser" -> {
            result.success(getDefaultBrowserInfo())
          }
          "canRequestPackageInstalls" -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              result.success(packageManager.canRequestPackageInstalls())
            } else {
              result.success(true)
            }
          }
          "openInstallPermissionSettings" -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                  data = Uri.parse("package:$packageName")
                  addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
              } catch (e: Exception) {
                Log.w("MainActivity", "Failed to open install permission settings", e)
                result.success(false)
              }
            } else {
              result.success(true)
            }
          }
          "installApk" -> {
            val filePath = call.argument<String>("filePath")
            if (filePath == null) {
              result.error("INVALID_ARGUMENT", "filePath is required", null)
              return@setMethodCallHandler
            }
            try {
              val file = File(filePath)
              if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return@setMethodCallHandler
              }
              val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
              )
              val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
              }
              startActivity(intent)
              result.success(true)
            } catch (e: Exception) {
              Log.e("MainActivity", "Failed to start install intent", e)
              result.error("INSTALL_ERROR", e.message, null)
            }
          }
          // "getAvailableRam" -> {
          //   val memoryInfo = getAvailableMemory()
          //   val availMemInMb = memoryInfo.availMem / 1048576L
          //   result.success(availMemInMb.toInt())
          // }
          else -> {
            result.notImplemented()
          }
      }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler {
      call, result ->
      if (call.method == "getInitialPgn") {
        result.success(initialPgn)
        initialPgn = null
      } else {
        result.notImplemented()
      }
    }

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_EVENTS_CHANNEL).setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          shareEventSink = events
        }

        override fun onCancel(arguments: Any?) {
          shareEventSink = null
        }
      }
    )
  }

  private fun getAvailableMemory(): ActivityManager.MemoryInfo {
    val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    return ActivityManager.MemoryInfo().also { memoryInfo ->
        activityManager.getMemoryInfo(memoryInfo)
    }
  }

  private fun getDefaultBrowserInfo(): Map<String, String?>? {
    return try {
      val pm = packageManager
      val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://lichess.org"))
      val resolveInfo = pm.resolveActivity(browserIntent, PackageManager.MATCH_DEFAULT_ONLY)
      val pkg = resolveInfo?.activityInfo?.packageName ?: return null
      val version = try {
        pm.getPackageInfo(pkg, 0).versionName
      } catch (e: Exception) {
        null
      }
      mapOf("package" to pkg, "version" to version)
    } catch (e: Exception) {
      null
    }
  }
}
