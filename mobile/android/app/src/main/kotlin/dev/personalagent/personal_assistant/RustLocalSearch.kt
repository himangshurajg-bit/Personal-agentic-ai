package dev.personalagent.personal_assistant

/** Thin JNI entry point; search data stays in-process on the device. */
internal object RustLocalSearch {
    init {
        System.loadLibrary("personal_local_search")
    }

    @JvmStatic
    external fun search(requestJson: String): String
}
