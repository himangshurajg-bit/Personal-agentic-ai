package dev.personalagent.personal_assistant

import org.junit.Assert.*
import org.junit.Test

class VoiceSessionComponentsTest {
    @Test fun stoppingOrReplacingRecognizerInvalidatesOldCallbacks() {
        val epoch = RecognitionEpoch()
        val first = epoch.next()
        assertTrue(epoch.isCurrent(first))
        epoch.invalidate()
        assertFalse(epoch.isCurrent(first))
        val second = epoch.next()
        assertTrue(epoch.isCurrent(second))
        assertFalse(epoch.isCurrent(first))
    }

    @Test fun wakePhraseMatchIsLocalExactPrefixAndUnicodeSafe() {
        assertTrue(containsWakePhrase("Hey Personal AI, what time is it", "hey personal ai"))
        assertTrue(containsWakePhrase("  HEY PERSONAL AI  ", "hey personal ai"))
        assertFalse(containsWakePhrase("I said hey personal ai yesterday", "hey personal ai"))
        assertFalse(containsWakePhrase("hey personal", "hey personal ai"))
        assertTrue(containsWakePhrase("নমস্কাৰ ব্যক্তিগত সহায়ক", "নমস্কাৰ ব্যক্তিগত সহায়ক"))
    }

    @Test fun actionRegistryKeepsExternalActionsApprovalGated() {
        assertTrue(ActionRegistry.get("launch_app")!!.requiresApproval)
        assertTrue(ActionRegistry.get("web_search")!!.requiresApproval)
        assertTrue(ActionRegistry.get("prepare_message")!!.requiresApproval)
        assertNull(ActionRegistry.get("set_timer")) // handled by its separate reviewed flow
        assertNull(ActionRegistry.get("download_file")) // handled by its separate reviewed flow
        assertEquals("notification_access", ActionRegistry.get("read_notifications")!!.requiredPermission)
        assertNull(ActionRegistry.get("send_sms")) // native messaging only opens a draft; user sends it
        assertNull(ActionRegistry.get("make_call"))
    }

    @Test fun actionAuthorizationRequiresBothApprovalAndSpecialAccess() {
        val openApp = ActionRegistry.get("launch_app")!!
        assertFalse(openApp.authorized(approved = false, permissionGranted = true))
        assertTrue(openApp.authorized(approved = true, permissionGranted = true))
        val webSearch = ActionRegistry.get("web_search")!!
        assertFalse(webSearch.authorized(approved = false, permissionGranted = true))
        assertTrue(webSearch.authorized(approved = true, permissionGranted = true))
        val messageDraft = ActionRegistry.get("prepare_message")!!
        assertFalse(messageDraft.authorized(approved = false, permissionGranted = true))
        assertTrue(messageDraft.authorized(approved = true, permissionGranted = true))
        val notifications = ActionRegistry.get("read_notifications")!!
        assertFalse(notifications.authorized(approved = true, permissionGranted = false))
        assertFalse(notifications.authorized(approved = false, permissionGranted = true))
        assertTrue(notifications.authorized(approved = true, permissionGranted = true))
    }

    @Test fun unknownActionCannotBeExecuted() {
        assertNull(ActionRegistry.get("delete_files"))
        assertNull(ActionRegistry.get(null))
    }
}
