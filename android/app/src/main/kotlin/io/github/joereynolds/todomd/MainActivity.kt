package io.github.joereynolds.todomd

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Storage access for the Dart side (lib/ui/platform.dart). The app reads notes
// folders with plain file IO, so it needs "All files access" (Android 11+) or
// the storage permission (older), and a folder picker that yields a path.
class MainActivity : FlutterActivity() {
    private val pickFolder = 41
    private val askStorage = 42
    private var pending: MethodChannel.Result? = null

    // Keep the screen on while the app is in the foreground (the flag is per
    // window, so it lapses as soon as the app is left).
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "todomd/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasAccess())
                "requestAccess" -> requestAccess(result)
                "pickFolder" -> {
                    pending?.success(null)
                    pending = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), pickFolder)
                }
                "externalRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
                "shareText" -> {
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                    startActivity(Intent.createChooser(send, null))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    // Android 11+: opens the settings page and returns null at once (the Dart
    // side checks again when the app resumes). Older: the permission dialog.
    private fun requestAccess(result: MethodChannel.Result) {
        if (hasAccess()) return result.success(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
            result.success(null) // unknown until the user comes back
        } else {
            pending?.success(null)
            pending = result
            requestPermissions(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                askStorage,
            )
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == askStorage) {
            pending?.success(hasAccess())
            pending = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(code, resultCode, data)
        if (code != pickFolder) return
        val uri = data?.data
        pending?.success(if (resultCode == RESULT_OK && uri != null) treeToPath(uri) else null)
        pending = null
    }

    // content://…/tree/primary:Notes/todo -> /storage/emulated/0/Notes/todo
    // SD cards: tree/1234-ABCD:Notes -> /storage/1234-ABCD/Notes
    private fun treeToPath(uri: Uri): String? {
        val id = DocumentsContract.getTreeDocumentId(uri) ?: return null
        val colon = id.indexOf(':')
        if (colon < 0) return null
        val volume = id.substring(0, colon)
        val rel = id.substring(colon + 1)
        val base = if (volume == "primary") Environment.getExternalStorageDirectory().absolutePath else "/storage/$volume"
        return if (rel.isEmpty()) base else "$base/$rel"
    }
}
