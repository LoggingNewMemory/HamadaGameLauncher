package com.example.hamada_game_launcher

import androidx.annotation.NonNull
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import android.view.WindowManager
import android.content.pm.PackageManager
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.Bitmap
import android.graphics.Canvas
import android.content.Intent
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

// Imports for foreground detection using UsageStatsManager and for prompting usage access
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.app.AppOpsManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.hamada_game_launcher/channel"
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler()
    private var currentGamePackage: String = ""
    // Background monitoring settings: trigger as soon as one check fails (approx. 3 seconds)
    private var isMonitoring: Boolean = false
    private var exitCounter: Int = 0
    private val EXIT_THRESHOLD = 1 
    private val CHECK_INTERVAL: Long = 1000
    private val TAG = "HamadaGameLauncher"
    
    // List of whitelisted packages that should not trigger game exit
    private val whitelistedPackages = listOf(
        "com.google.android.play.games",
        "com.android.vending",
        "com.google.android.gms",
        "com.google.android.gsf.login",
        "com.google.android.gsf",
        "com.google.android.apps.auth"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Prompt user to grant usage access if not granted.
        if (!hasUsageStatsPermission()) {
            promptUsageAccessPermission()
        }

        // Keep screen on while app is running
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Make app fullscreen for immersive experience
        hideSystemUI()
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
            )
        }
    }

    // Check if the app has usage stats permission.
    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // Prompt the user to grant usage stats permission.
    private fun promptUsageAccessPermission() {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d(TAG, "Setting up method channel")
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    thread {
                        try {
                            val apps = getInstalledGames()
                            runOnUiThread { result.success(apps) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error getting installed apps", e)
                            runOnUiThread { result.error("ERROR", "Failed to get installed apps", e.message) }
                        }
                    }
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        launchApp(packageName, result)
                    } else {
                        result.error("ERROR", "Package name is null", null)
                    }
                }
                "isRoot" -> {
                    result.success(isRooted())
                }
                "areScriptsExtracted" -> {
                    result.success(areScriptsExtracted())
                }
                "extractScripts" -> {
                    try {
                        val rootPerf = call.argument<String>("rootPerf")
                        val rootBalancedPerf = call.argument<String>("rootBalancedPerf")
                        val nonRootPerf = call.argument<String>("nonRootPerf")
                        val nonRootBalancedPerf = call.argument<String>("nonRootBalancedPerf")

                        if (rootPerf != null && rootBalancedPerf != null &&
                            nonRootPerf != null && nonRootBalancedPerf != null) {
                            extractScripts(rootPerf, rootBalancedPerf, nonRootPerf, nonRootBalancedPerf)
                            result.success(true)
                        } else {
                            result.error("ERROR", "Script content missing", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error extracting scripts", e)
                        result.error("ERROR", "Failed to extract scripts", e.message)
                    }
                }
                "executeScript" -> {
                    val scriptName = call.argument<String>("scriptName")
                    if (scriptName != null) {
                        executeScript(scriptName, result)
                    } else {
                        result.error("ERROR", "Script name is null", null)
                    }
                }
                "addWhitelistedPackage" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        addToWhitelist(packageName)
                        result.success(true)
                    } else {
                        result.error("ERROR", "Package name is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.d(TAG, "Method channel setup complete")
    }

    // Add a package to the whitelist
    private fun addToWhitelist(packageName: String) {
        if (!whitelistedPackages.contains(packageName)) {
            (whitelistedPackages as MutableList).add(packageName)
            Log.d(TAG, "Added $packageName to whitelist")
        }
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    private fun launchApp(packageName: String, result: MethodChannel.Result) {
        try {
            currentGamePackage = packageName
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                // Start background monitoring immediately
                startBackgroundMonitoring()
                result.success(true)
            } else {
                result.error("APP_NOT_FOUND", "Could not find the app: $packageName", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: $packageName", e)
            result.error("LAUNCH_ERROR", "Error launching app: ${e.message}", null)
        }
    }

    // Background monitoring: checks every 3 seconds, and triggers balanced script when game is not in foreground.
    private fun startBackgroundMonitoring() {
        isMonitoring = true
        exitCounter = 0
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (!isMonitoring) return

                val foregroundPackage = getForegroundAppPackageName()
                Log.d(TAG, "Foreground package: $foregroundPackage, current game: $currentGamePackage")
                
                // Check if the foreground app is either the game or a whitelisted app
                if (foregroundPackage != null && 
                    foregroundPackage != currentGamePackage && 
                    !whitelistedPackages.contains(foregroundPackage)) {
                    exitCounter++
                    Log.d(TAG, "Non-whitelisted app in foreground. Exit counter: $exitCounter")
                    if (exitCounter >= EXIT_THRESHOLD) {
                        isMonitoring = false
                        Handler(Looper.getMainLooper()).post {
                            methodChannel.invokeMethod("onGameExited", null)
                        }
                        return
                    }
                } else {
                    // Either the game is in foreground or a whitelisted app is showing
                    exitCounter = 0
                    Log.d(TAG, "Game or whitelisted app detected, continuing monitoring")
                }
                handler.postDelayed(this, CHECK_INTERVAL)
            }
        }, CHECK_INTERVAL)
    }

    // Determines the current foreground app package using UsageStatsManager.
    private fun getForegroundAppPackageName(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()
                val appList: List<UsageStats> = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 10000, time)
                if (appList.isNullOrEmpty()) {
                    Log.w(TAG, "No usage stats available; check if permission is granted")
                    return null
                }
                val sortedList = appList.filter { it.lastTimeUsed > 0 }.sortedBy { it.lastTimeUsed }
                if (sortedList.isNotEmpty()) {
                    return sortedList.last().packageName
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting foreground app", e)
            }
        }
        return null
    }

    private fun isAppRunning(packageName: String): Boolean {
        val foregroundPackage = getForegroundAppPackageName()
        Log.d(TAG, "Comparing game package '$packageName' with foreground package '$foregroundPackage'")
        return packageName == foregroundPackage
    }

    override fun onDestroy() {
        super.onDestroy()
        isMonitoring = false
        handler.removeCallbacksAndMessages(null)
    }

    private fun isRooted(): Boolean {
        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/system/xbin/busybox",
            "/data/local/su",
            "/data/local/xbin/su",
            "/data/local/bin/su"
        )
        for (path in paths) {
            if (File(path).exists()) return true
        }
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val exitValue = process.waitFor()
            exitValue == 0
        } catch (e: Exception) {
            false
        }
    }

    private fun getInstalledGames(): List<Map<String, Any>> {
        val packageManager = packageManager
        val installedApps = ArrayList<Map<String, Any>>()
        try {
            val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledApplications(0)
            }
            for (appInfo in packages) {
                if (packageManager.getLaunchIntentForPackage(appInfo.packageName) != null) {
                    val app = HashMap<String, Any>()
                    app["packageName"] = appInfo.packageName
                    app["appName"] = packageManager.getApplicationLabel(appInfo).toString()
                    try {
                        val iconDrawable = packageManager.getApplicationIcon(appInfo.packageName)
                        val bitmap = drawableToBitmap(iconDrawable)
                        if (bitmap != null) {
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            app["icon"] = stream.toByteArray()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting icon for ${appInfo.packageName}", e)
                    }
                    installedApps.add(app)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in getInstalledGames", e)
        }
        return installedApps
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return it }
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 1
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 1
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun getScriptsDir(): File {
        val scriptsDir = File(applicationContext.filesDir, "scripts")
        if (!scriptsDir.exists()) {
            scriptsDir.mkdirs()
        }
        return scriptsDir
    }

    private fun areScriptsExtracted(): Boolean {
        val scriptsDir = getScriptsDir()
        val rootPerf = File(scriptsDir, "root_perf.sh")
        val rootBalancedPerf = File(scriptsDir, "root_balanced_perf.sh")
        val nonRootPerf = File(scriptsDir, "non_root_perf.sh")
        val nonRootBalancedPerf = File(scriptsDir, "non_root_balanced_perf.sh")
        return rootPerf.exists() && rootBalancedPerf.exists() &&
               nonRootPerf.exists() && nonRootBalancedPerf.exists()
    }

    private fun extractScripts(
        rootPerf: String,
        rootBalancedPerf: String,
        nonRootPerf: String,
        nonRootBalancedPerf: String
    ) {
        val scriptsDir = getScriptsDir()
        try {
            writeScriptToFile(File(scriptsDir, "root_perf.sh"), rootPerf)
            writeScriptToFile(File(scriptsDir, "root_balanced_perf.sh"), rootBalancedPerf)
            writeScriptToFile(File(scriptsDir, "non_root_perf.sh"), nonRootPerf)
            writeScriptToFile(File(scriptsDir, "non_root_balanced_perf.sh"), nonRootBalancedPerf)
            makeScriptsExecutable(scriptsDir)
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting scripts", e)
            throw e
        }
    }

    private fun writeScriptToFile(file: File, content: String) {
        try {
            val fos = FileOutputStream(file)
            fos.write(content.toByteArray())
            fos.close()
        } catch (e: IOException) {
            Log.e(TAG, "Error writing script to file: ${file.name}", e)
            throw e
        }
    }

    private fun makeScriptsExecutable(scriptsDir: File) {
        try {
            val scripts = scriptsDir.listFiles()
            scripts?.forEach { script ->
                if (script.name.endsWith(".sh")) {
                    script.setExecutable(true, false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error making scripts executable", e)
        }
    }

    private fun executeScript(scriptName: String, result: MethodChannel.Result) {
        thread {
            try {
                val scriptsDir = getScriptsDir()
                val scriptFile = File(scriptsDir, scriptName)
                if (!scriptFile.exists()) {
                    runOnUiThread { result.error("ERROR", "Script $scriptName does not exist", null) }
                    return@thread
                }
                Log.d(TAG, "Executing script: $scriptName")
                val isRoot = isRooted()
                val process = if (isRoot) {
                    Runtime.getRuntime().exec(arrayOf("su", "-c", "sh ${scriptFile.absolutePath}"))
                } else {
                    Runtime.getRuntime().exec(arrayOf("sh", scriptFile.absolutePath))
                }
                val exitValue = process.waitFor()
                Log.d(TAG, "Script $scriptName executed with exit value: $exitValue")
                runOnUiThread { result.success(exitValue == 0) }
            } catch (e: Exception) {
                Log.e(TAG, "Error executing script: $scriptName", e)
                runOnUiThread { result.error("ERROR", "Failed to execute script: ${e.message}", null) }
            }
        }
    }
}