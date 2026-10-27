package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException

class WebForgeCoderPatchTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test fun modelPatchRequestCapturesOneVisibleFileAndStaleHashIsRejected() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Request")
        val initial = repository.prepareCoderPatchRequest(project.id, "index.html", "Improve the heading")
        assertEquals("index.html", initial.targetPath)
        assertEquals(repository.readProjectFile(project.id, "index.html"), initial.before)
        assertEquals(WebForgeRepository.sha256(initial.before), initial.beforeSha256)
        assertTrue(initial.requestText.contains("Improve the heading"))
        assertTrue(initial.requestText.contains(initial.before))
        assertTrue(runCatching { repository.prepareCoderPatchRequest(project.id, "../outside", "task") }.isFailure)

        val changed = initial.before + "<!-- concurrent change -->"
        repository.saveProjectFile(project.id, "index.html", changed)
        val error = runCatching {
            repository.prepareCoderPatch(project.id, "index.html", "proposed replacement", initial.beforeSha256)
        }.exceptionOrNull()
        assertTrue(error is IOException)
        assertEquals(changed, repository.readProjectFile(project.id, "index.html"))
    }

    @Test fun reviewedPatchAppliesExactlyAndCanBeUndoneAfterReload() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Patch")
        val before = repository.readProjectFile(project.id, "index.html")
        val after = before.replace("<h1>Patch</h1>", "<h1>Updated</h1>")
        val patch = repository.prepareCoderPatch(project.id, "index.html", after)

        assertEquals(before, patch.before)
        assertFalse(repository.hasPendingCoderUndo(project.id))
        repository.applyCoderPatch(project.id, patch)
        assertEquals(after, repository.readProjectFile(project.id, "index.html"))
        assertTrue(repository.hasPendingCoderUndo(project.id))
        assertFalse(repository.listProjectFiles(project.id).any { it.startsWith(".") || it.contains(".myra-coder") })

        val reopened = WebForgeRepository(temporaryFolder.root.resolve("projects"))
        val undo = reopened.undoCoderPatch(project.id)
        assertNotNull(undo)
        assertEquals("index.html", undo!!.targetPath)
        assertTrue(undo.restored)
        assertEquals(before, reopened.readProjectFile(project.id, "index.html"))
        assertFalse(reopened.hasPendingCoderUndo(project.id))
    }

    @Test fun patchRejectsStaleFileInsteadOfOverwritingNewerEdits() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Stale")
        val original = repository.readProjectFile(project.id, "index.html")
        val patch = repository.prepareCoderPatch(project.id, "index.html", original + "\n<!-- reviewed -->")
        repository.saveProjectFile(project.id, "index.html", original + "\n<!-- newer edit -->")

        val error = runCatching { repository.applyCoderPatch(project.id, patch) }.exceptionOrNull()
        assertTrue(error is IOException)
        assertTrue(repository.readProjectFile(project.id, "index.html").endsWith("<!-- newer edit -->"))
        assertFalse(repository.hasPendingCoderUndo(project.id))
    }

    @Test fun patchOnlyTargetsExistingVisibleFilesAndHasStrictSizeBounds() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Bounds")
        val invalidPaths = listOf("../outside.txt", ".hidden", "MYRA_CODER.md", "missing.txt", "/absolute")
        invalidPaths.forEach { path ->
            assertTrue("Expected rejection for $path", runCatching { repository.prepareCoderPatch(project.id, path, "new") }.isFailure)
        }
        assertTrue(runCatching {
            repository.prepareCoderPatch(project.id, "index.html", "x".repeat(WebForgeRepository.MAX_REVIEWED_PATCH_CHARS + 1))
        }.isFailure)
        val patch = repository.prepareCoderPatch(project.id, "index.html", "safe")
        assertTrue(runCatching {
            repository.applyCoderPatch(project.id, patch.copy(before = "x".repeat(WebForgeRepository.MAX_REVIEWED_PATCH_CHARS + 1)))
        }.isFailure)
    }

    @Test fun aSecondPatchWaitsUntilUndoIsResolved() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("OneUndo")
        val before = repository.readProjectFile(project.id, "index.html")
        val after = before + "\n<!-- first -->"
        repository.applyCoderPatch(project.id, repository.prepareCoderPatch(project.id, "index.html", after))
        val next = repository.prepareCoderPatch(project.id, "index.html", after + "\n<!-- second -->")

        assertTrue(runCatching { repository.applyCoderPatch(project.id, next) }.isFailure)
        val undo = repository.undoCoderPatch(project.id)
        assertTrue(undo!!.restored)
        repository.applyCoderPatch(project.id, repository.prepareCoderPatch(project.id, "index.html", after + "\n<!-- second -->"))
        assertTrue(repository.hasPendingCoderUndo(project.id))
    }

    @Test fun undoRefusesToOverwriteAFileChangedAfterPatch() {
        val repository = WebForgeRepository(temporaryFolder.newFolder("projects"))
        val project = repository.createProject("Conflict")
        val before = repository.readProjectFile(project.id, "index.html")
        val after = before + "\n<!-- applied -->"
        repository.applyCoderPatch(project.id, repository.prepareCoderPatch(project.id, "index.html", after))
        repository.saveProjectFile(project.id, "index.html", "newer external content")

        assertTrue(runCatching { repository.undoCoderPatch(project.id) }.isFailure)
        assertEquals("newer external content", repository.readProjectFile(project.id, "index.html"))
        assertTrue(repository.hasPendingCoderUndo(project.id))
    }
}
