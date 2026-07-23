package com.nepogano.app

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shareChannelName = "nepogano/social_share"
    private val referrerChannelName = "nepogano/install_referrer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName).setMethodCallHandler { call, result ->
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, referrerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getJoinCode" -> fetchInstallReferrerJoinCode(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Читає Play Install Referrer — рядок, з яким людину направили в Play
     * Маркет (join_code=<code>, дописаний на сторінці nepogano.app/join),
     * і дістає звідти код запрошення. Дозволяє показати підтвердження
     * "X хоче додати тебе другом" одразу після першого запуску, навіть якщо
     * застосунку не було на момент переходу по лінку (deferred deep link).
     */
    private fun fetchInstallReferrerJoinCode(result: MethodChannel.Result) {
        var finished = false
        val referrerClient = InstallReferrerClient.newBuilder(applicationContext).build()
        referrerClient.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                if (finished) return
                finished = true
                val code = if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                    try {
                        val referrerUrl = referrerClient.installReferrer.installReferrer
                        referrerUrl
                            .split("&")
                            .map { it.split("=") }
                            .firstOrNull { it.size == 2 && it[0] == "join_code" }
                            ?.get(1)
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    null
                }
                result.success(code)
                try {
                    referrerClient.endConnection()
                } catch (e: Exception) {
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                if (finished) return
                finished = true
                result.success(null)
            }
        })
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
