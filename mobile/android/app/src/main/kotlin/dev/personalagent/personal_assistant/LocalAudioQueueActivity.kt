package dev.personalagent.personal_assistant

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.webkit.MimeTypeMap
import java.util.Locale

/** A temporary, user-picked audio queue. It never scans or uploads device files. */
class LocalAudioQueueActivity : Activity() {
    companion object {
        const val EXTRA_URIS = "local_audio_queue_uris"
        const val EXTRA_IGNORED_COUNT = "local_audio_ignored_count"
        private const val REQUEST_ADD_AUDIO = 102
    }

    private val queue = mutableListOf<LocalAudioQueueEntry>()
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var state = LocalAudioPlaybackState.EMPTY
    private var currentIndex = -1
    private var durationMs = 0L
    private var positionMs = 0L
    private var scrubbing = false
    private var statusView: TextView? = null
    private var countView: TextView? = null
    private var timeView: TextView? = null
    private var seekBar: SeekBar? = null
    private var playButton: Button? = null
    private var pauseButton: Button? = null
    private var stopButton: Button? = null
    private var previousButton: Button? = null
    private var nextButton: Button? = null
    private var trackList: LinearLayout? = null
    private var initialIgnoredCount = 0

    private val progressTicker = object : Runnable {
        override fun run() {
            val active = player
            if (state == LocalAudioPlaybackState.PLAYING && active != null) {
                positionMs = active.currentPosition.toLong().coerceAtLeast(0L)
                updateProgressUi()
                handler.postDelayed(this, 250L)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "Local audio queue"
        initialIgnoredCount = intent.getIntExtra(EXTRA_IGNORED_COUNT, 0).coerceAtLeast(0)
        val incoming = intent.getStringArrayListExtra(EXTRA_URIS)
            .orEmpty()
            .mapIndexedNotNull { index, value -> entryFor(Uri.parse(value), index) }
        queue += LocalAudioQueue.add(emptyList(), incoming).entries
        state = if (queue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
        setContentView(buildScreen())
        statusView?.text = when {
            queue.isEmpty() && initialIgnoredCount > 0 -> "No supported audio files were selected; skipped $initialIgnoredCount unsupported, duplicate, or over-limit item(s)."
            queue.isEmpty() -> "No supported audio files were selected."
            initialIgnoredCount > 0 -> "Skipped $initialIgnoredCount unsupported, duplicate, or over-limit item(s)."
            else -> ""
        }
        renderQueue()
        updatePlayerUi()
    }

    private fun buildScreen(): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(16))
            setBackgroundColor(Color.rgb(18, 20, 27))
        }
        root.addView(TextView(this).apply {
            text = "Local audio · files stay on this device"
            setTextColor(Color.LTGRAY)
            textSize = 14f
            setPadding(0, 0, 0, dp(12))
        })
        root.addView(Button(this).apply {
            text = "Add audio files"
            setOnClickListener { openAudioPicker() }
        })
        statusView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            setPadding(0, dp(8), 0, dp(4))
        }
        root.addView(statusView)
        countView = TextView(this).apply {
            setTextColor(Color.LTGRAY)
            textSize = 13f
            setPadding(0, 0, 0, dp(4))
        }
        root.addView(countView)

        seekBar = SeekBar(this).apply {
            max = 1
            isEnabled = false
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        positionMs = progress.toLong()
                        updateTimeLabel()
                    }
                }
                override fun onStartTrackingTouch(bar: SeekBar?) { scrubbing = true }
                override fun onStopTrackingTouch(bar: SeekBar?) {
                    scrubbing = false
                    val active = player
                    if (active != null && state in setOf(LocalAudioPlaybackState.PLAYING, LocalAudioPlaybackState.PAUSED)) {
                        runCatching { active.seekTo((bar?.progress ?: 0).coerceAtLeast(0)) }
                    }
                }
            })
        }
        root.addView(seekBar)
        timeView = TextView(this).apply {
            setTextColor(Color.LTGRAY)
            textSize = 12f
            gravity = Gravity.END
        }
        root.addView(timeView)

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        previousButton = Button(this).apply {
            text = "Previous"
            setOnClickListener { playAdjacent(previous = true) }
        }
        playButton = Button(this).apply {
            text = "Play"
            setOnClickListener { startOrResume() }
        }
        pauseButton = Button(this).apply {
            text = "Pause"
            setOnClickListener { pausePlayback() }
        }
        stopButton = Button(this).apply {
            text = "Stop"
            setOnClickListener { stopPlayback() }
        }
        nextButton = Button(this).apply {
            text = "Next"
            setOnClickListener { playAdjacent(previous = false) }
        }
        controls.addView(previousButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(playButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(pauseButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(stopButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(nextButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        root.addView(controls)
        root.addView(Button(this).apply {
            text = "Clear queue"
            setOnClickListener { clearQueue() }
        })

        trackList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val scroll = ScrollView(this).apply {
            addView(trackList, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        root.addView(scroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
        ))
        return root
    }

    private fun openAudioPicker() {
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }, REQUEST_ADD_AUDIO)
        } catch (_: Exception) {
            showError("Android could not open the audio file picker.")
        }
    }

    @Deprecated("Android document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_ADD_AUDIO) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            statusView?.text = "No additional files selected."
            return
        }
        val selected = linkedSetOf<Uri>()
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let(selected::add)
        }
        data.data?.let(selected::add)
        val incoming = selected.mapIndexedNotNull { index, uri -> entryFor(uri, index) }
        val update = LocalAudioQueue.add(queue, incoming)
        val skippedCount = selected.size - incoming.size + update.ignoredCount
        queue.clear()
        queue.addAll(update.entries)
        if (currentIndex >= queue.size) currentIndex = queue.lastIndex
        state = if (queue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
        statusView?.text = when {
            update.addedCount == 0 && skippedCount > 0 -> "No new files added; skipped $skippedCount unsupported, duplicate, or over-limit item(s)."
            update.addedCount == 0 -> "No new supported audio files were added."
            skippedCount > 0 -> "Added ${update.addedCount}; skipped $skippedCount unsupported, duplicate, or over-limit item(s)."
            else -> "Added ${update.addedCount} audio file${if (update.addedCount == 1) "" else "s"}."
        }
        renderQueue()
        updatePlayerUi()
    }

    private fun entryFor(uri: Uri, index: Int): LocalAudioQueueEntry? {
        val mime = contentResolver.getType(uri)?.lowercase(Locale.ROOT)
            ?: uri.lastPathSegment?.substringAfterLast('.', "")?.let {
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase(Locale.ROOT))
            }?.lowercase(Locale.ROOT)
            ?: return null
        if (!mime.startsWith("audio/")) return null
        val title = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()?.takeIf { it.isNotBlank() } ?: "Audio file ${index + 1}"
        return LocalAudioQueueEntry(uri.toString(), title, mime)
    }

    private fun renderQueue() {
        val list = trackList ?: return
        list.removeAllViews()
        queue.forEachIndexed { index, entry ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val label = TextView(this).apply {
                text = "${index + 1}. ${entry.title}".take(LocalAudioQueue.MAX_TITLE_CHARS + 8)
                setTextColor(Color.WHITE)
                textSize = 14f
                setPadding(0, dp(6), dp(8), dp(6))
                isSelected = index == currentIndex
                contentDescription = "${if (index == currentIndex) "Selected" else ""} ${index + 1}. ${entry.title}"
            }
            row.addView(label, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Button(this).apply {
                text = "Play"
                setOnClickListener { playTrack(index) }
            })
            list.addView(row)
        }
        countView?.text = "${queue.size} / ${LocalAudioQueue.MAX_ENTRIES} files in this temporary queue"
        updatePlayerUi()
    }

    private fun playTrack(index: Int) {
        if (index !in queue.indices) return
        releasePlayer()
        currentIndex = index
        durationMs = 0L
        positionMs = 0L
        state = LocalAudioPlaybackState.PREPARING
        updatePlayerUi()
        val audioPlayer = MediaPlayer()
        player = audioPlayer
        audioPlayer.setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build())
        audioPlayer.setOnPreparedListener { prepared ->
            if (player !== prepared || isFinishing) return@setOnPreparedListener
            durationMs = prepared.duration.coerceAtLeast(0).toLong()
            prepared.start()
            state = LocalAudioPlaybackState.PLAYING
            statusView?.text = "Playing ${queue.getOrNull(currentIndex)?.title ?: "audio"}. Playback stops when this screen closes."
            updatePlayerUi()
            handler.removeCallbacks(progressTicker)
            handler.post(progressTicker)
        }
        audioPlayer.setOnCompletionListener { completed ->
            if (player !== completed) return@setOnCompletionListener
            positionMs = durationMs
            releasePlayer()
            state = LocalAudioPlaybackState.COMPLETED
            statusView?.text = "Finished ${queue.getOrNull(currentIndex)?.title ?: "audio"}. Tap Play to replay."
            updatePlayerUi()
        }
        audioPlayer.setOnErrorListener { failed, _, _ ->
            if (player === failed) {
                releasePlayer()
                state = LocalAudioPlaybackState.ERROR
                statusView?.text = "This audio file could not be played. Choose another track or try again."
                updatePlayerUi()
            }
            true
        }
        try {
            audioPlayer.setDataSource(this, Uri.parse(queue[index].uriKey))
            audioPlayer.prepareAsync()
        } catch (_: Exception) {
            releasePlayer()
            state = LocalAudioPlaybackState.ERROR
            statusView?.text = "This audio file could not be opened."
            updatePlayerUi()
        }
    }

    private fun startOrResume() {
        when (state) {
            LocalAudioPlaybackState.PLAYING, LocalAudioPlaybackState.PREPARING -> return
            LocalAudioPlaybackState.PAUSED -> {
                val active = player ?: return playTrack(currentIndex)
                runCatching { active.start() }.onFailure {
                    state = LocalAudioPlaybackState.ERROR
                    releasePlayer()
                    updatePlayerUi()
                    return
                }
                state = LocalAudioPlaybackState.PLAYING
                statusView?.text = "Playing ${queue.getOrNull(currentIndex)?.title ?: "audio"}. Playback stops when this screen closes."
                handler.removeCallbacks(progressTicker)
                handler.post(progressTicker)
                updatePlayerUi()
            }
            LocalAudioPlaybackState.READY, LocalAudioPlaybackState.COMPLETED, LocalAudioPlaybackState.ERROR -> {
                val index = currentIndex.takeIf { it in queue.indices } ?: 0
                playTrack(index)
            }
            LocalAudioPlaybackState.EMPTY -> showError("Add an audio file before playing.")
        }
    }

    private fun pausePlayback() {
        val active = player ?: return
        if (!state.canPause()) return
        runCatching { active.pause() }.onFailure { return }
        positionMs = active.currentPosition.coerceAtLeast(0).toLong()
        state = LocalAudioPlaybackState.PAUSED
        handler.removeCallbacks(progressTicker)
        statusView?.text = "Paused ${queue.getOrNull(currentIndex)?.title ?: "audio"}."
        updatePlayerUi()
    }

    private fun stopPlayback() {
        if (!state.canStop()) return
        releasePlayer()
        positionMs = 0L
        durationMs = 0L
        state = if (queue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
        statusView?.text = "Playback stopped. Your selected files are unchanged."
        updatePlayerUi()
    }

    private fun playAdjacent(previous: Boolean) {
        val next = if (previous) LocalAudioQueue.previousIndex(currentIndex, queue.size)
        else LocalAudioQueue.nextIndex(currentIndex, queue.size)
        if (next != null) playTrack(next) else if (currentIndex == -1 && queue.isNotEmpty()) playTrack(0)
    }

    private fun clearQueue() {
        releasePlayer()
        queue.clear()
        currentIndex = -1
        durationMs = 0L
        positionMs = 0L
        state = LocalAudioPlaybackState.EMPTY
        statusView?.text = "Queue cleared. The original files were not changed."
        renderQueue()
        updatePlayerUi()
    }

    private fun releasePlayer() {
        handler.removeCallbacks(progressTicker)
        val active = player
        player = null
        if (active != null) {
            runCatching { active.setOnPreparedListener(null) }
            runCatching { active.setOnCompletionListener(null) }
            runCatching { active.setOnErrorListener(null) }
            runCatching { active.release() }
        }
    }

    private fun updatePlayerUi() {
        if (queue.isEmpty()) {
            if (state != LocalAudioPlaybackState.EMPTY) state = LocalAudioPlaybackState.EMPTY
        }
        val selected = queue.getOrNull(currentIndex)
        if (statusView?.text.isNullOrBlank()) {
            statusView?.text = if (selected == null) {
                "Select a track and tap Play. Playback stays in the foreground."
            } else {
                "Selected ${selected.title}. Tap Play to start."
            }
        }
        playButton?.isEnabled = queue.isNotEmpty() && state !in setOf(LocalAudioPlaybackState.PLAYING, LocalAudioPlaybackState.PREPARING)
        playButton?.text = if (state == LocalAudioPlaybackState.PAUSED) "Resume" else "Play"
        pauseButton?.isEnabled = state.canPause()
        stopButton?.isEnabled = state.canStop()
        previousButton?.isEnabled = currentIndex > 0 && queue.isNotEmpty()
        nextButton?.isEnabled = currentIndex in 0 until queue.lastIndex
        seekBar?.isEnabled = durationMs > 0L && state in setOf(LocalAudioPlaybackState.PLAYING, LocalAudioPlaybackState.PAUSED)
        updateProgressUi()
    }

    private fun updateProgressUi() {
        val duration = durationMs.coerceAtLeast(0L)
        val position = LocalAudioQueue.clampPosition(positionMs, duration)
        if (!scrubbing) {
            seekBar?.max = duration.coerceAtMost(Int.MAX_VALUE.toLong()).toInt().coerceAtLeast(1)
            seekBar?.progress = position.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }
        updateTimeLabel()
    }

    private fun updateTimeLabel() {
        timeView?.text = "${formatTime(positionMs)} / ${formatTime(durationMs)}"
    }

    private fun formatTime(milliseconds: Long): String {
        val totalSeconds = milliseconds.coerceAtLeast(0L) / 1000L
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L
        return String.format(Locale.ROOT, "%d:%02d", minutes, seconds)
    }

    private fun showError(message: String) {
        statusView?.text = message
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onStop() {
        if (state == LocalAudioPlaybackState.PLAYING || state == LocalAudioPlaybackState.PAUSED || state == LocalAudioPlaybackState.PREPARING) {
            releasePlayer()
            positionMs = 0L
            durationMs = 0L
            state = if (queue.isEmpty()) LocalAudioPlaybackState.EMPTY else LocalAudioPlaybackState.READY
            statusView?.text = "Playback stopped when the audio screen went out of view."
            updatePlayerUi()
        }
        super.onStop()
    }

    override fun onDestroy() {
        releasePlayer()
        queue.clear()
        super.onDestroy()
    }
}
