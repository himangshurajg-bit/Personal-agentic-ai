package com.myra.ultra.nativeapp

import android.graphics.Color as AndroidColor
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts

internal data class WebForgeProject(val id: String, val name: String, val updatedAt: Long)
internal data class WebForgeFiles(val html: String, val css: String, val js: String)
internal data class WebForgeCoderContext(
    val previewText: String,
    val attachedPaths: List<String>,
    val warnings: List<String>,
)
internal data class WebForgeCoderPatchRequest(val targetPath: String, val task: String, val before: String, val beforeSha256: String, val requestText: String)
internal data class WebForgeCoderPatch(val targetPath: String, val before: String, val after: String, val beforeSha256: String = WebForgeRepository.sha256(before))
internal data class WebForgeCoderUndoResult(val targetPath: String, val content: String, val restored: Boolean)

/** A small offline project manager modeled on Website Builder's write_files/project listing contract. */
internal class WebForgeRepository(private val root: File) {
    companion object {
        const val MAX_PROJECTS = 100
        const val MAX_FILE_CHARS = 200_000
        const val MAX_PROJECT_FILES = 500
        const val MAX_CODER_CONTEXT_FILES = 5
        const val MAX_CODER_CONTEXT_CHARS = 120_000
        const val MAX_REVIEWED_PATCH_CHARS = 20_000
        const val MAX_CODER_TODOS = 100
        const val MAX_CODER_TODO_CHARS = 500
        private const val CODER_TODOS_FILE = ".myra-coder/todos-v1.tsv"

        fun sha256(content: String): String = MessageDigest.getInstance("SHA-256")
            .digest(content.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
        const val MAX_EXPORT_FILE_BYTES = 10L * 1024 * 1024
        const val MAX_EXPORT_TOTAL_BYTES = 20L * 1024 * 1024
        private const val PROJECT_METADATA_FILE = "project-name.txt"
        private const val CODER_GUIDE_FILE = "MYRA_CODER.md"
        private val PROJECT_NAME = Regex("[A-Za-z0-9][A-Za-z0-9 _-]{0,39}")
        private val PROJECT_ID = Regex("[a-z0-9]+(?:-[a-z0-9]+)*")

        fun projectId(name: String): String? {
            if (!PROJECT_NAME.matches(name.trim())) return null
            return name.trim().lowercase(Locale.ROOT).replace(Regex("[ _]+"), "-").replace(Regex("-+"), "-")
        }

        fun previewHtml(files: WebForgeFiles): String {
            val csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data: blob:; media-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; font-src data:; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'\">"
            val html = if (Regex("<html\\b", RegexOption.IGNORE_CASE).containsMatchIn(files.html)) files.html
                else "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body>${files.html}</body></html>"
            val withHead = if (Regex("<head\\b", RegexOption.IGNORE_CASE).containsMatchIn(html)) html
                else html.replaceFirst(Regex("<html([^>]*)>", RegexOption.IGNORE_CASE), "<html$1><head><meta charset=\"utf-8\"></head>")
            val protected = withHead.replaceFirst(Regex("<head([^>]*)>", RegexOption.IGNORE_CASE), "<head$1>$csp")
            val styled = protected.replaceFirst(Regex("</head\\s*>", RegexOption.IGNORE_CASE), "<style>${files.css}</style></head>")
            return styled.replaceFirst(Regex("</body\\s*>", RegexOption.IGNORE_CASE), "<script>${files.js}</script></body>")
        }
    }

    fun listProjects(): List<WebForgeProject> {
        if (!root.exists()) return emptyList()
        return root.listFiles()?.asSequence()?.filter { it.isDirectory && PROJECT_ID.matches(it.name) }
            ?.mapNotNull { dir ->
                val nameFile = File(dir, "project-name.txt")
                val name = runCatching { nameFile.readText(StandardCharsets.UTF_8) }.getOrNull()?.takeIf { it.isNotBlank() } ?: dir.name
                WebForgeProject(dir.name, name, dir.lastModified())
            }?.sortedWith(compareByDescending<WebForgeProject> { it.updatedAt }.thenBy { it.name.lowercase(Locale.ROOT) })?.toList().orEmpty()
    }

    fun createProject(rawName: String): WebForgeProject = createProject(rawName, null)

    /** Creates a new local project with reviewed initial files in one rollback-safe operation. */
    fun createProject(rawName: String, initialFiles: WebForgeFiles?): WebForgeProject {
        val trimmed = rawName.trim()
        val baseId = projectId(trimmed) ?: throw IllegalArgumentException("Use 1–40 letters, numbers, spaces, hyphens or underscores; start with a letter or number.")
        root.mkdirs()
        if (!root.isDirectory) throw IOException("Local project storage is unavailable.")
        if (listProjects().size >= MAX_PROJECTS) throw IllegalStateException("This workspace already has $MAX_PROJECTS projects.")
        var id = baseId
        var suffix = 2
        while (File(root, id).exists()) id = "$baseId-${suffix++}"
        val dir = safeProjectDir(id)
        if (!dir.mkdir()) throw IOException("Couldn't create the local project folder.")
        try {
            listOf("css", "js", "assets").forEach { File(dir, it).mkdirs() }
            atomicWrite(File(dir, "project-name.txt"), trimmed)
            atomicWrite(File(dir, "index.html"), "<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>${escapeHtml(trimmed)}</title>\n</head>\n<body>\n  <main>\n    <h1>${escapeHtml(trimmed)}</h1>\n    <p>Edit this page to get started.</p>\n  </main>\n</body>\n</html>\n")
            atomicWrite(File(dir, "css/style.css"), "body { font-family: system-ui, sans-serif; margin: 2rem; line-height: 1.5; }\n")
            atomicWrite(File(dir, "js/script.js"), "// Add page interactions here.\n")
            if (initialFiles != null) saveProject(id, initialFiles)
            return WebForgeProject(id, trimmed, dir.lastModified())
        } catch (error: Exception) {
            dir.deleteRecursively()
            throw error
        }
    }

    /** Read the project's private ordered TODO panel; malformed saved data is surfaced, not hidden. */
    fun loadCoderTodos(id: String): List<WebForgeTodo> {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        val file = File(dir, CODER_TODOS_FILE)
        if (!file.exists()) return emptyList()
        if (file.length() > MAX_CODER_TODOS * (MAX_CODER_TODO_CHARS * 2L + 512L)) {
            throw IOException("The saved Coder task list exceeds the safe read limit.")
        }
        val lines = file.readLines(StandardCharsets.UTF_8)
        if (lines.firstOrNull() != "MYRA_CODER_TODOS_V1") throw IOException("The saved Coder task list has an unsupported format.")
        val rows = lines.drop(1).filter(String::isNotEmpty)
        if (rows.size > MAX_CODER_TODOS) throw IOException("The saved Coder task list exceeds the safe task limit.")
        return try {
            rows.map { row ->
                val fields = row.split('\t')
                require(fields.size == 3)
                WebForgeTodo(decodeTodoText(fields[0]), decodeTodoText(fields[2]), WebForgeTodoStatus.parse(fields[1]))
            }.also { validateCoderTodos(it) }
        } catch (error: Exception) {
            throw IOException("The saved Coder task list couldn't be read safely.", error)
        }
    }

    /** Replace the complete ordered task list, matching update_todos full-list replacement locally. */
    fun replaceCoderTodos(id: String, todos: List<WebForgeTodo>) {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        validateCoderTodos(todos)
        val content = buildString {
            append("MYRA_CODER_TODOS_V1\n")
            todos.forEach { todo ->
                append(encodeTodoText(todo.id)).append('\t').append(todo.status.value).append('\t')
                    .append(encodeTodoText(todo.content)).append('\n')
            }
        }
        atomicWrite(File(dir, CODER_TODOS_FILE), content)
        dir.setLastModified(System.currentTimeMillis())
    }

    private fun encodeTodoText(text: String): String = buildString {
        text.toByteArray(StandardCharsets.UTF_8).forEach { byte -> append("%02x".format(byte.toInt() and 0xff)) }
    }

    private fun decodeTodoText(encoded: String): String {
        require(encoded.length % 2 == 0 && encoded.all { it in '0'..'9' || it in 'a'..'f' })
        val bytes = ByteArray(encoded.length / 2) { index -> encoded.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
        return String(bytes, StandardCharsets.UTF_8)
    }

    private fun validateCoderTodos(todos: List<WebForgeTodo>) {
        require(todos.isNotEmpty()) { "Keep at least one task in the Coder list." }
        require(todos.size <= MAX_CODER_TODOS) { "The Coder task list is limited to $MAX_CODER_TODOS items." }
        require(todos.map { it.id }.distinct().size == todos.size) { "Coder task IDs must be unique." }
        todos.forEach { todo ->
            require(todo.id.isNotBlank() && todo.id.length <= 120) { "Each Coder task needs a stable ID of at most 120 characters." }
            require(todo.content.isNotBlank() && todo.content.length <= MAX_CODER_TODO_CHARS) { "Each Coder task needs text of at most $MAX_CODER_TODO_CHARS characters." }
        }
    }

    fun readProject(id: String): WebForgeFiles {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        return WebForgeFiles(readBounded(File(dir, "index.html")), readBounded(File(dir, "css/style.css")), readBounded(File(dir, "js/script.js")))
    }

    fun saveProject(id: String, files: WebForgeFiles) {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        listOf(files.html, files.css, files.js).forEach { if (it.length > MAX_FILE_CHARS) throw IllegalArgumentException("Each file must be ${MAX_FILE_CHARS} characters or fewer.") }
        atomicWrite(File(dir, "index.html"), files.html)
        atomicWrite(File(dir, "css/style.css"), files.css)
        atomicWrite(File(dir, "js/script.js"), files.js)
        dir.setLastModified(System.currentTimeMillis())
    }

    /**
     * Runs a bounded, static Website Studio review against the current core editor values.
     * It never executes JavaScript or loads project resources. This ports the upstream
     * Studio static_check contract's structural/link/selector checks, without Node or browser APIs.
     */
    fun reviewProject(id: String, currentFiles: WebForgeFiles): List<String> {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        val issues = mutableListOf<String>()
        val html = currentFiles.html.take(MAX_FILE_CHARS)
        val css = currentFiles.css.take(MAX_FILE_CHARS)
        val js = currentFiles.js.take(MAX_FILE_CHARS)
        if (!Regex("<!doctype\\s+html", RegexOption.IGNORE_CASE).containsMatchIn(html)) issues += "index.html: missing <!doctype html>."
        if (!Regex("<title\\b", RegexOption.IGNORE_CASE).containsMatchIn(html)) issues += "index.html: missing a <title>."
        if (!Regex("<meta\\b[^>]*name\\s*=\\s*['\"]viewport['\"]", RegexOption.IGNORE_CASE).containsMatchIn(html)) issues += "index.html: missing a viewport meta tag."

        val cssRefs = Regex("<link\\b([^>]*?)>", RegexOption.IGNORE_CASE).findAll(html).mapNotNull { tag ->
            val attrs = tag.groupValues[1]
            val rel = Regex("\\brel\\s*=\\s*['\"]([^'\"]+)['\"]", RegexOption.IGNORE_CASE).find(attrs)?.groupValues?.get(1).orEmpty()
            val href = Regex("\\bhref\\s*=\\s*['\"]([^'\"]+\\.css(?:[?#][^'\"]*)?)['\"]", RegexOption.IGNORE_CASE).find(attrs)?.groupValues?.get(1)
            href?.takeIf { rel.split(Regex("\\s+")).any { value -> value.equals("stylesheet", true) } }
        }.toList()
        val jsRefs = Regex("<script\\b([^>]*?)>", RegexOption.IGNORE_CASE).findAll(html).mapNotNull { tag ->
            Regex("\\bsrc\\s*=\\s*['\"]([^'\"]+\\.js(?:[?#][^'\"]*)?)['\"]", RegexOption.IGNORE_CASE).find(tag.groupValues[1])?.groupValues?.get(1)
        }.toList()

        fun checkLocalRefs(refs: List<String>, kind: String) {
            refs.forEach { raw ->
                val ref = raw.substringBefore('?').substringBefore('#')
                if (ref.startsWith("https://", true) || ref.startsWith("http://", true) || ref.startsWith("//") || ref.startsWith("data:", true)) return@forEach
                val normalized = ref.removePrefix("./")
                val exists = runCatching { safeProjectFile(id, normalized).isFile }.getOrDefault(false)
                if (!exists) issues += "index.html links '$raw' but that local $kind file is missing or unsafe."
            }
        }
        checkLocalRefs(cssRefs, "stylesheet")
        checkLocalRefs(jsRefs, "script")
        // CSS is composed into the offline preview from the editor even without an HTML link.
        if (css.isBlank() && cssRefs.isEmpty() && !Regex("<style\\b", RegexOption.IGNORE_CASE).containsMatchIn(html)) {
            issues += "index.html: no local stylesheet link or inline <style> block was found."
        }

        val ids = Regex("\\bid\\s*=\\s*['\"]([^'\"]+)['\"]", RegexOption.IGNORE_CASE).findAll(html).map { it.groupValues[1] }.toSet()
        val classes = Regex("\\bclass\\s*=\\s*['\"]([^'\"]+)['\"]", RegexOption.IGNORE_CASE).findAll(html).flatMap { it.groupValues[1].split(Regex("\\s+")).asSequence() }.toSet()
        val idLookups = Regex("getElementById\\(\\s*['\"]([\\w-]+)['\"]", RegexOption.IGNORE_CASE).findAll(js).map { it.groupValues[1] }.toSet()
        idLookups.filterNot(ids::contains).forEach { issues += "js/script.js looks up '#$it', but index.html has no matching id." }
        val selectors = Regex("querySelector(?:All)?\\(\\s*['\"]([#.][\\w-]+)['\"]", RegexOption.IGNORE_CASE).findAll(js).map { it.groupValues[1] }.toSet()
        selectors.forEach { selector ->
            val exists = if (selector.startsWith('#')) selector.drop(1) in ids else selector.drop(1) in classes
            if (!exists) issues += "js/script.js queries '$selector', but index.html has no matching selector."
        }
        if (css.count { it == '{' } != css.count { it == '}' }) issues += "css/style.css: opening and closing brace counts differ."
        return issues.distinct().take(12)
    }

    /** Recursively lists project-owned files, matching the upstream ProjectManager.list_all_files contract. */
    fun listProjectFiles(id: String): List<String> {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        val base = dir.canonicalFile.toPath()
        val result = mutableListOf<String>()
        dir.walkTopDown().onEnter { folder ->
            folder == dir || folder.canonicalFile.toPath().startsWith(base)
        }.forEach { file ->
            if (!file.isFile) return@forEach
            val canonical = file.canonicalFile.toPath()
            if (!canonical.startsWith(base) || canonical == base) return@forEach
            val relative = base.relativize(canonical).toString().replace(File.separatorChar, '/')
            if (relative != PROJECT_METADATA_FILE && relative.split('/').none { it.startsWith('.') }) result += relative
        }
        if (result.size > MAX_PROJECT_FILES) throw IOException("This project exceeds the safe ${MAX_PROJECT_FILES}-file listing limit.")
        return result.sorted()
    }

    fun readProjectFile(id: String, relativePath: String): String {
        val file = safeProjectFile(id, relativePath)
        if (!file.isFile) throw IOException("That project file isn't available.")
        return readBounded(file)
    }

    /**
     * Resolves MYRA Coder's source-backed @path attachment convention for a local preview only.
     * It reads only existing, visible project files; it does not send the prompt to a model.
     */
    fun prepareCoderContext(id: String, task: String): WebForgeCoderContext {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        require(task.length <= 4_000) { "A Coder task preview is limited to 4,000 characters." }
        val available = listProjectFiles(id).filter { path -> path != PROJECT_METADATA_FILE && path.split('/').none { it.startsWith(".") } }.toSet()
        val matcher = Regex("(^|\\s)@([^\\s@]+)").toPattern().matcher(task)
        val rawMentions = linkedSetOf<String>()
        while (matcher.find()) {
            val mention = matcher.group(2)
            if (mention != null) rawMentions.add(mention)
        }

        val warnings = mutableListOf<String>()
        val attached = mutableListOf<String>()
        val blocks = mutableListOf<String>()
        var attachedChars = 0
        for (raw in rawMentions) {
            val stripped = raw.trimEnd { it in "?.,:;!)]'\"" }
            val path = when {
                raw in available -> raw
                stripped in available -> stripped
                else -> null
            }
            if (path == null) {
                warnings += "@${stripped.ifBlank { raw }}: no matching visible project file; skipped."
                continue
            }
            if (path in attached) continue
            if (attached.size >= MAX_CODER_CONTEXT_FILES) {
                warnings += "Only the first $MAX_CODER_CONTEXT_FILES referenced files can be attached."
                break
            }
            val content = try {
                val file = safeProjectFile(id, path)
                if (!file.isFile) throw IOException("not a regular file")
                readBounded(file)
            } catch (_: Exception) {
                warnings += "@$path: couldn't read this project file; skipped."
                continue
            }
            if (attachedChars + content.length > MAX_CODER_CONTEXT_CHARS) {
                warnings += "@$path: combined Coder context exceeds the $MAX_CODER_CONTEXT_CHARS-character limit; skipped."
                continue
            }
            attachedChars += content.length
            attached += path
            val lines = content.split("\n")
            val width = lines.size.toString().length
            val numbered = lines.mapIndexed { index, line -> "${(index + 1).toString().padStart(width, ' ')}\t$line" }.joinToString("\n")
            blocks += "--- FILE: $path ---\n$numbered\n--- END FILE: $path ---"
        }
        val preview = if (blocks.isEmpty()) task else "${blocks.joinToString("\n\n")}\n\nUsing the attached file context above, respond to:\n$task"
        return WebForgeCoderContext(preview, attached, warnings)
    }

    /**
     * Builds the upstream Coder `/init`-style project-notes starter using visible paths only.
     * It does not parse or send source contents, run project commands, or overwrite an existing guide.
     */
    fun scaffoldCoderGuide(id: String): Boolean {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        val target = safeProjectFile(id, CODER_GUIDE_FILE)
        if (target.exists()) return false
        val paths = listProjectFiles(id)
            .filter { path -> path != PROJECT_METADATA_FILE && path != CODER_GUIDE_FILE && path.split('/').none { it.startsWith('.') || it == "node_modules" } }
            .take(MAX_PROJECT_FILES)
        val languageNames = mapOf(
            "ts" to "TypeScript", "tsx" to "TypeScript (React)", "js" to "JavaScript",
            "jsx" to "JavaScript (React)", "py" to "Python", "go" to "Go", "rs" to "Rust",
            "java" to "Java", "kt" to "Kotlin", "kts" to "Kotlin Script", "rb" to "Ruby", "php" to "PHP", "c" to "C",
            "cpp" to "C++", "cs" to "C#", "html" to "HTML", "css" to "CSS",
            "json" to "JSON", "md" to "Markdown",
        )
        val languages = paths.mapNotNull { path ->
            languageNames[path.substringAfterLast('.', "").lowercase(Locale.ROOT)]
        }.distinct().sorted()
        val pathSet = paths.toSet()
        val packageManager = when {
            "pnpm-lock.yaml" in pathSet -> "pnpm"
            "yarn.lock" in pathSet -> "yarn"
            "bun.lockb" in pathSet || "bun.lock" in pathSet -> "bun"
            "package-lock.json" in pathSet -> "npm"
            else -> null
        }
        val topLevelDirs = paths.mapNotNull { it.substringBefore('/', "").takeIf(String::isNotEmpty) }.distinct().sorted()
        val projectName = runCatching { File(dir, PROJECT_METADATA_FILE).readText(StandardCharsets.UTF_8).trim() }
            .getOrNull()?.takeIf(String::isNotEmpty) ?: id
        val lines = mutableListOf("# MYRA_CODER.md — Project Notes", "", "**Project:** $projectName")
        if (languages.isNotEmpty()) lines += listOf("", "**Languages:** ${languages.joinToString(", ")}")
        if (packageManager != null) lines += listOf("", "**Package manager:** $packageManager")
        if (topLevelDirs.isNotEmpty()) {
            lines += listOf("", "## Layout", "")
            topLevelDirs.take(12).forEach { lines += "- `$it/`" }
        }
        lines += listOf(
            "", "## Project conventions", "", "- Add verified build and test commands here.",
            "- Record durable architecture notes and coding conventions here.",
            "", "_Generated locally from visible project paths. Review and edit these notes; no source contents were sent._", "",
        )
        val content = lines.joinToString("\n")
        if (content.length > MAX_FILE_CHARS) throw IOException("The generated project guide exceeds the safe file limit.")
        // Recheck the destination immediately before writing and never replace existing notes.
        if (target.exists()) return false
        atomicWrite(target, content)
        dir.setLastModified(System.currentTimeMillis())
        return true
    }

    /** Capture the exact one-file payload before explicit Google-send approval. */
    fun prepareCoderPatchRequest(id: String, relativePath: String, task: String): WebForgeCoderPatchRequest {
        require(relativePath in listProjectFiles(id)) { "Choose an existing visible file in this project." }
        val file = safeProjectFile(id, relativePath)
        if (!file.isFile) throw IOException("That project file isn't available.")
        val before = readBounded(file)
        require(before.length <= MAX_REVIEWED_PATCH_CHARS) { "This file is too large for model-assisted replacement; use the regular editor instead." }
        val requestText = WebForgeCoderAssist.patchRequestText(task, relativePath, before)
        return WebForgeCoderPatchRequest(relativePath, task, before, sha256(before), requestText)
    }

    /** Capture a bounded replacement proposal, rejecting a source file changed since model review. */
    fun prepareCoderPatch(id: String, relativePath: String, after: String, expectedBeforeSha256: String? = null): WebForgeCoderPatch {
        require(relativePath in listProjectFiles(id)) { "Choose an existing visible file in this project." }
        require(after.length <= MAX_REVIEWED_PATCH_CHARS) { "A reviewed Coder patch is limited to $MAX_REVIEWED_PATCH_CHARS characters." }
        val file = safeProjectFile(id, relativePath)
        if (!file.isFile) throw IOException("That project file isn't available.")
        val before = readBounded(file)
        require(before.length <= MAX_REVIEWED_PATCH_CHARS) { "This file is too large for the reviewed patch flow; use the regular editor instead." }
        val currentHash = sha256(before)
        if (expectedBeforeSha256 != null && currentHash != expectedBeforeSha256) throw IOException("This file changed while Gemini was preparing a replacement. Reopen it and prepare a fresh request.")
        return WebForgeCoderPatch(relativePath, before, after, currentHash)
    }

    /** Apply only the exact reviewed replacement, after a stale-content check; retain one durable undo. */
    fun applyCoderPatch(id: String, patch: WebForgeCoderPatch) {
        require(patch.before.length <= MAX_REVIEWED_PATCH_CHARS && patch.after.length <= MAX_REVIEWED_PATCH_CHARS) {
            "A reviewed Coder patch is limited to $MAX_REVIEWED_PATCH_CHARS characters per version."
        }
        require(patch.targetPath in listProjectFiles(id)) { "Choose an existing visible file in this project." }
        val target = safeProjectFile(id, patch.targetPath)
        if (!target.isFile) throw IOException("That project file isn't available.")
        val current = readBounded(target)
        if (sha256(current) != patch.beforeSha256 || current != patch.before) throw IOException("This file changed after the review. Reopen it and prepare the patch again.")

        val projectDir = safeProjectDir(id)
        val undoDir = File(projectDir, ".myra-coder")
        val marker = File(undoDir, ".patch-target")
        if (marker.exists()) throw IllegalStateException("Undo the previous reviewed patch before applying another one.")
        if (!undoDir.exists() && !undoDir.mkdirs()) throw IOException("Couldn't prepare private undo storage.")
        atomicWrite(File(undoDir, ".patch-before"), patch.before)
        atomicWrite(File(undoDir, ".patch-after"), patch.after)
        // Write the marker last: if the app stops partway through staging, incomplete backups aren't offered as undo.
        atomicWrite(marker, patch.targetPath)
        atomicWrite(target, patch.after)
        projectDir.setLastModified(System.currentTimeMillis())
    }

    fun hasPendingCoderUndo(id: String): Boolean {
        val dir = safeProjectDir(id)
        val marker = File(File(dir, ".myra-coder"), ".patch-target")
        return marker.isFile
    }

    /** Restore the one saved pre-patch version only if the file still equals the reviewed result. */
    fun undoCoderPatch(id: String): WebForgeCoderUndoResult? {
        val projectDir = safeProjectDir(id)
        val undoDir = File(projectDir, ".myra-coder")
        val marker = File(undoDir, ".patch-target")
        if (!marker.isFile) return null
        val path = marker.readText(StandardCharsets.UTF_8)
        require(path in listProjectFiles(id)) { "The saved undo target is no longer a visible file in this project." }
        val beforeFile = File(undoDir, ".patch-before")
        val afterFile = File(undoDir, ".patch-after")
        if (!beforeFile.isFile || !afterFile.isFile) throw IOException("The saved patch undo data is incomplete.")
        if (beforeFile.length() > MAX_REVIEWED_PATCH_CHARS * 4L || afterFile.length() > MAX_REVIEWED_PATCH_CHARS * 4L) {
            throw IOException("The saved patch undo data exceeds the safe limit.")
        }
        val before = readBounded(beforeFile)
        val after = readBounded(afterFile)
        require(before.length <= MAX_REVIEWED_PATCH_CHARS && after.length <= MAX_REVIEWED_PATCH_CHARS) { "The saved patch undo data exceeds the safe limit." }
        val target = safeProjectFile(id, path)
        if (!target.isFile) throw IOException("The reviewed patch target is no longer available.")
        val current = readBounded(target)
        val restored = when {
            current == after -> { atomicWrite(target, before); true }
            current == before -> false // The write never took effect; discard the staged undo safely.
            else -> throw IOException("The file changed after the patch. Undo was left untouched to avoid overwriting newer work.")
        }
        // Removing the marker last makes a repeated recovery harmless if cleanup is interrupted.
        if (!marker.delete()) throw IOException("The file was restored, but its undo record could not be cleared yet.")
        beforeFile.delete()
        afterFile.delete()
        if (restored) projectDir.setLastModified(System.currentTimeMillis())
        return WebForgeCoderUndoResult(path, before, restored)
    }

    fun saveProjectFile(id: String, relativePath: String, content: String) {
        if (content.length > MAX_FILE_CHARS) throw IllegalArgumentException("A file must be ${MAX_FILE_CHARS} characters or fewer.")
        val file = safeProjectFile(id, relativePath)
        file.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) throw IOException("Couldn't create the local project folder.")
        }
        val checkedFile = safeProjectFile(id, relativePath)
        if (!checkedFile.exists() && listProjectFiles(id).size >= MAX_PROJECT_FILES) throw IllegalStateException("This project already has ${MAX_PROJECT_FILES} files.")
        atomicWrite(checkedFile, content)
        safeProjectDir(id).setLastModified(System.currentTimeMillis())
    }

    /** Writes a bounded local ZIP for user-selected export; no network or deployment is involved. */
    fun exportProjectZip(id: String, output: OutputStream): Int {
        val dir = safeProjectDir(id)
        if (!dir.isDirectory) throw IOException("That project isn't available in this workspace.")
        val base = dir.canonicalFile.toPath()
        val paths = listProjectFiles(id).filter { path ->
            val parts = path.split('/')
            parts.none { it.startsWith('.') || it == "node_modules" } && ".myra-coder" !in parts
        }
        if (paths.size > MAX_PROJECT_FILES) throw IOException("This project exceeds the safe export file limit.")
        val entries = paths.map { relative ->
            val file = safeProjectFile(id, relative)
            if (!file.isFile) throw IOException("A project file changed while preparing export.")
            val canonical = file.canonicalFile.toPath()
            if (!canonical.startsWith(base) || canonical == base) throw IOException("A project file points outside this workspace.")
            val size = file.length()
            if (size > MAX_EXPORT_FILE_BYTES) throw IOException("${relative} exceeds the safe 10 MiB export limit.")
            relative to file
        }
        val totalBytes = entries.sumOf { it.second.length() }
        if (totalBytes > MAX_EXPORT_TOTAL_BYTES) throw IOException("The project exceeds the safe 20 MiB export limit.")

        val zip = ZipOutputStream(output)
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var totalCopied = 0L
        entries.forEach { (relative, file) ->
            zip.putNextEntry(ZipEntry(relative))
            file.inputStream().use { input ->
                var copied = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    copied += count
                    totalCopied += count
                    if (copied > MAX_EXPORT_FILE_BYTES || totalCopied > MAX_EXPORT_TOTAL_BYTES || copied > file.length()) {
                        throw IOException("${relative} changed beyond the safe export limit.")
                    }
                    zip.write(buffer, 0, count)
                }
                if (copied != file.length()) throw IOException("${relative} changed while being exported.")
            }
            zip.closeEntry()
        }
        zip.finish()
        zip.flush()
        return entries.size
    }

    private fun safeProjectFile(id: String, relativePath: String): File {
        val dir = safeProjectDir(id)
        val normalized = relativePath.trim()
        require(normalized.isNotEmpty() && normalized.length <= 180) { "Enter a project-relative file path (up to 180 characters)." }
        require(!normalized.startsWith('/') && !normalized.startsWith('\\') && !Regex("^[A-Za-z]:").containsMatchIn(normalized)) { "Use a project-relative file path." }
        require('\\' !in normalized) { "Use forward slashes in project file paths." }
        val parts = normalized.split('/')
        require(parts.none { it.isEmpty() || it == "." || it == ".." }) { "File paths can't contain empty, dot, or parent folders." }
        require(parts.none { it.startsWith('.') }) { "Hidden project files can't be edited here." }
        require(!normalized.equals(PROJECT_METADATA_FILE, ignoreCase = true)) { "Project metadata can't be edited here." }
        val base = dir.canonicalFile.toPath()
        var cursor = dir
        parts.forEachIndexed { index, part ->
            cursor = File(cursor, part)
            val canonical = cursor.canonicalFile.toPath()
            require(canonical.startsWith(base) && canonical != base) { "Project paths can't escape this workspace." }
            if (index < parts.lastIndex && cursor.exists()) require(cursor.isDirectory) { "A project path component isn't a folder." }
        }
        val target = cursor.canonicalFile.toPath()
        require(target.startsWith(base) && target != base) { "Invalid project file path." }
        return cursor
    }

    private fun safeProjectDir(id: String): File {
        require(PROJECT_ID.matches(id)) { "Invalid project name." }
        val candidate = File(root, id)
        val dir = candidate.canonicalFile
        require(dir.parentFile == root.canonicalFile && dir.name == id) { "Invalid project path." }
        return dir
    }

    private fun readBounded(file: File): String {
        if (!file.exists()) return ""
        if (file.length() > MAX_FILE_CHARS * 4L) throw IOException("A project file exceeds the safe read limit.")
        return file.readText(StandardCharsets.UTF_8).also { if (it.length > MAX_FILE_CHARS) throw IOException("A project file exceeds the safe read limit.") }
    }

    private fun atomicWrite(file: File, content: String) {
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, ".${file.name}.tmp")
        temp.writeText(content, StandardCharsets.UTF_8)
        if (!temp.renameTo(file)) {
            temp.delete()
            throw IOException("Couldn't save ${file.name} to local project storage.")
        }
    }

    private fun escapeHtml(value: String): String = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")
}

private val WebForgePanel = Color(0xFF151B25)
private val WebForgeMint = Color(0xFF66E3CF)
private val WebForgeMuted = Color(0xFF9AA8B9)

@Composable
internal fun WebForgeScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val repository = remember(context) { WebForgeRepository(File(context.filesDir, "webforge-projects")) }
    val scope = rememberCoroutineScope()
    var projects by remember { mutableStateOf(emptyList<WebForgeProject>()) }
    var selected by remember { mutableStateOf<WebForgeProject?>(null) }
    var projectName by remember { mutableStateOf("") }
    var files by remember { mutableStateOf(WebForgeFiles("", "", "")) }
    var projectFilePaths by remember { mutableStateOf(emptyList<String>()) }
    var extraFilePath by remember { mutableStateOf("") }
    var extraFileContent by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf("Projects stay in this app's private storage. AI generation sends only the prompt you enter to Google Gemini after you confirm.") }
    var generationPrompt by remember { mutableStateOf("") }
    var generatedSite by remember { mutableStateOf<WebForgeGeneratedSite?>(null) }
    var confirmGeneration by remember { mutableStateOf(false) }
    var generating by remember { mutableStateOf(false) }
    var reviewIssues by remember { mutableStateOf<List<String>?>(null) }
    var coderTask by remember { mutableStateOf("") }
    var coderTodos by remember { mutableStateOf(emptyList<WebForgeTodo>()) }
    var newCoderTodo by remember { mutableStateOf("") }
    var openTodoMenu by remember { mutableStateOf<String?>(null) }
    var coderContext by remember { mutableStateOf<WebForgeCoderContext?>(null) }
    var coderSuggestions by remember { mutableStateOf<String?>(null) }
    var confirmCoderAssist by remember { mutableStateOf(false) }
    var askingCoder by remember { mutableStateOf(false) }
    var coderPatchPath by remember { mutableStateOf("") }
    var coderPatchMenuOpen by remember { mutableStateOf(false) }
    var confirmCoderPatchAssist by remember { mutableStateOf(false) }
    var coderPatchRequest by remember { mutableStateOf<WebForgeCoderPatchRequest?>(null) }
    var preparingCoderPatch by remember { mutableStateOf(false) }
    var patchComposerOpen by remember { mutableStateOf(false) }
    var patchTargetMenuOpen by remember { mutableStateOf(false) }
    var patchTargetPath by remember { mutableStateOf("") }
    var patchAfterText by remember { mutableStateOf("") }
    var pendingCoderPatch by remember { mutableStateOf<WebForgeCoderPatch?>(null) }
    var patchUndoAvailable by remember { mutableStateOf(false) }
    var applyingCoderPatch by remember { mutableStateOf(false) }
    var pendingExport by remember { mutableStateOf<WebForgeProject?>(null) }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        val project = pendingExport
        pendingExport = null
        if (uri == null || project == null) {
            notice = "ZIP export canceled."
        } else {
            scope.launch {
                notice = "Exporting ${project.name}…"
                runCatching {
                    withContext(Dispatchers.IO) {
                        val output = context.contentResolver.openOutputStream(uri)
                            ?: throw IOException("Couldn't open the selected save location.")
                        output.use { repository.exportProjectZip(project.id, it) }
                    }
                }.onSuccess { count -> notice = "Exported $count project files to the location you chose." }
                    .onFailure { notice = it.message ?: "Couldn't export this project." }
            }
        }
    }
    var showPreview by remember { mutableStateOf(false) }
    var previewSource by remember { mutableStateOf("") }
    LaunchedEffect(repository) { projects = withContext(Dispatchers.IO) { repository.listProjects() } }
    fun refreshProjectFiles(id: String) { scope.launch { projectFilePaths = runCatching { withContext(Dispatchers.IO) { repository.listProjectFiles(id) } }.getOrDefault(emptyList()) } }
    fun load(project: WebForgeProject) {
        scope.launch {
            notice = "Opening local project…"
            runCatching { withContext(Dispatchers.IO) { repository.readProject(project.id) } }
                .onSuccess { files = it; selected = project; showPreview = false; reviewIssues = null; coderTask = ""; coderContext = null; coderSuggestions = null; coderPatchPath = ""; coderPatchRequest = null; confirmCoderPatchAssist = false; patchComposerOpen = false; pendingCoderPatch = null; patchUndoAvailable = withContext(Dispatchers.IO) { repository.hasPendingCoderUndo(project.id) }; coderTodos = withContext(Dispatchers.IO) { repository.loadCoderTodos(project.id) }; newCoderTodo = ""; openTodoMenu = null; extraFilePath = ""; extraFileContent = ""; refreshProjectFiles(project.id); notice = "Editing ${project.name} locally. Changes are not published." }
                .onFailure { notice = it.message ?: "Couldn't open this local project." }
        }
    }
    fun refreshProjects() { scope.launch { projects = withContext(Dispatchers.IO) { repository.listProjects() } } }
    fun openProjectFile(path: String) {
        val project = selected ?: return
        scope.launch {
            runCatching { withContext(Dispatchers.IO) { repository.readProjectFile(project.id, path) } }
                .onSuccess { extraFilePath = path; extraFileContent = it; notice = "Opened $path locally." }
                .onFailure { notice = it.message ?: "Couldn't open this project file." }
        }
    }

    fun editorValueFor(path: String): String? = when (path) {
        "index.html" -> files.html
        "css/style.css" -> files.css
        "js/script.js" -> files.js
        else -> extraFileContent.takeIf { extraFilePath == path }
    }
    fun updateEditorValue(path: String, content: String) {
        when (path) {
            "index.html" -> files = files.copy(html = content)
            "css/style.css" -> files = files.copy(css = content)
            "js/script.js" -> files = files.copy(js = content)
        }
        if (extraFilePath == path) extraFileContent = content
        showPreview = false
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 20.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = WebForgeMint) }
            Column {
                Text("WEBFORGE", color = WebForgeMint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp)
                Text("Website projects", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text("Create and edit a local HTML/CSS/JavaScript project. Preview is sandboxed and offline; there is no deployment action.", color = WebForgeMuted, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp))
        Text(notice, color = WebForgeMuted, fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
        if (selected == null) {
            Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Text("Generate a website draft", color = WebForgeMint, fontWeight = FontWeight.SemiBold)
                    Text("Only the prompt below is sent to Google Gemini, and only after you confirm. Existing project files are never attached. Review the returned HTML, CSS and JavaScript here; nothing is saved until you tap Save generated project.", color = WebForgeMuted, fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.padding(top = 4.dp))
                    OutlinedTextField(value = generationPrompt, onValueChange = { generationPrompt = it.take(WebForgeGeneration.MAX_PROMPT_CHARS); generatedSite = null }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), label = { Text("Website prompt") }, placeholder = { Text("A calm portfolio site for a photographer...") }, minLines = 2, maxLines = 5, supportingText = { Text("${generationPrompt.length}/${WebForgeGeneration.MAX_PROMPT_CHARS}") })
                    Button(onClick = { confirmGeneration = true }, enabled = !generating && generationPrompt.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16)), modifier = Modifier.padding(top = 6.dp)) { Text(if (generating) "Generating…" else "Generate draft") }
                    generatedSite?.let { draft ->
                        Text("Review generated draft", color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 12.dp))
                        OutlinedTextField(value = draft.projectName, onValueChange = { generatedSite = draft.copy(projectName = it.take(40)) }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), label = { Text("New project name") }, singleLine = true)
                        Text("Generated code is untrusted. Read and edit it before saving. Preview stays sandboxed and offline.", color = Color(0xFFFFC47A), fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp))
                        CodeField("index.html", draft.files.html, { generatedSite = draft.copy(files = draft.files.copy(html = it)) })
                        CodeField("css/style.css", draft.files.css, { generatedSite = draft.copy(files = draft.files.copy(css = it)) })
                        CodeField("js/script.js", draft.files.js, { generatedSite = draft.copy(files = draft.files.copy(js = it)) })
                        Button(onClick = {
                            val reviewed = generatedSite ?: return@Button
                            scope.launch {
                                notice = "Saving the reviewed draft as a new local project…"
                                runCatching { withContext(Dispatchers.IO) { repository.createProject(reviewed.projectName, reviewed.files) } }
                                    .onSuccess { project -> generatedSite = null; generationPrompt = ""; refreshProjects(); load(project) }
                                    .onFailure { notice = it.message ?: "Couldn't save the new local project." }
                            }
                        }, enabled = draft.projectName.isNotBlank() && draft.files.html.isNotBlank() && draft.files.css.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16)), modifier = Modifier.padding(top = 8.dp)) { Text("Save generated project") }
                    }
                }
            }
            if (confirmGeneration) {
                AlertDialog(
                    onDismissRequest = { confirmGeneration = false },
                    title = { Text("Send prompt to Google Gemini?") },
                    text = { Text("Your website prompt will be sent to Google Gemini using the saved model settings. No existing project files or other project data will be sent. Generated code is untrusted; review it before saving. Generate now?") },
                    confirmButton = { TextButton(onClick = {
                        confirmGeneration = false
                        val prompt = generationPrompt
                        val invalid = WebForgeGeneration.validatePrompt(prompt)
                        if (invalid != null) { notice = invalid } else {
                            generating = true
                            notice = "Sending only your prompt to Google Gemini…"
                            scope.launch {
                                runCatching {
                                    withContext(Dispatchers.IO) {
                                        val model = GeminiModelCatalog.resolveId(context.getSharedPreferences("myra_native_settings", android.content.Context.MODE_PRIVATE).getString("model", null))
                                        GeminiClient.generateWebsite(context, prompt, model)
                                    }
                                }.onSuccess { generatedSite = it; notice = "Draft received. Review all three files; nothing has been saved yet." }
                                    .onFailure { notice = it.message ?: "Couldn't generate a website draft." }
                                generating = false
                            }
                        }
                    }) { Text("Send prompt & generate") } },
                    dismissButton = { TextButton(onClick = { confirmGeneration = false }) { Text("Cancel") } },
                )
            }
            Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Text("New project", color = Color.White, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(value = projectName, onValueChange = { projectName = it.take(60) }, modifier = Modifier.fillMaxWidth(), label = { Text("Project name") }, singleLine = true)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = {
                        val name = projectName
                        scope.launch {
                            runCatching { withContext(Dispatchers.IO) { repository.createProject(name) } }
                                .onSuccess { project -> projectName = ""; refreshProjects(); load(project) }
                                .onFailure { notice = it.message ?: "Couldn't create the local project." }
                        }
                    }, enabled = projectName.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16))) { Text("Create local project") }
                }
            }
            Text("YOUR PROJECTS", color = WebForgeMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
            if (projects.isEmpty()) Text("No projects yet.", color = WebForgeMuted, modifier = Modifier.padding(8.dp))
            projects.forEach { project ->
                Card(onClick = { load(project) }, colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Text(project.name, color = Color.White, fontWeight = FontWeight.SemiBold)
                        Text("index.html · css/style.css · js/script.js", color = WebForgeMuted, fontSize = 12.sp)
                    }
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { selected = null; showPreview = false; extraFilePath = ""; extraFileContent = ""; patchComposerOpen = false; pendingCoderPatch = null; refreshProjects() }) { Icon(Icons.Default.ArrowBack, null); Spacer(Modifier.width(4.dp)); Text("Projects") }
                Button(onClick = {
                    val project = selected ?: return@Button
                    val draft = files
                    scope.launch {
                        notice = "Saving locally…"
                        runCatching { withContext(Dispatchers.IO) { repository.saveProject(project.id, draft) } }
                            .onSuccess { notice = "Saved ${project.name} on this device. Nothing was sent or published."; refreshProjects() }
                            .onFailure { notice = it.message ?: "Couldn't save the project." }
                    }
                }, colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16))) { Text("Save") }
                OutlinedButton(onClick = {
                if (showPreview) showPreview = false
                else { previewSource = WebForgeRepository.previewHtml(files); showPreview = true }
            }) { Icon(Icons.Default.Visibility, null); Spacer(Modifier.width(4.dp)); Text(if (showPreview) "Hide preview" else "Preview") }
            }
            OutlinedButton(
                onClick = {
                    val project = selected ?: return@OutlinedButton
                    val draft = files
                    scope.launch {
                        notice = "Reviewing the current HTML/CSS/JavaScript draft…"
                        runCatching { withContext(Dispatchers.IO) { repository.reviewProject(project.id, draft) } }
                            .onSuccess { issues -> reviewIssues = issues; notice = if (issues.isEmpty()) "Static review found no checked structure or reference issues." else "Static review found ${issues.size} issue(s) to inspect." }
                            .onFailure { notice = it.message ?: "Couldn't review this project draft." }
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            ) { Text("Review current draft") }
            reviewIssues?.let { issues ->
                Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(if (issues.isEmpty()) "No checked issues found" else "Static review", color = WebForgeMint, fontWeight = FontWeight.SemiBold)
                        Text("Checks basic HTML metadata, local CSS/JS links, literal DOM selectors and CSS brace balance only; it does not parse or execute code.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp, bottom = 6.dp))
                        if (issues.isEmpty()) Text("This is not a full HTML, CSS or JavaScript validator.", color = Color.White, fontSize = 12.sp)
                        issues.forEach { issue -> Text("• $issue", color = Color.White, fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.padding(vertical = 2.dp)) }
                    }
                }
            }
            Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text("MYRA Coder file context", color = WebForgeMint, fontWeight = FontWeight.SemiBold)
                    Text("Use @path/to/file in a task to prepare numbered context from visible project files. You can review the exact task/context and explicitly send it to Google Gemini for suggestions; nothing is written or run.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp))
                    OutlinedTextField(
                        value = coderTask,
                        onValueChange = { coderTask = it.take(WebForgeCoderAssist.MAX_TASK_CHARS); coderContext = null; coderSuggestions = null },
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                        label = { Text("Coding task") },
                        placeholder = { Text("Explain @index.html and @css/style.css") },
                        minLines = 2,
                        maxLines = 5,
                    )
                    Text("AI-assisted full-file replacement", color = WebForgeMint, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 12.dp))
                    Text("Choose one existing visible file. After you review the exact task and file text sent to Google, Gemini can propose a complete replacement. MYRA shows the full before/after and source fingerprint; a separate approval is required to apply it locally. Nothing is run.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp))
                    androidx.compose.foundation.layout.Box(Modifier.padding(top = 6.dp)) {
                        OutlinedButton(onClick = { coderPatchMenuOpen = true }, enabled = !preparingCoderPatch) {
                            Text(if (coderPatchPath.isBlank()) "Choose one file for replacement" else coderPatchPath)
                        }
                        DropdownMenu(expanded = coderPatchMenuOpen, onDismissRequest = { coderPatchMenuOpen = false }) {
                            projectFilePaths.forEach { path ->
                                DropdownMenuItem(text = { Text(path) }, onClick = { coderPatchPath = path; coderPatchRequest = null; coderPatchMenuOpen = false })
                            }
                        }
                    }
                    Button(
                        onClick = {
                            val project = selected ?: return@Button
                            val path = coderPatchPath
                            val task = coderTask
                            preparingCoderPatch = true
                            scope.launch {
                                runCatching {
                                    withContext(Dispatchers.IO) { repository.prepareCoderPatchRequest(project.id, path, task) }
                                }.map { request ->
                                    val unsavedEditor = editorValueFor(path)
                                    if (unsavedEditor != null && unsavedEditor != request.before) {
                                        throw IllegalStateException("Save or discard your current edits to $path before preparing a model request.")
                                    }
                                    request
                                }.onSuccess { request -> coderPatchRequest = request; confirmCoderPatchAssist = true; notice = "Review the exact one-file Gemini request before sending." }
                                    .onFailure { notice = it.message ?: "Couldn't prepare the model-assisted replacement request." }
                                preparingCoderPatch = false
                            }
                        },
                        enabled = coderPatchPath.isNotBlank() && coderTask.isNotBlank() && !askingCoder && !preparingCoderPatch && !patchUndoAvailable,
                        colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16)),
                        modifier = Modifier.padding(top = 4.dp),
                    ) { Text(if (preparingCoderPatch) "Preparing…" else "Prepare model replacement") }
                    if (patchUndoAvailable) Text("Undo the last reviewed patch before preparing another replacement.", color = WebForgeMuted, fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp))
                    Button(
                        onClick = {
                            val project = selected ?: return@Button
                            val task = coderTask
                            scope.launch {
                                runCatching { withContext(Dispatchers.IO) { repository.prepareCoderContext(project.id, task) } }
                                    .onSuccess { result -> coderContext = result; notice = "Prepared local context for ${result.attachedPaths.size} file(s); nothing was sent." }
                                    .onFailure { notice = it.message ?: "Couldn't prepare Coder context." }
                            }
                        },
                        enabled = coderTask.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16)),
                        modifier = Modifier.padding(top = 4.dp),
                    ) { Text("Prepare @file context") }
                    coderContext?.let { result ->
                        if (result.attachedPaths.isNotEmpty()) Text("Attached locally: ${result.attachedPaths.joinToString()}", color = WebForgeMuted, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
                        result.warnings.forEach { warning -> Text(warning, color = Color(0xFFFFC47A), fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp)) }
                        OutlinedTextField(value = result.previewText, onValueChange = {}, readOnly = true, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), label = { Text("Exact text sent to Google if you confirm") }, minLines = 4, maxLines = 12)
                    }
                }
            }
            coderContext?.let { contextPreview ->
                Button(
                    onClick = { confirmCoderAssist = true },
                    enabled = !askingCoder && coderTask.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16)),
                    modifier = Modifier.padding(top = 6.dp),
                ) { Text(if (askingCoder) "Getting suggestions…" else "Get Gemini suggestions") }
                coderSuggestions?.let { answer ->
                    Text("Suggestions for review — nothing was changed", color = WebForgeMint, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 10.dp))
                    Text("Treat model output as untrusted. MYRA does not apply it, run code, or modify project files.", color = Color(0xFFFFC47A), fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp))
                    OutlinedTextField(value = answer, onValueChange = {}, readOnly = true, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), label = { Text("Gemini response") }, minLines = 4, maxLines = 16)
                    OutlinedButton(
                        onClick = { patchTargetPath = ""; patchAfterText = ""; patchComposerOpen = true },
                        enabled = !applyingCoderPatch && !patchUndoAvailable,
                        modifier = Modifier.padding(top = 6.dp),
                    ) { Text("Prepare a reviewed local patch") }
                    if (patchUndoAvailable) Text("Undo the last reviewed patch before applying another one.", color = WebForgeMuted, fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp))
                }
                if (confirmCoderAssist) {
                    AlertDialog(
                        onDismissRequest = { confirmCoderAssist = false },
                        title = { Text("Send this task to Google Gemini?") },
                        text = {
                            Column {
                                Text("The exact user text below will be sent to Google using your selected model. It includes only the task and any explicitly referenced @file excerpts shown here. No other project files are sent. Gemini returns suggestions only; MYRA will not write files or run code.", fontSize = 13.sp)
                                Column(Modifier.height(240.dp).fillMaxWidth().padding(top = 8.dp).verticalScroll(rememberScrollState())) {
                                    Text(contextPreview.previewText, fontSize = 12.sp, lineHeight = 16.sp)
                                }
                            }
                        },
                        confirmButton = { TextButton(onClick = {
                            confirmCoderAssist = false
                            val task = coderTask
                            val exactText = contextPreview.previewText
                            val invalid = WebForgeCoderAssist.validate(task, exactText)
                            if (invalid != null) { notice = invalid } else {
                                askingCoder = true
                                coderSuggestions = null
                                notice = "Sending the reviewed Coder task and selected file excerpts to Google Gemini…"
                                scope.launch {
                                    runCatching {
                                        withContext(Dispatchers.IO) {
                                            val model = GeminiModelCatalog.resolveId(context.getSharedPreferences("myra_native_settings", android.content.Context.MODE_PRIVATE).getString("model", null))
                                            GeminiClient.generateCoderSuggestions(context, exactText, model)
                                        }
                                    }.onSuccess { coderSuggestions = it; notice = "Suggestions received for review; no project files were changed." }
                                        .onFailure { notice = it.message ?: "Couldn't get Coder suggestions." }
                                    askingCoder = false
                                }
                            }
                        }) { Text("Send task & get suggestions") } },
                        dismissButton = { TextButton(onClick = { confirmCoderAssist = false }) { Text("Cancel") } },
                    )
                }
            }
            if (confirmCoderPatchAssist) {
                val request = coderPatchRequest
                if (request != null) AlertDialog(
                    onDismissRequest = { if (!askingCoder) { confirmCoderPatchAssist = false; coderPatchRequest = null } },
                    title = { Text("Send this one file to Google Gemini?") },
                    text = {
                        Column {
                            Text("Google receives only this exact task and the complete contents of ${request.targetPath}, using your selected model. No other project files are sent. The response is untrusted and will not be written or run. You’ll review the complete before/after and approve again before a local write.", fontSize = 13.sp)
                            Text("Source SHA-256: ${request.beforeSha256}", color = WebForgeMint, fontSize = 10.sp, modifier = Modifier.padding(top = 6.dp))
                            Column(Modifier.height(240.dp).fillMaxWidth().padding(top = 8.dp).verticalScroll(rememberScrollState())) {
                                Text(request.requestText, fontSize = 11.sp, lineHeight = 15.sp)
                            }
                        }
                    },
                    confirmButton = { TextButton(enabled = !askingCoder, onClick = {
                        val prepared = request
                        val project = selected
                        confirmCoderPatchAssist = false
                        if (prepared == null || project == null) {
                            coderPatchRequest = null
                            notice = "Choose a project file and prepare the request again."
                        } else {
                            askingCoder = true
                            notice = "Sending only the reviewed task and selected file to Google Gemini…"
                            scope.launch {
                                runCatching {
                                    val replacement = withContext(Dispatchers.IO) {
                                        val model = GeminiModelCatalog.resolveId(context.getSharedPreferences("myra_native_settings", android.content.Context.MODE_PRIVATE).getString("model", null))
                                        GeminiClient.generateCoderReplacement(context, prepared.requestText, model)
                                    }
                                    withContext(Dispatchers.IO) {
                                        repository.prepareCoderPatch(project.id, prepared.targetPath, replacement, prepared.beforeSha256)
                                    }
                                }.onSuccess { patch ->
                                    pendingCoderPatch = patch
                                    coderPatchRequest = null
                                    notice = "Gemini returned a bounded replacement. Review the complete before/after and fingerprint before applying."
                                }.onFailure { error ->
                                    coderPatchRequest = null
                                    notice = error.message ?: "Couldn't prepare a safe replacement; no file was changed."
                                }
                                askingCoder = false
                            }
                        }
                    }) { Text(if (askingCoder) "Sending…" else "Send one file & get replacement") } },
                    dismissButton = { TextButton(enabled = !askingCoder, onClick = { confirmCoderPatchAssist = false; coderPatchRequest = null }) { Text("Cancel") } },
                )
            }
            if (patchComposerOpen) {
                AlertDialog(
                    onDismissRequest = { patchComposerOpen = false; patchTargetMenuOpen = false },
                    title = { Text("Prepare a local file patch") },
                    text = {
                        Column {
                            Text("Choose one existing visible file, then paste the full replacement from the suggestion. Nothing is written until you inspect both versions and confirm. One patch can be undone locally.", fontSize = 13.sp)
                            androidx.compose.foundation.layout.Box(Modifier.padding(top = 8.dp)) {
                                OutlinedButton(onClick = { patchTargetMenuOpen = true }) {
                                    Text(if (patchTargetPath.isBlank()) "Choose an existing project file" else patchTargetPath)
                                }
                                DropdownMenu(expanded = patchTargetMenuOpen, onDismissRequest = { patchTargetMenuOpen = false }) {
                                    projectFilePaths.forEach { path ->
                                        DropdownMenuItem(text = { Text(path) }, onClick = { patchTargetPath = path; patchTargetMenuOpen = false })
                                    }
                                }
                            }
                            OutlinedTextField(
                                value = patchAfterText,
                                onValueChange = { patchAfterText = it.take(WebForgeRepository.MAX_REVIEWED_PATCH_CHARS) },
                                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                                label = { Text("Full replacement file contents") },
                                placeholder = { Text("Paste the proposed file contents") },
                                minLines = 5,
                                maxLines = 10,
                                supportingText = { Text("${patchAfterText.length}/${WebForgeRepository.MAX_REVIEWED_PATCH_CHARS}; files over this limit use the regular editor") },
                            )
                        }
                    },
                    confirmButton = {
                        TextButton(enabled = patchTargetPath.isNotBlank() && patchAfterText.isNotEmpty(), onClick = {
                            val project = selected ?: return@TextButton
                            val path = patchTargetPath
                            val replacement = patchAfterText
                            val unsavedEditor = editorValueFor(path)
                            scope.launch {
                                runCatching {
                                    withContext(Dispatchers.IO) { repository.prepareCoderPatch(project.id, path, replacement) }
                                }.map { patch ->
                                    if (unsavedEditor != null && unsavedEditor != patch.before) {
                                        throw IllegalStateException("Save or discard your current edits to $path before preparing a patch.")
                                    }
                                    patch
                                }.onSuccess { patch -> pendingCoderPatch = patch; patchComposerOpen = false; notice = "Review the complete before/after text for ${patch.targetPath}." }
                                    .onFailure { notice = it.message ?: "Couldn't prepare this local patch." }
                            }
                        }) { Text("Review before/after") }
                    },
                    dismissButton = { TextButton(onClick = { patchComposerOpen = false; patchTargetMenuOpen = false }) { Text("Cancel") } },
                )
            }
            pendingCoderPatch?.let { patch ->
                AlertDialog(
                    onDismissRequest = { if (!applyingCoderPatch) pendingCoderPatch = null },
                    title = { Text("Review patch: ${patch.targetPath}") },
                    text = {
                        Column(Modifier.height(360.dp).fillMaxWidth().verticalScroll(rememberScrollState())) {
                            Text("Source SHA-256: ${patch.beforeSha256}", color = WebForgeMuted, fontSize = 10.sp)
                            Text("BEFORE — full current file (${patch.before.length} characters)", color = WebForgeMint, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
                            Text(patch.before.ifEmpty { "(empty file)" }, color = Color.White, fontSize = 11.sp, lineHeight = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                            Text("AFTER — full replacement (${patch.after.length} characters)", color = WebForgeMint, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
                            Text(patch.after.ifEmpty { "(empty file)" }, color = Color.White, fontSize = 11.sp, lineHeight = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                        }
                    },
                    confirmButton = {
                        TextButton(enabled = !applyingCoderPatch, onClick = {
                            val project = selected ?: return@TextButton
                            applyingCoderPatch = true
                            scope.launch {
                                runCatching { withContext(Dispatchers.IO) { repository.applyCoderPatch(project.id, patch); repository.readProjectFile(project.id, patch.targetPath) } }
                                    .onSuccess { saved -> updateEditorValue(patch.targetPath, saved); pendingCoderPatch = null; patchUndoAvailable = true; refreshProjectFiles(project.id); refreshProjects(); notice = "Applied the reviewed patch to ${patch.targetPath} on this device. You can undo it below." }
                                    .onFailure { pendingCoderPatch = null; notice = it.message ?: "Patch not applied; prepare a fresh review." }
                                applyingCoderPatch = false
                            }
                        }) { Text(if (applyingCoderPatch) "Applying…" else "Apply this exact patch") }
                    },
                    dismissButton = { TextButton(enabled = !applyingCoderPatch, onClick = { pendingCoderPatch = null }) { Text("Cancel") } },
                )
            }
            if (patchUndoAvailable) {
                OutlinedButton(
                    onClick = {
                        val project = selected ?: return@OutlinedButton
                        scope.launch {
                            runCatching { withContext(Dispatchers.IO) { repository.undoCoderPatch(project.id) } }
                                .onSuccess { result ->
                                    if (result == null) patchUndoAvailable = false
                                    else {
                                        updateEditorValue(result.targetPath, result.content)
                                        patchUndoAvailable = withContext(Dispatchers.IO) { repository.hasPendingCoderUndo(project.id) }
                                        refreshProjectFiles(project.id)
                                        refreshProjects()
                                        notice = if (result.restored) "Restored the saved version of ${result.targetPath}." else "No patch write was needed; its temporary undo record was cleared."
                                    }
                                }
                                .onFailure { notice = it.message ?: "Couldn't undo the reviewed patch." }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                ) { Text("Undo last reviewed patch") }
            }
            Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text("MYRA Coder task list", color = WebForgeMint, fontWeight = FontWeight.SemiBold)
                    Text("Project-scoped and saved only on this device. This mirrors update_todos: the complete ordered list is replaced on each edit; no model or tools run automatically.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp, bottom = 6.dp))
                    OutlinedTextField(value = newCoderTodo, onValueChange = { newCoderTodo = it.take(WebForgeRepository.MAX_CODER_TODO_CHARS) }, modifier = Modifier.fillMaxWidth(), label = { Text("New task") }, singleLine = true)
                    Button(onClick = {
                        val project = selected ?: return@Button
                        val text = newCoderTodo.trim()
                        val next = coderTodos + WebForgeTodo(java.util.UUID.randomUUID().toString(), text, WebForgeTodoStatus.PENDING)
                        scope.launch {
                            runCatching { withContext(Dispatchers.IO) { repository.replaceCoderTodos(project.id, next); repository.loadCoderTodos(project.id) } }
                                .onSuccess { coderTodos = it; newCoderTodo = ""; notice = "Saved the project task list locally." }
                                .onFailure { notice = it.message ?: "Couldn't save the project task list." }
                        }
                    }, enabled = newCoderTodo.isNotBlank() && coderTodos.size < WebForgeRepository.MAX_CODER_TODOS, modifier = Modifier.padding(top = 4.dp)) { Text("Add task") }
                    if (coderTodos.isEmpty()) Text("No tasks yet. Add a task to start this project's list.", color = WebForgeMuted, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                    coderTodos.forEach { todo ->
                        Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                            Text(todo.content, color = Color.White, fontSize = 13.sp, lineHeight = 18.sp)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                androidx.compose.foundation.layout.Box {
                                    OutlinedButton(onClick = { openTodoMenu = todo.id }) { Text(todo.status.value.replace('_', ' ')) }
                                    DropdownMenu(expanded = openTodoMenu == todo.id, onDismissRequest = { openTodoMenu = null }) {
                                        WebForgeTodoStatus.entries.forEach { status ->
                                            DropdownMenuItem(text = { Text(status.value.replace('_', ' ')) }, onClick = {
                                                val next = if (status == WebForgeTodoStatus.IN_PROGRESS) coderTodos.map { item ->
                                                    item.copy(status = if (item.id == todo.id) status else if (item.status == WebForgeTodoStatus.IN_PROGRESS) WebForgeTodoStatus.PENDING else item.status)
                                                } else coderTodos.map { item -> if (item.id == todo.id) item.copy(status = status) else item }
                                                openTodoMenu = null
                                                val project = selected ?: return@DropdownMenuItem
                                                scope.launch {
                                                    runCatching { withContext(Dispatchers.IO) { repository.replaceCoderTodos(project.id, next); repository.loadCoderTodos(project.id) } }
                                                        .onSuccess { coderTodos = it; notice = "Saved task status locally." }
                                                        .onFailure { notice = it.message ?: "Couldn't save the project task list." }
                                                }
                                            })
                                        }
                                    }
                                }
                                IconButton(onClick = {
                                    if (coderTodos.size <= 1) { notice = "Keep at least one task in the project list."; return@IconButton }
                                    val next = coderTodos.filterNot { it.id == todo.id }
                                    val project = selected ?: return@IconButton
                                    scope.launch {
                                        runCatching { withContext(Dispatchers.IO) { repository.replaceCoderTodos(project.id, next); repository.loadCoderTodos(project.id) } }
                                            .onSuccess { coderTodos = it; notice = "Removed the task from this project's list." }
                                            .onFailure { notice = it.message ?: "Couldn't save the project task list." }
                                    }
                                }, enabled = coderTodos.size > 1) { Icon(Icons.Default.Delete, contentDescription = "Remove task", tint = WebForgeMuted) }
                            }
                        }
                    }
                }
            }
            Card(colors = CardDefaults.cardColors(containerColor = WebForgePanel), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text("MYRA Coder project notes", color = WebForgeMint, fontWeight = FontWeight.SemiBold)
                    Text("Create a local MYRA_CODER.md starter from visible filenames and folders. It does not read file contents, run commands, or contact a model.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp, modifier = Modifier.padding(top = 4.dp))
                    val guideExists = "MYRA_CODER.md" in projectFilePaths
                    OutlinedButton(
                        onClick = {
                            val project = selected ?: return@OutlinedButton
                            if (guideExists) {
                                openProjectFile("MYRA_CODER.md")
                            } else {
                                scope.launch {
                                    runCatching { withContext(Dispatchers.IO) { repository.scaffoldCoderGuide(project.id) } }
                                        .onSuccess { created ->
                                            refreshProjectFiles(project.id)
                                            if (created) {
                                                notice = "Created MYRA_CODER.md locally; review and edit it before relying on the notes."
                                                openProjectFile("MYRA_CODER.md")
                                            } else {
                                                notice = "MYRA_CODER.md already exists; it was left unchanged."
                                                openProjectFile("MYRA_CODER.md")
                                            }
                                        }
                                        .onFailure { notice = it.message ?: "Couldn't create the local project guide." }
                                }
                            }
                        },
                        modifier = Modifier.padding(top = 4.dp),
                    ) { Text(if (guideExists) "Open MYRA_CODER.md" else "Create MYRA_CODER.md") }
                }
            }
            OutlinedButton(
                onClick = {
                    val project = selected ?: return@OutlinedButton
                    pendingExport = project
                    exportLauncher.launch("${project.id}.zip")
                },
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            ) { Text("Export project ZIP") }
            Text("Saves visible project files to a ZIP through Android's file picker. Hidden files and dependency folders are excluded; nothing is uploaded.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp)
            Spacer(Modifier.height(8.dp))
            Text("PROJECT FILES", color = WebForgeMint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
            Text("Open and edit project-relative files, including nested folders. Files stay on this device.", color = WebForgeMuted, fontSize = 11.sp)
            projectFilePaths.forEach { path ->
                OutlinedButton(onClick = { openProjectFile(path) }, modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) { Text(path, modifier = Modifier.fillMaxWidth()) }
            }
            OutlinedTextField(value = extraFilePath, onValueChange = { extraFilePath = it.take(180) }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), label = { Text("Project-relative file path") }, placeholder = { Text("README.md or assets/logo.txt") }, singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { if (extraFilePath.isNotBlank()) openProjectFile(extraFilePath) }, enabled = extraFilePath.isNotBlank()) { Text("Open file") }
                Button(onClick = {
                    val project = selected ?: return@Button
                    val path = extraFilePath
                    val content = extraFileContent
                    scope.launch {
                        runCatching { withContext(Dispatchers.IO) { repository.saveProjectFile(project.id, path, content) } }
                            .onSuccess { notice = "Saved $path locally. Nothing was sent or published."; refreshProjectFiles(project.id); refreshProjects() }
                            .onFailure { notice = it.message ?: "Couldn't save this project file." }
                    }
                }, enabled = extraFilePath.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = WebForgeMint, contentColor = Color(0xFF0B0F16))) { Text("Save file") }
            }
            if (extraFilePath.isNotBlank()) CodeField(extraFilePath, extraFileContent, { extraFileContent = it })
            Spacer(Modifier.height(8.dp))
            Text("Core preview files", color = WebForgeMuted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            CodeField("index.html", files.html, { files = files.copy(html = it) })
            CodeField("css/style.css", files.css, { files = files.copy(css = it) })
            CodeField("js/script.js", files.js, { files = files.copy(js = it) })
            if (showPreview) {
                Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("OFFLINE PREVIEW", color = WebForgeMint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
                    OutlinedButton(onClick = { previewSource = WebForgeRepository.previewHtml(files) }) { Text("Refresh preview") }
                }
                Text("This preview blocks network requests, external navigation, forms, and frames. JavaScript runs only inside the isolated preview with no native bridge.", color = WebForgeMuted, fontSize = 11.sp, lineHeight = 16.sp)
                AndroidView(
                    modifier = Modifier.fillMaxWidth().height(400.dp).padding(top = 6.dp).background(Color.White, RoundedCornerShape(12.dp)),
                    factory = { viewContext ->
                        WebView(viewContext).apply {
                            setBackgroundColor(AndroidColor.WHITE)
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = false
                            settings.databaseEnabled = false
                            settings.allowFileAccess = false
                            settings.allowContentAccess = false
                            settings.allowFileAccessFromFileURLs = false
                            settings.allowUniversalAccessFromFileURLs = false
                            settings.setSupportMultipleWindows(false)
                            settings.javaScriptCanOpenWindowsAutomatically = false
                            webViewClient = object : WebViewClient() {
                                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true
                                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse =
                                    WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                            }
                        }
                    },
                    update = { view ->
                        if (view.tag != previewSource) {
                            view.tag = previewSource
                            view.loadDataWithBaseURL("https://preview.myra.local/", previewSource, "text/html", "UTF-8", null)
                        }
                    },
                    onRelease = { view -> view.stopLoading(); view.removeAllViews(); view.destroy() },
                )
            }
        }
    }
}

@Composable
private fun CodeField(label: String, value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = { onValueChange(it.take(WebForgeRepository.MAX_FILE_CHARS)) },
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        label = { Text(label) },
        minLines = when (label) { "index.html" -> 8; "css/style.css" -> 5; else -> 4 },
        maxLines = 14,
        supportingText = { Text("${value.length}/${WebForgeRepository.MAX_FILE_CHARS} characters") },
    )
}
