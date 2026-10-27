package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.io.File
import java.nio.file.Files
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream
import java.io.RandomAccessFile

class WebForgeRepositoryTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test fun projectNameBecomesSafeStableFolderId() {
        assertEquals("my-site-2", WebForgeRepository.projectId(" My Site 2 "))
        assertNull(WebForgeRepository.projectId("../outside"))
        assertNull(WebForgeRepository.projectId("name/child"))
        assertNull(WebForgeRepository.projectId(""))
        assertNull(WebForgeRepository.projectId("_hidden"))
    }

    @Test fun createListEditAndReloadProjectFilesLocally() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val first = repository.createProject("Portfolio")
        val second = repository.createProject("Portfolio")

        assertEquals("portfolio", first.id)
        assertEquals("portfolio-2", second.id)
        assertEquals(2, repository.listProjects().size)
        assertTrue(temporaryFolder.root.resolve("projects/portfolio/css").isDirectory)
        assertTrue(temporaryFolder.root.resolve("projects/portfolio/js").isDirectory)
        assertTrue(temporaryFolder.root.resolve("projects/portfolio/assets").isDirectory)
        assertTrue(repository.readProject(first.id).html.contains("<h1>Portfolio</h1>"))

        val edited = WebForgeFiles("<html><head></head><body><h1>Local</h1></body></html>", "h1 { color: teal; }", "document.title = 'Local';")
        repository.saveProject(first.id, edited)
        assertEquals(edited, repository.readProject(first.id))
    }

    @Test fun websiteStudioReviewFindsMissingStructureReferencesSelectorsAndCssBraces() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Review")
        val draft = WebForgeFiles(
            "<html><body><div id=\"known\"></div><link rel=\"stylesheet\" href=\"missing.css\"><script src=\"missing.js\"></script></body></html>",
            "main { color: teal;",
            "document.getElementById('absent'); document.querySelector('.missing');",
        )

        val issues = repository.reviewProject(project.id, draft)
        assertTrue(issues.any { it.contains("missing <!doctype html>") })
        assertTrue(issues.any { it.contains("missing a <title>") })
        assertTrue(issues.any { it.contains("missing a viewport meta tag") })
        assertTrue(issues.any { it.contains("local stylesheet file is missing") })
        assertTrue(issues.any { it.contains("local script file is missing") })
        assertTrue(issues.any { it.contains("no matching id") })
        assertTrue(issues.any { it.contains("no matching selector") })
        assertTrue(issues.any { it.contains("brace counts differ") })
        assertTrue(issues.size <= 12)
    }

    @Test fun websiteStudioReviewAcceptsBasicLocalProjectWithoutExecutingScripts() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Clean")
        val draft = WebForgeFiles(
            "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width\"><title>Clean</title><link rel=\"stylesheet\" href=\"css/style.css\"></head><body><main id=\"app\" class=\"panel\"></main><script src=\"js/script.js\"></script></body></html>",
            "body { color: teal; }",
            "document.getElementById('app'); document.querySelector('.panel');",
        )

        val savedBeforeReview = repository.readProject(project.id)
        assertTrue(repository.reviewProject(project.id, draft).isEmpty())
        assertEquals(savedBeforeReview, repository.readProject(project.id)) // review uses the current draft and makes no writes
    }

    @Test fun websiteStudioReviewAcceptsTheDefaultOfflinePreviewScaffold() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Starter")
        assertTrue(repository.reviewProject(project.id, repository.readProject(project.id)).isEmpty())
    }

    @Test fun websiteStudioReviewTreatsTraversalReferencesAsUnsafe() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("BoundedReview")
        val draft = WebForgeFiles(
            "<!doctype html><html><head><meta name=\"viewport\"><title>Safe</title><link rel=\"stylesheet\" href=\"../../outside.css\"></head><body></body></html>",
            "body {}",
            "",
        )
        val issues = repository.reviewProject(project.id, draft)
        assertTrue(issues.any { it.contains("missing or unsafe") })
    }

    @Test fun rejectsPathTraversalAndOversizedFiles() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Safe")
        assertTrue(runCatching { repository.readProject("../outside") }.isFailure)
        val tooLarge = "x".repeat(WebForgeRepository.MAX_FILE_CHARS + 1)
        assertTrue(runCatching { repository.saveProject(project.id, WebForgeFiles(tooLarge, "", "")) }.isFailure)
        assertEquals("Safe", repository.readProject(project.id).html.substringAfter("<h1>").substringBefore("</h1>"))
    }


    @Test fun listsReadsAndSavesArbitraryNestedProjectFiles() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Site")
        repository.saveProjectFile(project.id, "README.md", "# Site")
        repository.saveProjectFile(project.id, "assets/icons/logo.svg", "<svg/>")

        assertEquals(listOf("README.md", "assets/icons/logo.svg", "css/style.css", "index.html", "js/script.js"), repository.listProjectFiles(project.id))
        assertEquals("# Site", repository.readProjectFile(project.id, "README.md"))
        assertEquals("<svg/>", repository.readProjectFile(project.id, "assets/icons/logo.svg"))
        repository.saveProjectFile(project.id, "assets/icons/logo.svg", "<svg><title>updated</title></svg>")
        assertEquals("<svg><title>updated</title></svg>", repository.readProjectFile(project.id, "assets/icons/logo.svg"))
    }

    @Test fun arbitraryFileAccessRejectsTraversalMetadataHiddenAndSymlinkPaths() {
        val projects = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(projects)
        val project = repository.createProject("Site")
        val outside = temporaryFolder.newFile("outside.txt")
        outside.writeText("outside")
        Files.createSymbolicLink(File(projects, "site/escape.txt").toPath(), outside.toPath())

        listOf("../outside.txt", "assets/../../outside.txt", "/outside.txt", "C:/outside.txt", "assets\\bad.txt", ".hidden", "project-name.txt", "escape.txt").forEach { path ->
            assertTrue("path should be rejected: $path", runCatching { repository.readProjectFile(project.id, path) }.isFailure)
            assertTrue("path should not be saved: $path", runCatching { repository.saveProjectFile(project.id, path, "changed") }.isFailure)
        }
        assertEquals("outside", outside.readText())
    }

    @Test fun myraCoderAtFileContextPreparesNumberedLocalFilesWithoutChangingPrompt() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("CoderContext")
        repository.saveProjectFile(project.id, "src/main.kt", "fun main() {\n  println(\"hi\")\n}")
        repository.saveProjectFile(project.id, "README.md", "# Notes")

        val result = repository.prepareCoderContext(project.id, "Explain @src/main.kt and @README.md. Also see @src/main.kt")

        assertEquals(listOf("src/main.kt", "README.md"), result.attachedPaths)
        assertTrue(result.previewText.contains("--- FILE: src/main.kt ---\n1\tfun main() {\n2\t  println(\"hi\")\n3\t}"))
        assertTrue(result.previewText.contains("--- FILE: README.md ---\n1\t# Notes"))
        assertTrue(result.previewText.endsWith("Using the attached file context above, respond to:\nExplain @src/main.kt and @README.md. Also see @src/main.kt"))
        assertTrue(result.warnings.isEmpty())
        assertEquals("# Notes", repository.readProjectFile(project.id, "README.md"))
    }

    @Test fun myraCoderContextSkipsMissingHiddenTraversalMetadataAndDirectoryMentions() {
        val projects = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(projects)
        val project = repository.createProject("SafeContext")
        repository.saveProjectFile(project.id, "README.md", "visible")
        File(projects, "${project.id}/assets/.private/secret.txt").apply { parentFile?.mkdirs(); writeText("hidden-secret-marker") }

        val result = repository.prepareCoderContext(project.id, "Check @README.md @missing.txt @../outside @project-name.txt @assets @assets/.private/secret.txt")

        assertEquals(listOf("README.md"), result.attachedPaths)
        assertTrue(result.warnings.size >= 4)
        assertFalse(result.previewText.contains("hidden-secret-marker"))
    }

    @Test fun coderGuideScaffoldUsesVisibleLayoutOnlyAndPreservesExistingNotes() {
        val projects = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(projects)
        val project = repository.createProject("Guide Site")
        repository.saveProjectFile(project.id, "src/Main.kt", "private source marker must not be copied")
        repository.saveProjectFile(project.id, "package-lock.json", "lock data is not read")
        val hidden = File(projects, "guide-site/.private/secret.kt")
        hidden.parentFile?.mkdirs()
        hidden.writeText("hidden source marker")

        assertTrue(repository.scaffoldCoderGuide(project.id))
        val guide = repository.readProjectFile(project.id, "MYRA_CODER.md")
        assertTrue(guide.contains("**Project:** Guide Site"))
        assertTrue("generated guide: $guide", guide.contains("Kotlin"))
        assertTrue(guide.contains("**Package manager:** npm"))
        assertTrue(guide.contains("- `src/`"))
        assertFalse(guide.contains(".private"))
        assertFalse(guide.contains("private source marker"))
        assertFalse(guide.contains("hidden source marker"))

        repository.saveProjectFile(project.id, "MYRA_CODER.md", "Owner-authored notes")
        assertFalse(repository.scaffoldCoderGuide(project.id))
        assertEquals("Owner-authored notes", repository.readProjectFile(project.id, "MYRA_CODER.md"))
    }

    @Test fun myraCoderContextBoundsFileCountAndCombinedContent() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("ContextLimits")
        repeat(WebForgeRepository.MAX_CODER_CONTEXT_FILES + 1) { index ->
            repository.saveProjectFile(project.id, "f$index.txt", "file-$index")
        }
        val task = (0..WebForgeRepository.MAX_CODER_CONTEXT_FILES).joinToString(" ") { "@f$it.txt" }

        val result = repository.prepareCoderContext(project.id, task)

        assertEquals(WebForgeRepository.MAX_CODER_CONTEXT_FILES, result.attachedPaths.size)
        assertTrue(result.warnings.any { it.contains("Only the first") })
        assertTrue(runCatching { repository.prepareCoderContext(project.id, "x".repeat(4_001)) }.isFailure)

        repository.saveProjectFile(project.id, "large.txt", "x".repeat(WebForgeRepository.MAX_CODER_CONTEXT_CHARS + 1))
        val oversized = repository.prepareCoderContext(project.id, "@large.txt")
        assertTrue(oversized.attachedPaths.isEmpty())
        assertTrue(oversized.warnings.any { it.contains("combined Coder context exceeds") })
    }

    @Test fun arbitraryFileWritesEnforceCharacterAndFileCountLimits() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Bounded")
        assertTrue(runCatching { repository.saveProjectFile(project.id, "notes.txt", "x".repeat(WebForgeRepository.MAX_FILE_CHARS + 1)) }.isFailure)
        repeat(WebForgeRepository.MAX_PROJECT_FILES - repository.listProjectFiles(project.id).size) { index ->
            repository.saveProjectFile(project.id, "assets/file-$index.txt", "ok")
        }
        assertTrue(runCatching { repository.saveProjectFile(project.id, "extra.txt", "overflow") }.isFailure)
    }

    @Test fun exportsNestedProjectFilesAsBoundedZipAndExcludesHiddenOrExternalFiles() {
        val projects = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(projects)
        val project = repository.createProject("Export")
        repository.saveProjectFile(project.id, "assets/icons/logo.svg", "<svg>ok</svg>")
        val binary = File(projects, "export/assets/pixel.bin")
        binary.writeBytes(byteArrayOf(0, 1, 2, -1))
        val hidden = File(projects, "export/.private/secret.txt")
        hidden.parentFile?.mkdirs()
        hidden.writeText("hidden-secret-marker")
        val outside = temporaryFolder.newFile("outside.txt")
        outside.writeText("outside")
        Files.createSymbolicLink(File(projects, "export/assets/outside.txt").toPath(), outside.toPath())

        val output = ByteArrayOutputStream()
        val count = repository.exportProjectZip(project.id, output)
        val entries = mutableMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(output.toByteArray())).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                entries[entry.name] = zip.readBytes()
            }
        }
        assertEquals(count, entries.size)
        assertTrue(entries.keys.containsAll(listOf("index.html", "css/style.css", "js/script.js", "assets/icons/logo.svg", "assets/pixel.bin")))
        assertFalse(entries.keys.any { it.startsWith(".") || it.contains("/.") || it.contains("outside") })
        assertEquals(byteArrayOf(0, 1, 2, -1).toList(), entries.getValue("assets/pixel.bin").toList())
        assertEquals("outside", outside.readText())
    }

    @Test fun zipExportRejectsOversizedFilesBeforeWriting() {
        val projects = temporaryFolder.newFolder("projects")
        val repository = WebForgeRepository(projects)
        val project = repository.createProject("Big")
        val huge = File(projects, "big/assets/huge.bin")
        RandomAccessFile(huge, "rw").use { it.setLength(WebForgeRepository.MAX_EXPORT_FILE_BYTES + 1) }
        val output = ByteArrayOutputStream()
        assertTrue(runCatching { repository.exportProjectZip(project.id, output) }.exceptionOrNull() is IOException)
        assertEquals(0, output.size())
    }

    @Test fun previewKeepsFilesTogetherAndEnforcesOfflinePolicy() {
        val result = WebForgeRepository.previewHtml(WebForgeFiles("<main>hello</main>", "main { color: teal; }", "document.title='hello';"))
        assertTrue(result.contains("default-src 'none'"))
        assertTrue(result.contains("connect-src 'none'"))
        assertTrue(result.contains("main { color: teal; }"))
        assertTrue(result.contains("document.title='hello';"))
        assertTrue(result.contains("<main>hello</main>"))
        assertFalse(result.contains("<iframe"))
    }

    @Test fun duplicateProjectNamesDoNotOverwriteExistingProject() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val original = repository.createProject("site")
        repository.saveProject(original.id, WebForgeFiles("original", "", ""))
        repository.createProject("site")
        assertEquals("original", repository.readProject("site").html)
        assertEquals(2, repository.listProjects().size)
    }

    @Test fun rejectsProjectCountOverflow() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        repeat(WebForgeRepository.MAX_PROJECTS) { repository.createProject("p$it") }
        val error = runCatching { repository.createProject("one-too-many") }.exceptionOrNull()
        assertNotNull(error)
        assertTrue(error is IllegalStateException)
    }
}
