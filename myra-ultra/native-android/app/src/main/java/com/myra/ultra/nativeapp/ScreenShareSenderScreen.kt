package com.myra.ultra.nativeapp

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Composable
fun ScreenShareSenderScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var credentials by remember { mutableStateOf(ScreenShareCredentialStore.read(context)) }
    var serviceUrl by remember { mutableStateOf(credentials?.serviceUrl.orEmpty()) }
    var invitationJson by remember { mutableStateOf("") }
    var sessionId by remember { mutableStateOf(ScreenShareCredentialStore.readSessionId(context).orEmpty()) }
    var state by remember { mutableStateOf(if (ScreenShareProjectionService.isRunning) "active" else "") }
    var status by remember {
        mutableStateOf(
            if (credentials == null) "Paste the invitation copied from Personal AI, then pair this device."
            else "Paired securely. Personal AI still has to approve every screen-share request.",
        )
    }
    var busy by remember { mutableStateOf(false) }
    var showForgetDialog by remember { mutableStateOf(false) }

    val projectionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val currentCredentials = credentials
        val approvedSession = sessionId
        if (result.resultCode == Activity.RESULT_OK && result.data != null &&
            currentCredentials != null && ScreenShareProtocol.isValidSessionId(approvedSession)) {
            try {
                ScreenShareProjectionService.start(context, result.resultCode, result.data!!, approvedSession)
                state = "approved"
                status = "Android granted screen capture. MYRA is starting the visible foreground service; use its Stop notification at any time."
            } catch (_: Exception) {
                state = "stopped"
                status = "MYRA couldn't start screen sharing; no stream is claimed. Check the Android notification and foreground-service permissions."
                scope.launch(Dispatchers.IO) { runCatching { ScreenShareNetwork().endSession(currentCredentials, approvedSession) } }
            }
        } else {
            state = "stopped"
            status = "Android screen-capture permission was declined or canceled; no screen was shared."
            if (currentCredentials != null && ScreenShareProtocol.isValidSessionId(approvedSession)) {
                scope.launch(Dispatchers.IO) { runCatching { ScreenShareNetwork().endSession(currentCredentials, approvedSession) } }
            }
        }
    }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projectionLauncher.launch(manager.createScreenCaptureIntent())
        } else {
            status = "Allow MYRA's ongoing notification in Android to start the screen-share foreground service. No capture started."
            val currentCredentials = credentials
            val approvedSession = sessionId
            if (currentCredentials != null && ScreenShareProtocol.isValidSessionId(approvedSession)) {
                scope.launch(Dispatchers.IO) {
                    runCatching { ScreenShareNetwork().endSession(currentCredentials, approvedSession) }
                }
                state = "stopped"
            }
        }
    }

    LaunchedEffect(credentials?.pairingId, sessionId) {
        val currentCredentials = credentials ?: return@LaunchedEffect
        if (!ScreenShareProtocol.isValidSessionId(sessionId)) return@LaunchedEffect
        try {
            val current = withContext(Dispatchers.IO) {
                ScreenShareNetwork().sessionStatus(currentCredentials, sessionId)
            }
            state = current
            status = when (current) {
                "awaiting_receiver_approval" -> "Waiting for the owner to approve this exact request in Personal AI."
                "approved" -> "Personal AI approved this request. Tap Share screen to review Android's capture consent."
                "active" -> if (ScreenShareProjectionService.isRunning) "Screen sharing is active. Use the visible notification or Stop sharing here." else "The receiver reports an active session; MYRA's capture service isn't running on this device. Stop the session or request a new one."
                "stopped" -> "This screen-share session has stopped."
                "expired" -> "This request expired. Create a new request if you still want to share."
                "revoked" -> "This paired sender was revoked in Personal AI. Pair it again to continue."
                else -> "Session status: $current"
            }
        } catch (_: Exception) {
            status = "Couldn't refresh this session. The saved pairing stays on this device; check the HTTPS service address and try again."
        }
    }

    fun performPairing() {
        val invitation = try {
            ScreenShareProtocol.parseInvitation(invitationJson)
        } catch (error: Exception) {
            status = error.message ?: "Check the pairing information."
            return
        }
        val service = try {
            ScreenShareProtocol.normalizeServiceUrl(serviceUrl)
        } catch (error: Exception) {
            status = error.message ?: "Check the HTTPS address."
            return
        }
        scope.launch {
            busy = true
            status = "Pairing with Personal AI…"
            try {
                val paired = withContext(Dispatchers.IO) {
                    ScreenShareNetwork().redeemPairing(service, invitation)
                }
                withContext(Dispatchers.IO) { ScreenShareCredentialStore.save(context, paired) }
                credentials = paired
                serviceUrl = paired.serviceUrl
                invitationJson = ""
                sessionId = ""
                state = ""
                status = "Paired. Every screen-share request still needs separate approval in Personal AI."
            } catch (error: Exception) {
                status = error.message?.take(200) ?: "Couldn't pair with Personal AI. Check the HTTPS address and fresh invitation."
            } finally {
                busy = false
            }
        }
    }

    fun requestSession() {
        val saved = credentials ?: return
        if (ScreenShareProjectionService.isRunning) {
            status = "Stop the active share before requesting another one."
            return
        }
        scope.launch {
            busy = true
            status = "Sending a request to Personal AI… no pixels are captured yet."
            try {
                val createdId = withContext(Dispatchers.IO) { ScreenShareNetwork().requestSession(saved) }
                withContext(Dispatchers.IO) { ScreenShareCredentialStore.saveSessionId(context, createdId) }
                sessionId = createdId
                state = "awaiting_receiver_approval"
                status = "Request sent. Personal AI must approve this specific session before Android asks to capture your screen."
            } catch (error: Exception) {
                status = error.message?.take(200) ?: "Couldn't request a screen-share session."
            } finally {
                busy = false
            }
        }
    }

    fun refreshSession() {
        val saved = credentials ?: return
        if (!ScreenShareProtocol.isValidSessionId(sessionId)) return
        scope.launch {
            busy = true
            try {
                val updated = withContext(Dispatchers.IO) { ScreenShareNetwork().sessionStatus(saved, sessionId) }
                state = updated
                status = when (updated) {
                    "approved" -> "Personal AI approved this exact session. Tap Share screen to review Android's consent."
                    "active" -> "The receiver reports an active session. Stop locally or in Personal AI to end it."
                    "awaiting_receiver_approval" -> "Still waiting for approval in Personal AI; no screen capture has started."
                    "stopped" -> "This screen-share session has stopped."
                    "expired" -> "This request expired. Create a new one if needed."
                    "revoked" -> "The paired sender was revoked in Personal AI."
                    else -> "Session status: $updated"
                }
            } catch (error: Exception) {
                status = error.message?.take(200) ?: "Couldn't refresh session status."
            } finally {
                busy = false
            }
        }
    }

    fun askForScreenCapture() {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projectionLauncher.launch(manager.createScreenCaptureIntent())
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp)) {
        TextButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, null); Text("Back to tools", modifier = Modifier.padding(start = 6.dp)) }
        Text("PAIRED SCREEN SHARE", color = Mint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.7.sp)
        Spacer(Modifier.height(5.dp))
        Text("Share with Personal AI", color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text("MYRA only captures after you request a session, Personal AI approves it, and Android shows its own screen-capture consent. No audio is captured.", color = Muted, fontSize = 14.sp, lineHeight = 20.sp)
        Spacer(Modifier.height(14.dp))

        Card(colors = CardDefaults.cardColors(containerColor = Panel), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Connect to your receiver", color = Color.White, fontWeight = FontWeight.SemiBold)
                OutlinedTextField(
                    value = serviceUrl,
                    onValueChange = { serviceUrl = it.take(512) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Personal AI HTTPS service address") },
                    placeholder = { Text("https://your-private-service.example") },
                    singleLine = true,
                    enabled = credentials == null && !busy,
                )
                if (credentials == null) {
                    OutlinedTextField(
                        value = invitationJson,
                        onValueChange = { invitationJson = it.take(512) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Pairing invitation") },
                        placeholder = { Text("Paste the JSON copied from Personal AI") },
                        minLines = 2,
                        maxLines = 4,
                        enabled = !busy,
                    )
                    Button(onClick = ::performPairing, enabled = !busy && serviceUrl.isNotBlank() && invitationJson.isNotBlank()) {
                        if (busy) CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp), color = Color.Black, strokeWidth = 2.dp)
                        Text("Pair this device")
                    }
                    Text("Use HTTPS only. The current local development receiver is loopback-only; remote HTTPS/WSS reachability requires a configured server endpoint.", color = Muted, fontSize = 12.sp, lineHeight = 17.sp)
                } else {
                    Text("Paired with Personal AI · sender token is encrypted on this device.", color = Mint, fontSize = 13.sp)
                    if (sessionId.isNotBlank()) {
                        Text("Session: ${sessionId.take(8)}… · $state", color = Muted, fontSize = 12.sp)
                    }
                }
            }
        }

        if (credentials != null) {
            Spacer(Modifier.height(12.dp))
            Card(colors = CardDefaults.cardColors(containerColor = Panel), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Per-session approval", color = Color.White, fontWeight = FontWeight.SemiBold)
                    if (sessionId.isBlank() || state in setOf("stopped", "expired", "revoked")) {
                        Button(onClick = ::requestSession, enabled = !busy && !ScreenShareProjectionService.isRunning) {
                            Icon(Icons.Default.ScreenShare, null); Text("Request screen share", modifier = Modifier.padding(start = 8.dp))
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = ::refreshSession, enabled = !busy) { Text("Check approval") }
                            if (state == "approved" && !ScreenShareProjectionService.isRunning) {
                                Button(onClick = ::askForScreenCapture, enabled = !busy) {
                                    Icon(Icons.Default.ScreenShare, null); Text("Share screen", modifier = Modifier.padding(start = 6.dp))
                                }
                            }
                        }
                        if (state in setOf("approved", "active", "awaiting_receiver_approval") || ScreenShareProjectionService.isRunning) {
                            OutlinedButton(onClick = {
                                val saved = credentials
                                val id = sessionId
                                if (ScreenShareProjectionService.isRunning) {
                                    ScreenShareProjectionService.stop(context)
                                    state = "stopped"
                                    status = "Stop requested. MYRA closes the capture and stream; check Personal AI to confirm its final session state."
                                } else if (saved != null && ScreenShareProtocol.isValidSessionId(id)) {
                                    busy = true
                                    scope.launch {
                                        try {
                                            withContext(Dispatchers.IO) { ScreenShareNetwork().endSession(saved, id) }
                                            state = "stopped"
                                            status = "Request stopped. Personal AI will show the updated session state when refreshed."
                                        } catch (error: Exception) {
                                            status = error.message?.take(200) ?: "Couldn't stop this request; check its status in Personal AI."
                                        } finally {
                                            busy = false
                                        }
                                    }
                                }
                            }, enabled = !busy) {
                                Icon(Icons.Default.Stop, null); Text("Stop sharing", modifier = Modifier.padding(start = 6.dp))
                            }
                        }
                    }
                    Text(status, color = if (state == "active") Mint else Muted, fontSize = 13.sp, lineHeight = 18.sp)
                    Text("Android limits capture to a foreground service, a visible Stop notification, 1,280 px maximum long edge, 3 frames per second, JPEG frames in memory, and a one-hour session. Stop when finished; Personal AI can also stop the session or revoke this pairing.", color = Muted, fontSize = 12.sp, lineHeight = 17.sp)
                    TextButton(onClick = { showForgetDialog = true }, enabled = !busy && !ScreenShareProjectionService.isRunning) {
                        Icon(Icons.Default.LinkOff, null); Text("Forget pairing", modifier = Modifier.padding(start = 6.dp))
                    }
                }
            }
        } else if (status.isNotBlank()) {
            Spacer(Modifier.height(10.dp)); Text(status, color = Muted, fontSize = 13.sp, lineHeight = 18.sp)
        }
    }

    if (showForgetDialog) {
        AlertDialog(
            onDismissRequest = { showForgetDialog = false },
            title = { Text("Forget this pairing?") },
            text = { Text("This removes MYRA's local sender token. It doesn't revoke the receiver-side pairing; use Personal AI's Revoke control to invalidate it there.") },
            confirmButton = {
                TextButton(onClick = {
                    val previous = credentials
                    credentials = null
                    serviceUrl = previous?.serviceUrl.orEmpty()
                    sessionId = ""
                    state = ""
                    invitationJson = ""
                    status = "Local pairing removed. Revoke the sender in Personal AI too if you want to invalidate it on the receiver."
                    scope.launch(Dispatchers.IO) { ScreenShareCredentialStore.forget(context) }
                    showForgetDialog = false
                }) { Text("Forget locally") }
            },
            dismissButton = { TextButton(onClick = { showForgetDialog = false }) { Text("Cancel") } },
        )
    }
}

private val Mint = Color(0xFF66E3CF)
private val Muted = Color(0xFF9AA8B9)
private val Panel = Color(0xFF151B25)
