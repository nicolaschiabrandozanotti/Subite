package com.example.bondi_app

import android.Manifest
import android.app.Notification
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val permissionCode = 840
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bondi/device").setMethodCallHandler { call, result ->
            if (call.method == "wifi") {
                val connectivity = getSystemService(android.net.ConnectivityManager::class.java)
                val network = connectivity.activeNetwork
                val capabilities = connectivity.getNetworkCapabilities(network)
                result.success(capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true)
            } else if (call.method == "lightMode") {
                val manager = getSystemService(ActivityManager::class.java)
                val memory = ActivityManager.MemoryInfo()
                manager.getMemoryInfo(memory)
                result.success(manager.isLowRamDevice || memory.totalMem <= 3L * 1024 * 1024 * 1024)
            } else { result.notImplemented() }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bondi/notifications").setMethodCallHandler { call, result ->
            val manager = getSystemService(NotificationManager::class.java)
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.error("busy", "Ya hay una solicitud de permiso pendiente", null) }
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionCode) }
                    } else { result.success(manager.areNotificationsEnabled()) }
                }
                "show" -> {
                    if (!manager.areNotificationsEnabled()) { result.error("disabled", "Notificaciones deshabilitadas", null) }
                    else {
                        val channelId = "bondi_bajada"
                        if (Build.VERSION.SDK_INT >= 26) {
                            val channel = NotificationChannel(channelId, "Avisos de bajada", NotificationManager.IMPORTANCE_HIGH)
                            channel.description = "Cercanía al punto de bajada elegido"
                            channel.enableVibration(true)
                            manager.createNotificationChannel(channel)
                        }
                        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        val pending = PendingIntent.getActivity(this, 20, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
                        val notification = builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                            .setContentTitle(call.argument<String>("title"))
                            .setContentText(call.argument<String>("body"))
                            .setStyle(Notification.BigTextStyle().bigText(call.argument<String>("body")))
                            .setAutoCancel(true).setContentIntent(pending)
                            .setDefaults(Notification.DEFAULT_ALL).build()
                        manager.notify(20, notification)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
