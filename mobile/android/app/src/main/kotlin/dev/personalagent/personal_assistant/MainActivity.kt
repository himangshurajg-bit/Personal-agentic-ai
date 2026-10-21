package dev.personalagent.personal_assistant

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var pendingAction: Map<*, *>? = null
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "execute" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    if (args["kind"] == "reminder" && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if(permissionResult != null) { result.error("busy", "A permission request is already open", null) }
                        else { permissionResult=result; pendingAction=args; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41) }
                    } else execute(args,result)
                }
                "export" -> {
                    if(exportResult != null) { result.error("busy","An export is already open",null) }
                    else {
                        exportText=call.argument<String>("text"); exportResult=result
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="application/json"; putExtra(Intent.EXTRA_TITLE,"personal-memories.json") },42) }
                        catch(_:Exception) { exportResult=null; exportText=null; result.error("unavailable","No document picker is available",null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun execute(args:Map<*, *>,result:MethodChannel.Result) {
        try {
            when(args["kind"]) {
                "open_app" -> {
                    val packageName=args["package"] as? String
                    if(packageName !in setOf("com.android.settings","com.android.chrome","com.google.android.youtube","com.google.android.calculator")) throw IllegalArgumentException("Unsupported app")
                    val launch=packageManager.getLaunchIntentForPackage(packageName!!) ?: throw IllegalStateException("That app is not installed or cannot be opened")
                    startActivity(launch)
                    result.success(mapOf("result" to "opened","detail" to "Android accepted the app launch request. Its screen was not independently checked."))
                }
                "reminder" -> {
                    val title=(args["title"] as? String)?.trim() ?: ""
                    val at=(args["at_ms"] as? Number)?.toLong() ?: 0L
                    val now=System.currentTimeMillis()
                    if(title.isEmpty() || title.length>120 || at<now+1000 || at>now+366L*86400000L) throw IllegalArgumentException("Reminder title or time is invalid")
                    if(Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) {
                        result.success(mapOf("result" to "denied","detail" to "Notification permission denied; no reminder was scheduled.")); return
                    }
                    val prefs=getSharedPreferences("reminders",MODE_PRIVATE)
                    val id=prefs.getInt("next",100)+1
                    // Persist first: never report storage failure after scheduling an alarm.
                    if(!prefs.edit().putInt("next",id).putString("r$id",JSONObject().put("title",title).put("at",at).toString()).commit()) throw IllegalStateException("Could not persist reminder; no schedule was requested")
                    try { ReminderReceiver.schedule(this,id,title,at) }
                    catch(e:Exception) { prefs.edit().remove("r$id").commit(); result.success(mapOf("result" to "unknown","detail" to "Android scheduling did not return successfully; outcome is unverified. Do not repeat blindly.")); return }
                    result.success(mapOf("result" to "scheduled","detail" to "Android accepted the reminder schedule. Delivery is approximate and may be delayed by battery restrictions."))
                }
                else -> throw IllegalArgumentException("Unsupported action")
            }
        } catch(e:Exception) { result.success(mapOf("result" to "failed","detail" to (e.message ?: "Action failed; outcome not verified").take(300))) }
    }
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(requestCode==41) {
            val result=permissionResult; val args=pendingAction; permissionResult=null; pendingAction=null
            if(result!=null && args!=null) {
                if(grantResults.isNotEmpty() && grantResults[0]==PackageManager.PERMISSION_GRANTED) execute(args,result)
                else result.success(mapOf("result" to "denied","detail" to "Notification permission denied; no reminder was scheduled."))
            }
        }
    }
    @Deprecated("Android activity result bridge for Flutter document export")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode==42) {
            val result=exportResult; val text=exportText; exportResult=null; exportText=null
            if(resultCode!=RESULT_OK || data?.data==null || text==null) { result?.error("cancelled","Export cancelled; no file saved",null); return }
            try { contentResolver.openOutputStream(data.data!!,"wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)); it.flush() } ?: throw IllegalStateException("Could not open destination")
                result?.success(mapOf("saved" to true))
            } catch(_:Exception) { result?.error("write_failed","Memory export could not be saved",null) }
        }
    }
}
class ReminderReceiver : BroadcastReceiver() {
    companion object {
        fun schedule(context:Context,id:Int,title:String,at:Long) {
            val intent=Intent(context,ReminderReceiver::class.java).putExtra("id",id).putExtra("title",title)
            val pending=PendingIntent.getBroadcast(context,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val alarms=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending)
        }
    }
    override fun onReceive(context:Context,intent:Intent) {
        val prefs=context.getSharedPreferences("reminders",Context.MODE_PRIVATE)
        if(intent.action==Intent.ACTION_BOOT_COMPLETED) {
            prefs.all.filterKeys { it.startsWith("r") }.forEach { (key,value) ->
                try { val obj=JSONObject(value as String); val at=obj.getLong("at"); if(at>System.currentTimeMillis()) schedule(context,key.drop(1).toInt(),obj.getString("title"),at) else prefs.edit().remove(key).apply() } catch(_:Exception) { /* malformed saved reminder is not executed */ }
            }
            return
        }
        val id=intent.getIntExtra("id",0)
        val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("reminders","Your reminders",NotificationManager.IMPORTANCE_DEFAULT))
        if(Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) {
            val open=PendingIntent.getActivity(context,id,Intent(context,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification=android.app.Notification.Builder(context,"reminders").setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Your reminder").setContentText(intent.getStringExtra("title") ?: "Reminder").setContentIntent(open).setAutoCancel(true).build()
            manager.notify(id,notification)
        }
        prefs.edit().remove("r$id").apply()
    }
}
