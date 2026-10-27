package dev.personalagent.personal_assistant

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.MediaController
import android.widget.ScrollView
import android.widget.TextView
import android.widget.VideoView
import kotlin.math.sqrt

/** User-started local viewer. Media stays in Android's URI-grant boundary. */
class LocalMediaActivity : Activity() {
    companion object {
        const val EXTRA_KIND = "local_media_kind"
    }

    private var descriptor: ParcelFileDescriptor? = null
    private var renderer: PdfRenderer? = null
    private var pageBitmap: Bitmap? = null
    private var videoView: VideoView? = null
    private var pageIndex = 0
    private var pageLabel: TextView? = null
    private var previousButton: Button? = null
    private var nextButton: Button? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent.data
        val kind = intent.getStringExtra(EXTRA_KIND)
        if (uri == null || kind !in setOf("pdf", "video")) {
            showError("This local file could not be opened.")
            return
        }
        title = if (kind == "pdf") "PDF pages" else "Video player"
        try {
            if (kind == "pdf") openPdf(uri) else openVideo(uri)
        } catch (_: Exception) {
            showError(if (kind == "pdf") "This PDF could not be opened." else "This video could not be played.")
        }
    }

    private fun baseLayout(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(12), dp(16), dp(16))
        setBackgroundColor(Color.rgb(18, 20, 27))
    }

    private fun addLocalNotice(root: LinearLayout, text: String) {
        root.addView(TextView(this).apply {
            this.text = text
            setTextColor(Color.LTGRAY)
            textSize = 14f
            setPadding(0, 0, 0, dp(10))
        })
    }

    private fun openPdf(uri: Uri) {
        descriptor = contentResolver.openFileDescriptor(uri, "r")
            ?: throw IllegalStateException("No readable file handle")
        renderer = PdfRenderer(descriptor!!)
        if (renderer!!.pageCount < 1) throw IllegalStateException("PDF has no pages")

        val root = baseLayout()
        addLocalNotice(root, "Local PDF · stays on this device")
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        previousButton = Button(this).apply {
            text = "Previous"
            setOnClickListener { showPdfPage(pageIndex - 1) }
        }
        pageLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 16f
        }
        nextButton = Button(this).apply {
            text = "Next"
            setOnClickListener { showPdfPage(pageIndex + 1) }
        }
        controls.addView(previousButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(pageLabel, LinearLayout.LayoutParams(0, dp(48), 1f))
        controls.addView(nextButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        root.addView(controls)

        val image = ImageView(this).apply {
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.WHITE)
            contentDescription = "PDF page"
        }
        val pageScroll = ScrollView(this).apply {
            addView(image, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        root.addView(pageScroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
        ))
        setContentView(root)
        imageView = image
        showPdfPage(0)
    }

    private var imageView: ImageView? = null

    private fun showPdfPage(index: Int) {
        val pdf = renderer ?: return
        if (index !in 0 until pdf.pageCount) return
        val page = pdf.openPage(index)
        try {
            val maxWidth = (resources.displayMetrics.widthPixels - dp(32)).coerceAtLeast(1)
            val fitWidth = (maxWidth.toFloat() / page.width).coerceAtMost(2.5f)
            val pixelBound = sqrt(8_000_000.0 / (page.width.toDouble() * page.height)).toFloat()
            val scale = minOf(fitWidth, pixelBound)
            val width = (page.width * scale).toInt().coerceAtLeast(1)
            val height = (page.height * scale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val oldBitmap = pageBitmap
            pageBitmap = bitmap
            imageView?.setImageBitmap(bitmap)
            oldBitmap?.recycle()
            pageIndex = index
            pageLabel?.text = "${index + 1} / ${pdf.pageCount}"
            previousButton?.isEnabled = index > 0
            nextButton?.isEnabled = index < pdf.pageCount - 1
        } finally {
            page.close()
        }
    }

    private fun openVideo(uri: Uri) {
        val root = baseLayout()
        addLocalNotice(root, "Local video · stays on this device")
        val player = VideoView(this)
        videoView = player
        root.addView(player, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
        ))
        val seekControls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        seekControls.addView(Button(this).apply {
            text = "−10 sec"
            setOnClickListener { player.seekTo((player.currentPosition - 10_000).coerceAtLeast(0)) }
        })
        seekControls.addView(Button(this).apply {
            text = "+10 sec"
            setOnClickListener { player.seekTo(player.currentPosition + 10_000) }
        })
        root.addView(seekControls)
        setContentView(root)
        player.setMediaController(MediaController(this).apply { setAnchorView(player) })
        player.setVideoURI(uri)
        player.setOnPreparedListener { player.start() }
    }

    private fun showError(message: String) {
        setContentView(baseLayout().apply {
            addLocalNotice(this, message)
            addView(Button(this@LocalMediaActivity).apply {
                text = "Close"
                setOnClickListener { finish() }
            })
        })
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        videoView?.stopPlayback()
        imageView?.setImageDrawable(null)
        pageBitmap?.recycle()
        pageBitmap = null
        renderer?.close()
        renderer = null
        descriptor?.close()
        descriptor = null
        super.onDestroy()
    }
}
