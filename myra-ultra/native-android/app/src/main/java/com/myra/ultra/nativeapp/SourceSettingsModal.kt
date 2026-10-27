package com.myra.ultra.nativeapp

import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/** Source HTML dialog overlay: full-window modal layer, dimmed backdrop, and bottom-sheet content. */
@Composable
internal fun SourceSettingsModal(
    onDismissRequest: () -> Unit,
    content: @Composable () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.let {
                it.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                it.setDimAmount(SourceSettingsPresentation.backdropDimAmount)
            }
        }
        Box(Modifier.fillMaxSize()) {
            content()
        }
    }
}
