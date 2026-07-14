package com.nepogano.app

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "nepogano/social_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val filePath = call.argument<String>("filePath")
            when (call.method) {
                "shareInstagramStory" -> result.success(shareInstagramStory(filePath!!))
                "shareToPackage" -> {
                    val packageName = call.argument<String>("packageName")!!
                    result.success(shareToPackage(filePath!!, packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Копіює файл у кеш-теку, зареєстровану FileProvider'ом share_plus, і повертає content:// URI. */
    private fun contentUriFor(filePath: String): Uri {
        val srcFile = File(filePath)
        val shareCacheDir = File(cacheDir, "share_plus")
        if (!shareCacheDir.exists()) shareCacheDir.mkdirs()
        val destFile = File(shareCacheDir, srcFile.name)
        srcFile.copyTo(destFile, overwrite = true)
        return FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.flutter.share_provider",
            destFile,
        )
    }

    /** Пряма інтеграція Instagram Stories — публічний Intent-контракт, не потребує реєстрації розробника. */
    private fun shareInstagramStory(filePath: String): Boolean {
        return try {
            val uri = contentUriFor(filePath)
            val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
                setDataAndType(uri, "image/*")
                putExtra("source_application", applicationContext.packageName)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setPackage("com.instagram.android")
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Таргетований шер напряму у вказаний застосунок, без системного вибору. */
    private fun shareToPackage(filePath: String, packageName: String): Boolean {
        return try {
            val uri = contentUriFor(filePath)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setPackage(packageName)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
