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
import android.provider.OpenableColumns
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var pendingAction: Map<*, *>? = null
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null
    private var voice: SpeechRecognizer? = null
    private var voiceChannel: MethodChannel? = null
    private var voicePermission: MethodChannel.Result? = null
    private var voiceArgs: Map<*,*>? = null
    private fun voiceEvent(kind:String, value:Any? = null) { voiceChannel?.invokeMethod("voice_event",mapOf("kind" to kind,"value" to value)) }
    private fun stopVoice() { voice?.cancel();voice?.destroy();voice=null;voiceEvent("stopped") }
    private fun startVoice(args:Map<*,*>, result:MethodChannel.Result) {
        val mode=args["mode"] as? String
        val locale=args["locale"] as? String
        if(mode !in setOf("offline","online") || locale !in setOf("as-IN","en-IN")) { result.error("invalid","Unsupported speech selection",null);return }
        if(mode=="online" && args["approved_online"]!=true) {result.error("approval","Review online audio processing first",null);return}
        if(mode=="offline" && (Build.VERSION.SDK_INT<33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(this))) {result.error("unavailable","Verified on-device language recognition requires Android 13+ and an installed on-device service. No online fallback.",null);return}
        if(mode=="online" && !SpeechRecognizer.isRecognitionAvailable(this)) {result.error("unavailable","No system recognition service. Type instead.",null);return}
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) {
            if(voicePermission!=null) {result.error("busy","A microphone permission request is open",null);return}
            voicePermission=result;voiceArgs=args;requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),44);return
        }
        stopVoice()
        try {
            val recognizer=if(mode=="offline") SpeechRecognizer.createOnDeviceSpeechRecognizer(this) else SpeechRecognizer.createSpeechRecognizer(this)
            voice=recognizer
            recognizer.setRecognitionListener(object:RecognitionListener {
                override fun onReadyForSpeech(params:Bundle?) { voiceEvent("listening") }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB:Float) { voiceEvent("level",rmsdB.toDouble()) }
                override fun onBufferReceived(buffer:ByteArray?) {}
                override fun onEndOfSpeech() {voiceEvent("stopped")}
                override fun onError(error:Int) { voiceEvent("error","Speech service error $error. No fallback or automatic retry. Typing remains available.") }
                override fun onResults(results:Bundle?) { voiceEvent("text",results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "");voiceEvent("stopped") }
                override fun onPartialResults(results:Bundle?) { voiceEvent("partial",results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "") }
                override fun onEvent(eventType:Int,params:Bundle?) {}
            })
            val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {putExtra(RecognizerIntent.EXTRA_LANGUAGE,locale);putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true)}
            if(mode=="offline" && Build.VERSION.SDK_INT>=33) {
                recognizer.checkRecognitionSupport(intent,mainExecutor,object:RecognitionSupportCallback {
                    override fun onSupportResult(support:RecognitionSupport) {
                        if(voice!==recognizer) {result.error("cancelled","Speech cancelled",null);return}
                        if(!support.installedOnDeviceLanguages.any { it.replace('_','-').equals(locale,true) }) {stopVoice();result.error("unavailable","Selected on-device language is not installed. No model download or online fallback was made; type instead.",null);return}
                        try {recognizer.startListening(intent);result.success(mapOf("started" to true,"mode" to "offline"))} catch(_:Exception) {stopVoice();result.error("unavailable","On-device recognition could not start; no online fallback",null)}
                    }
                    override fun onError(error:Int) {stopVoice();result.error("unavailable","Cannot verify installed offline language ($error). Type instead; no online fallback.",null)}
                })
            } else {recognizer.startListening(intent);result.success(mapOf("started" to true,"mode" to "online"))}
        } catch(_:Exception) {stopVoice();result.error("unavailable","Speech could not start; typing remains available",null)}
    }
    override fun onPause() {stopVoice();super.onPause()}
    override fun onDestroy() {stopVoice();super.onDestroy()}
    private var fileResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        voiceChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"personal_assistant/voice")
        MethodChannel(engine.dartExecutor.binaryMessenger, "personal_assistant/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "device_status" -> result.success(mapOf(
                    "sdk" to Build.VERSION.SDK_INT,
                    "microphone_granted" to (checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED),
                    "notifications_granted" to (Build.VERSION.SDK_INT<33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED),
                    "on_device_recognizer" to (Build.VERSION.SDK_INT>=31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)),
                    "system_recognizer" to SpeechRecognizer.isRecognitionAvailable(this)
                ))
                "voice_start" -> startVoice(call.arguments as? Map<*,*> ?: emptyMap<Any,Any>(),result)
                "voice_cancel" -> {stopVoice();result.success(true)}
                "execute" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    if (args["kind"] == "reminder" && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if(permissionResult != null) { result.error("busy", "A permission request is already open", null) }
                        else { permissionResult=result; pendingAction=args; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41) }
                    } else execute(args,result)
                }
                "pick_file" -> {
                    if(fileResult != null) result.error("busy","A selection is already open",null)
                    else {
                        fileResult=result
                        try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type="*/*"; putExtra(Intent.EXTRA_MIME_TYPES,arrayOf("text/plain","text/markdown","application/json","application/pdf","image/png","image/jpeg")) },43) }
                        catch(_:Exception) { fileResult=null;result.error("unavailable","Document picker unavailable",null) }
                    }
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
        if(requestCode==44) {
            val result=voicePermission;val args=voiceArgs;voicePermission=null;voiceArgs=null
            if(result!=null && args!=null) {
                if(grantResults.isNotEmpty() && grantResults[0]==PackageManager.PERMISSION_GRANTED) startVoice(args,result)
                else result.error("denied","Microphone permission denied. No audio was processed; typing still works.",null)
            }
        }
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
        if(requestCode==43) {
            val result=fileResult;fileResult=null
            val uri=data?.data
            if(resultCode!=RESULT_OK || uri==null) {result?.error("cancelled","No file selected",null);return}
            try {
                val mime=contentResolver.getType(uri) ?: "application/octet-stream"
                var name="Selected file"
                contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use { cursor -> if(cursor.moveToFirst()) name=cursor.getString(0) ?: name }
                val response=mutableMapOf<String,Any>("name" to name.take(200),"mime" to mime)
                if(mime=="application/pdf") {response["unsupported"]="PDF selected. Extraction and PDF/image inference are not available in this build; no content was sent."}
                else {
                    val limit=if(mime.startsWith("image/")) 2000000 else 200000
                    val bytes=contentResolver.openInputStream(uri)?.use { input ->
                        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);var total=0
                        while(true) {val n=input.read(buffer);if(n<0)break;total+=n;if(total>limit)throw IllegalArgumentException("File exceeds local preview limit");out.write(buffer,0,n)}
                        out.toByteArray()
                    } ?: throw IllegalStateException("Could not read selected file")
                    if(mime in setOf("image/png","image/jpeg")) response["image_base64"]=Base64.encodeToString(bytes,Base64.NO_WRAP)
                    else if(mime.startsWith("text/") || mime=="application/json") {
                        val decoder=Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                        response["text"]=decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                    } else response["unsupported"]="This file type has no local reader in this build. No content sent."
                }
                result?.success(response)
            } catch(e:Exception) {result?.error("read_failed",e.message ?: "Could not read file",null)}
        }
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
