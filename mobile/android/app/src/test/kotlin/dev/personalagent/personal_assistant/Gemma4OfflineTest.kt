package dev.personalagent.personal_assistant

import java.io.File
import java.net.URI
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Gemma4OfflineTest {
    @Test
    fun artifactIsPinnedToTheReviewedImmutableFile() {
        assertEquals("gemma-4-E2B-it", Gemma4Artifact.MODEL_ID)
        assertEquals("gemma-4-E2B-it.litertlm", Gemma4Artifact.MODEL_FILE)
        assertEquals("gemma-4-E4B-it.litertlm", Gemma4Artifact.PREVIOUS_MODEL_FILE)
        assertTrue(Gemma4Artifact.URL.contains("litert-community/gemma-4-E2B-it-litert-lm/resolve/${Gemma4Artifact.REVISION}/${Gemma4Artifact.MODEL_FILE}"))
        assertEquals("6e5c4f1e395deb959c494953478fa5cec4b8008f", Gemma4Artifact.REVISION)
        assertEquals(2_588_147_712L, Gemma4Artifact.MODEL_BYTES)
        assertEquals("181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c", Gemma4Artifact.SHA256)
        assertEquals(8, Gemma4Artifact.MIN_DEVICE_MEMORY_GB)
        assertEquals("0.18.1", Gemma4Artifact.LITERT_LM_VERSION)
        assertEquals("Apache-2.0", Gemma4Artifact.LICENSE)
    }

    @Test
    fun redirectsStayOnHttpsHuggingFaceDomains() {
        assertTrue(Gemma4Artifact.allowsRedirect(URI("https://huggingface.co/model")))
        assertTrue(Gemma4Artifact.allowsRedirect(URI("https://us.gcp.cdn.hf.co/signed/model")))
        assertFalse(Gemma4Artifact.allowsRedirect(URI("http://huggingface.co/model")))
        assertFalse(Gemma4Artifact.allowsRedirect(URI("https://huggingface.co.attacker.example/model")))
        assertFalse(Gemma4Artifact.allowsRedirect(URI("https://attacker.example/model")))
        assertFalse(Gemma4Artifact.allowsRedirect(URI("https://user@huggingface.co/model")))
    }

    @Test
    fun rangeAndPreflightPolicyRejectInvalidResumeState() {
        assertEquals(ByteRange(100, 199, 500), Gemma4TransferPolicy.parseContentRange("bytes 100-199/500"))
        assertNotNull(Gemma4TransferPolicy.parseContentRange("bytes 100-499/500"))
        assertEquals(null, Gemma4TransferPolicy.parseContentRange("bytes 100-600/500"))
        assertEquals(null, Gemma4TransferPolicy.parseContentRange("bytes */500"))
        assertEquals(120L, Gemma4TransferPolicy.resumeOffset(120L, 500L))
        assertEquals(null, Gemma4TransferPolicy.resumeOffset(0L, 500L))
        assertEquals(null, Gemma4TransferPolicy.resumeOffset(500L, 500L))
        val reserve = Gemma4Artifact.SAFETY_RESERVE_BYTES
        assertTrue(Gemma4TransferPolicy.hasEnoughSpace(reserve + 88L, 12L, 100L))
        assertFalse(Gemma4TransferPolicy.hasEnoughSpace(reserve + 87L, 12L, 100L))
    }

    @Test
    fun shaVerificationAndAtomicInstallRejectWrongBytes() {
        val directory = Files.createTempDirectory("gemma4-store-test").toFile()
        try {
            val part = File(directory, "candidate.part").apply { writeText("hello") }
            val target = File(directory, "candidate.litertlm")
            assertTrue(Gemma4FileIntegrity.verify(part, 5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"))
            Gemma4FileIntegrity.installAtomically(part, target, 5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
            assertTrue(target.isFile)
            assertEquals("hello", target.readText())
            assertFalse(part.exists())

            val badPart = File(directory, "bad.part").apply { writeText("wrong") }
            val stableContents = target.readText()
            try {
                Gemma4FileIntegrity.installAtomically(badPart, target, 5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
                throw AssertionError("bad artifact should not be installed")
            } catch (_: IllegalArgumentException) {
                assertEquals(stableContents, target.readText())
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun qualificationPromptsAreFixedAndCoverTheRequiredDomains() {
        assertTrue(Gemma4QualificationPrompts.find("english")!!.text.contains("Class 12/JEE"))
        assertTrue(Gemma4QualificationPrompts.find("assamese")!!.text.contains("অসমীয়াত"))
        assertTrue(Gemma4QualificationPrompts.find("arithmetic")!!.text.contains("newton"))
        assertTrue(Gemma4QualificationPrompts.find("jee")!!.text.contains("20 N"))
        assertEquals(null, Gemma4QualificationPrompts.find("user-provided-url-or-prompt"))
    }
}
