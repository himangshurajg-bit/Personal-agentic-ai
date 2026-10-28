package dev.personalagent.personal_assistant

/**
 * Narrow, best-effort gate for the Xiaomi OS3 Super Island extension.
 * The build opt-in is intentionally separate from device capability: it is a
 * maintainer-controlled switch for Xiaomi-approved/whitelisted testing, not proof
 * that Xiaomi has granted this app permission.
 */
internal fun canUseHyperOsIsland(
    buildOptIn: Boolean,
    manufacturer: String,
    brand: String,
    islandSystemFeature: Boolean,
    focusProtocolVersion: Int,
): Boolean {
    val xiaomiFamily = setOf("xiaomi", "redmi", "poco")
    return buildOptIn &&
        (manufacturer.trim().lowercase() in xiaomiFamily || brand.trim().lowercase() in xiaomiFamily) &&
        islandSystemFeature &&
        focusProtocolVersion == HYPEROS_ISLAND_PROTOCOL_VERSION
}

internal const val HYPEROS_ISLAND_PROTOCOL_VERSION = 3
internal const val HYPEROS_ISLAND_PARAM_EXTRA = "miui.focus.param"
internal const val HYPEROS_ISLAND_PICS_EXTRA = "miui.focus.pics"
internal const val HYPEROS_ISLAND_APP_ICON_KEY = "miui.focus.pic_personal_ai"

/**
 * Return a compact, generic payload for a known task state only. The function
 * deliberately accepts no task title, prompt, account name, or arbitrary text.
 * The layout uses Xiaomi's documented OS2/OS3 summary template 2 (image-text 1
 * plus text) and its documented static-icon small-island component.
 */
internal fun buildHyperOsIslandPayload(
    buildOptIn: Boolean,
    manufacturer: String,
    brand: String,
    islandSystemFeature: Boolean,
    focusProtocolVersion: Int,
    standardTaskStatus: String,
): String? {
    if (!canUseHyperOsIsland(
            buildOptIn,
            manufacturer,
            brand,
            islandSystemFeature,
            focusProtocolVersion,
        )) return null

    val islandStatus = when (standardTaskStatus) {
        "Preparing your request" -> "Preparing"
        "Waiting for the selected AI" -> "Waiting"
        "Running the on-device model" -> "On-device"
        "Receiving the reply" -> "Replying"
        else -> return null
    }

    // Keep the vendor payload aligned with the ordinary notification's five-minute
    // expiry. No user-provided content is interpolated into this JSON.
    return """{"param_v2":{"protocol":1,"business":"personal_ai_task","islandFirstFloat":false,"enableFloat":false,"updatable":true,"timeout":5,"filterWhenNoPermission":false,"param_island":{"islandProperty":1,"islandTimeout":300,"bigIslandArea":{"imageTextInfoLeft":{"type":1,"textInfo":{"title":"AI","content":"Task","showHighlightColor":false}},"textInfo":{"frontTitle":"Task","title":"$islandStatus","showHighlightColor":false}},"smallIslandArea":{"picInfo":{"type":1,"pic":"$HYPEROS_ISLAND_APP_ICON_KEY"}}},"baseInfo":{"type":2,"title":"Personal AI","content":"$islandStatus"}}}"""
}
