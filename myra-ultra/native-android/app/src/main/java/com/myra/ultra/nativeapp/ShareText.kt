package com.myra.ultra.nativeapp

internal object ShareTextData {
    const val MAX_LENGTH = 4_000

    fun normalize(raw: String): String? = raw.trim().take(MAX_LENGTH).takeIf(String::isNotEmpty)
}
