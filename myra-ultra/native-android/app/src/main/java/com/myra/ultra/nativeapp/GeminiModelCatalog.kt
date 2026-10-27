package com.myra.ultra.nativeapp

/** Stable Gemini API models used by the native chat and file-analysis requests. */
internal object GeminiModelCatalog {
    data class Option(val id: String, val label: String, val note: String)

    val options = listOf(
        Option("gemini-3.8-flash", "Gemini 3.8 Flash", "Recommended · stable multimodal model"),
        Option("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite", "Lower-cost stable multimodal model"),
        Option("gemini-2.5-flash", "Gemini 2.5 Flash", "Legacy · access is limited to prior active users"),
    )

    const val DEFAULT_ID = "gemini-3.8-flash"
    private val ids = options.mapTo(linkedSetOf()) { it.id }

    fun resolveId(value: String?): String = value?.takeIf(ids::contains) ?: DEFAULT_ID
    fun option(id: String?): Option = options.first { it.id == resolveId(id) }
    fun endpoint(modelId: String, method: String): String {
        require(method == "generateContent" || method == "streamGenerateContent")
        val safeId = resolveId(modelId)
        return "https://generativelanguage.googleapis.com/v1beta/models/$safeId:$method"
    }
}
