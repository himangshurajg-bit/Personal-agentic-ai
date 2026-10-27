package com.myra.ultra.nativeapp

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.activity.ComponentActivity
import kotlinx.coroutines.delay


@Composable
fun LocalAudioQueueSection() {
    val context = LocalContext.current
    val lifecycle = (context as? ComponentActivity)?.lifecycle
    var queue by remember { mutableStateOf<List<LocalAudioQueueEntry>>(emptyList()) }
    val latestQueue by rememberUpdatedState(queue)
    var currentIndex by remember { mutableStateOf<Int?>(null) }
    var state by remember { mutableStateOf(LocalAudioPlaybackState.EMPTY) }
    var status by remember { mutableStateOf("Choose audio files to make a temporary local queue.") }
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }

    fun release(target: MediaPlayer?) {
        if (target == null) return
        try { target.setOnPreparedListener(null); target.setOnCompletionListener(null); target.setOnErrorListener(null); target.release() } catch (_: Exception) { }
    }
    fun playTrack(index: Int) {
        val selected = queue.getOrNull(index) ?: return
        release(player)
        player = null
        currentIndex = index
        positionMs = 0L
        durationMs = 0L
        state = LocalAudioPlaybackState.PREPARING
        status = "Preparing ${selected.title} locally…"
        val created = MediaPlayer()
        player = created
        created.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
        created.setOnPreparedListener { ready ->
            if (player === ready) {
                try {
                    durationMs = ready.duration.coerceAtLeast(0).toLong()
                    ready.start()
                    state = LocalAudioPlaybackState.PLAYING
                    status = "Playing ${selected.title} on this device."
                } catch (_: Exception) {
                    release(ready); player = null; state = LocalAudioPlaybackState.ERROR
                    status = "Android could not start this track. Choose another file."
                }
            } else release(ready)
        }
        created.setOnCompletionListener { finished ->
            if (player === finished) {
                positionMs = durationMs
                state = LocalAudioPlaybackState.COMPLETED
                status = "${selected.title} finished. Choose Next to continue the queue."
                release(finished)
                player = null
            }
        }
        created.setOnErrorListener { failed, _, _ ->
            if (player === failed) {
                release(failed); player = null; state = LocalAudioPlaybackState.ERROR
                status = "Android could not play ${selected.title}. Choose another supported file."
            }
            true
        }
        try {
            created.setDataSource(context, Uri.parse(selected.uriKey))
            created.prepareAsync()
        } catch (_: Exception) {
            release(created)
            if (player === created) player = null
            state = LocalAudioPlaybackState.ERROR
            status = "Android could not open ${selected.title}. The queue is unchanged."
        }
    }
    fun playOrResume() {
        val index = currentIndex
        if (state == LocalAudioPlaybackState.PAUSED && player != null) {
            try { player?.start(); state = LocalAudioPlaybackState.PLAYING; status = "Playback resumed." }
            catch (_: Exception) { state = LocalAudioPlaybackState.ERROR; status = "Android could not resume playback." }
        } else if (index != null && state in setOf(LocalAudioPlaybackState.READY, LocalAudioPlaybackState.COMPLETED)) {
            playTrack(index)
        } else if (index == null && queue.isNotEmpty()) playTrack(0)
    }
    fun pause() {
        val active = player ?: return
        try { active.pause(); state = LocalAudioPlaybackState.PAUSED; status = "Playback paused." }
        catch (_: Exception) { state = LocalAudioPlaybackState.ERROR; status = "Android could not pause playback." }
    }
    fun stop() {
        val active = player
        try { active?.pause(); active?.seekTo(0); positionMs = 0L }
        catch (_: Exception) { }
        release(active); player = null
        state = if (queue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
        status = if (queue.isEmpty()) "Queue is empty." else "Playback stopped. Tap Play to start this track again."
    }
    fun goNext() {
        val index = currentIndex?.let { LocalAudioQueue.nextIndex(it, queue.size) } ?: if (queue.isNotEmpty()) 0 else null
        if (index == null) status = "There is no next track in the queue." else playTrack(index)
    }
    fun goPrevious() {
        val index = currentIndex?.let { LocalAudioQueue.previousIndex(it, queue.size) } ?: if (queue.isNotEmpty()) 0 else null
        if (index == null) status = "There is no previous track in the queue." else playTrack(index)
    }
    fun clearQueue() {
        stop()
        queue = emptyList()
        currentIndex = null
        state = LocalAudioPlaybackState.EMPTY
        status = "Queue cleared. MYRA did not remove or change the files."
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isEmpty()) {
            status = "No files added."
        } else {
            val additions = uris.mapNotNull { uri ->
                val mime = try { context.contentResolver.getType(uri) } catch (_: Exception) { null } ?: return@mapNotNull null
                val title = queryAudioTitle(context, uri) ?: uri.lastPathSegment ?: "Audio file"
                LocalAudioQueueEntry(uri.toString(), title, mime)
            }
            val update = LocalAudioQueue.add(queue, additions)
            queue = update.entries
            status = when {
                update.addedCount > 0 && update.ignoredCount > 0 -> "Added ${update.addedCount} audio file(s); ignored ${update.ignoredCount} unsupported, duplicate, or over-limit item(s)."
                update.addedCount > 0 -> "Added ${update.addedCount} audio file(s). Nothing plays until you tap a track or Play."
                else -> "No supported new audio files were added. The queue stays unchanged."
            }
        }
    }

    LaunchedEffect(player, state) {
        val active = player
        if (active != null && state == LocalAudioPlaybackState.PLAYING) {
            while (player === active && state == LocalAudioPlaybackState.PLAYING) {
                try { positionMs = active.currentPosition.coerceAtLeast(0).toLong() } catch (_: Exception) { }
                delay(250)
            }
        }
    }
    DisposableEffect(lifecycle, player) {
        val observedPlayer = player
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && player != null) {
                release(player); player = null; positionMs = 0L
                state = if (latestQueue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
                status = "Playback stopped when MYRA left the foreground; the temporary queue remains until you leave Files."
            }
        }
        lifecycle?.addObserver(observer)
        onDispose {
            lifecycle?.removeObserver(observer)
            release(observedPlayer)
            if (player === observedPlayer) player = null
        }
    }

    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF211D28)), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Text("Temporary audio queue", color = Color.White, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
            Text("Select audio with Android’s file picker, then tap a track to play. Files stay local; the queue is temporary, not saved, uploaded, or playable in the background.", color = Color(0xFFB8B1C2), fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.padding(top = 4.dp))
            Text(status, color = if (state == LocalAudioPlaybackState.ERROR) Color(0xFFFFB4AB) else Color(0xFF70E1B2), fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.padding(top = 8.dp))
            Button(onClick = { picker.launch(arrayOf("audio/*")) }, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF70E1B2), contentColor = Color(0xFF111014)), modifier = Modifier.padding(top = 8.dp)) {
                Icon(Icons.Default.Add, contentDescription = null); Spacer(Modifier.width(6.dp)); Text("Add audio files")
            }
            if (durationMs > 0L && state.canSeek()) {
                Slider(value = clampLocalAudioPosition(positionMs, durationMs).toFloat(), onValueChange = { positionMs = clampLocalAudioPosition(it.toLong(), durationMs) }, onValueChangeFinished = {
                    try { player?.seekTo(positionMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()) } catch (_: Exception) { status = "Could not seek in this track." }
                }, valueRange = 0f..durationMs.toFloat(), modifier = Modifier.fillMaxWidth())
                Text("${formatLocalAudioTime(positionMs)} / ${formatLocalAudioTime(durationMs)}", color = Color(0xFFB8B1C2), fontSize = 12.sp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 6.dp)) {
                OutlinedButton(onClick = { goPrevious() }, enabled = queue.isNotEmpty()) { Icon(Icons.Default.ArrowBack, contentDescription = "Previous track") }
                Button(onClick = { playOrResume() }, enabled = state.canStartOrResume() || (currentIndex == null && queue.isNotEmpty()), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF70E1B2), contentColor = Color(0xFF111014))) { Icon(Icons.Default.PlayArrow, contentDescription = "Play") }
                OutlinedButton(onClick = { pause() }, enabled = state.canPause()) { Icon(Icons.Default.Pause, contentDescription = "Pause") }
                OutlinedButton(onClick = { stop() }, enabled = state.canStop()) { Icon(Icons.Default.Stop, contentDescription = "Stop") }
                OutlinedButton(onClick = { goNext() }, enabled = queue.isNotEmpty()) { Icon(Icons.Default.ArrowForward, contentDescription = "Next track") }
            }
            if (queue.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text("${queue.size} / ${LocalAudioQueue.MAX_ENTRIES} tracks", color = Color(0xFFB8B1C2), fontSize = 12.sp)
                LazyColumn(modifier = Modifier.fillMaxWidth().height((queue.size.coerceAtMost(5) * 48).dp)) {
                    itemsIndexed(queue, key = { _, item -> item.uriKey }) { index, item ->
                        Row(Modifier.fillMaxWidth().clickable { playTrack(index) }.padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(if (index == currentIndex) "▶ ${item.title}" else item.title, color = if (index == currentIndex) Color(0xFF70E1B2) else Color.White, maxLines = 1, modifier = Modifier.weight(1f))
                            Text(if (index == currentIndex) state.name.lowercase() else "Play", color = Color(0xFFB8B1C2), fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
                Text("Queue order follows the file picker. Add more to append; duplicate file references are ignored. Clear removes only the queue, not the files.", color = Color(0xFFB8B1C2), fontSize = 12.sp, lineHeight = 17.sp)
                OutlinedButton(onClick = { clearQueue() }) { Text("Clear queue") }
            }
        }
    }
}

private fun queryAudioTitle(context: Context, uri: Uri): String? = try {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))?.take(300) else null
    }
} catch (_: Exception) { null }
