package com.example.hamada_game_launcher

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class AppListMethodHandler(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private val TAG = "AppListMethodHandler"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Method called: ${call.method}")
        
        when (call.method) {
            "isRoot" -> {
                // Implementation for checking root status
                Log.d(TAG, "Checking root status")
                // Check for root by looking for su binary
                val rootAvailable = checkForRoot()
                result.success(rootAvailable)
            }
            "executeScript" -> {
                val script = call.argument<String>("script")
                Log.d(TAG, "Executing script: $script")
                try {
                    executePerformanceScript(script ?: "")
                    result.success(null)
                } catch (e: Exception) {
                    Log.e(TAG, "Error executing script", e)
                    result.error("SCRIPT_ERROR", e.message, null)
                }
            }
            "getInstalledApps" -> {
                Log.d(TAG, "Getting installed apps")
                try {
                    val apps = getInstalledApplications()
                    Log.d(TAG, "Found ${apps.size} installed apps")
                    result.success(apps)
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting installed apps", e)
                    result.error("GET_APPS_ERROR", e.message, null)
                }
            }
            "launchApp" -> {
                val packageName = call.argument<String>("packageName")
                Log.d(TAG, "Launching app: $packageName")
                
                if (packageName != null) {
                    try {
                        launchApplication(packageName)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error launching app", e)
                        result.error("LAUNCH_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_PACKAGE", "Package name is null", null)
                }
            }
            else -> {
                Log.d(TAG, "Method not implemented: ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun checkForRoot(): Boolean {
        // Common locations for the su binary
        val locations = arrayOf("/system/bin/", "/system/xbin/", "/sbin/", "/su/bin/", "/data/local/xbin/", "/data/local/bin/", "/system/sd/xbin/", "/system/bin/failsafe/", "/data/local/")
        
        for (location in locations) {
            if (File(location + "su").exists()) {
                return true
            }
        }
        
        return false
    }
    
    private fun executePerformanceScript(scriptName: String) {
        // In a real implementation, you would execute the appropriate performance script
        // For now, we'll just log what script would be executed
        when (scriptName) {
            "root_perf.sh" -> {
                Log.d(TAG, "Would execute root performance optimizations")
                // Example: Execute shell commands for high performance settings with root
            }
            "non_root_perf.sh" -> {
                Log.d(TAG, "Would execute non-root performance optimizations")
                // Example: Set device to performance mode without root
            }
            "root_balanced_perf.sh" -> {
                Log.d(TAG, "Would restore balanced settings with root")
                // Example: Restore normal device settings with root
            }
            "non_root_balanced_perf.sh" -> {
                Log.d(TAG, "Would restore balanced settings without root")
                // Example: Restore normal device settings without root
            }
            else -> {
                Log.d(TAG, "Unknown script: $scriptName")
            }
        }
    }

    private fun getInstalledApplications(): List<Map<String, Any>> {
        val packageManager = activity.packageManager
        val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        
        return installedApps
            .filter { 
                // Filter to only include apps with LAUNCHER category
                val launchIntent = packageManager.getLaunchIntentForPackage(it.packageName)
                launchIntent != null && isGameOrEntertainmentApp(it, packageManager)
            }
            .map { app ->
                try {
                    val appInfo = packageManager.getApplicationInfo(app.packageName, 0)
                    val appName = packageManager.getApplicationLabel(appInfo).toString()
                    val appIcon = packageManager.getApplicationIcon(app.packageName)
                    
                    val iconBytes = drawableToByteArray(appIcon)
                    
                    mapOf(
                        "packageName" to app.packageName,
                        "appName" to appName,
                        "icon" to iconBytes
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing app ${app.packageName}", e)
                    mapOf(
                        "packageName" to app.packageName,
                        "appName" to app.packageName,
                        "icon" to ByteArray(0)
                    )
                }
            }
    }
    
    private fun isGameOrEntertainmentApp(app: ApplicationInfo, packageManager: PackageManager): Boolean {
        // Try to determine if the app is a game based on its category
        try {
            // Check if app is flagged as a game by the system
            if ((app.flags and ApplicationInfo.FLAG_IS_GAME) != 0) {
                return true
            }
            
            // Check the application category on Android 8.0+
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val category = app.category
                if (category == ApplicationInfo.CATEGORY_GAME) {
                    return true
                }
            }
            
            // For game launcher, we might want to include other apps too
            // Check if app name contains game-related terms
            val appName = packageManager.getApplicationLabel(app).toString().toLowerCase()
            val gameTerms = arrayOf("game", "play", "arcade", "race", "shooter", "rpg", "adventure")
            for (term in gameTerms) {
                if (appName.contains(term)) {
                    return true
                }
            }
            
            // Include popular game packages
            val gamePackagePrefixes = arrayOf(
                "com.gameloft", "com.ea.", "com.ubisoft", "com.activision", 
                "com.supercell", "com.rovio", "com.king", "com.nintendo",
                "com.sega", "com.mojang", "com.blizzard", "com.epicgames"
            )
            for (prefix in gamePackagePrefixes) {
                if (app.packageName.startsWith(prefix)) {
                    return true
                }
            }
            
            // For this game launcher app, we'll include all apps by default
            // Change this logic if you only want to show games
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error determining if app is a game", e)
            return true // Include by default on error
        }
    }
    
    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        try {
            // Ensure consistent icon size to improve grid display
            val iconSize = 128
            val bitmap = Bitmap.createBitmap(iconSize, iconSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            
            // Calculate scale to fit the icon properly
            val width = drawable.intrinsicWidth
            val height = drawable.intrinsicHeight
            
            if (width > 0 && height > 0) {
                val scale = Math.min(iconSize.toFloat() / width, iconSize.toFloat() / height)
                val scaledWidth = (width * scale).toInt()
                val scaledHeight = (height * scale).toInt()
                
                // Center the icon
                val left = (iconSize - scaledWidth) / 2
                val top = (iconSize - scaledHeight) / 2
                
                drawable.setBounds(left, top, left + scaledWidth, top + scaledHeight)
            } else {
                drawable.setBounds(0, 0, iconSize, iconSize)
            }
            
            drawable.draw(canvas)
            
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
            return stream.toByteArray()
        } catch (e: Exception) {
            Log.e(TAG, "Error converting drawable to byte array", e)
            return ByteArray(0)
        }
    }
    
    private fun launchApplication(packageName: String) {
        val intent = activity.packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } else {
            throw Exception("No launch intent found for package $packageName")
        }
    }
}