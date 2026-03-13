package com.example.ouiborne

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    // Ce nom doit être identique à celui dans ton code Dart (UpdateService)
    private val CHANNEL = "apk_install"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("path")
                if (filePath != null) {
                    try {
                        installApk(filePath)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_PATH", "Le chemin du fichier est null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        if (!file.exists()) {
            println("Erreur: Le fichier APK n'existe pas à l'emplacement : $filePath")
            return
        }

        val intent = Intent(Intent.ACTION_VIEW)
        val uri: Uri

        // Gestion sécurisée pour Android 7.0 (Nougat) et supérieur
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // "com.example.ouiborne.fileprovider" doit correspondre à ton AndroidManifest
            uri = FileProvider.getUriForFile(
                context,
                "com.example.ouiborne.fileprovider",
                file
            )
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            // Pour les très vieux Android (< 7.0)
            uri = Uri.fromFile(file)
        }

        intent.setDataAndType(uri, "application/vnd.android.package-archive")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        startActivity(intent)
    }
}