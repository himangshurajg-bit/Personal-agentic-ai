package com.myra.ultra.nativeapp

/** Language choices ported from the prototype language catalog; model output follows this setting. */
internal data class LanguageOption(val code: String, val englishName: String, val nativeName: String) {
    val label: String get() = if (englishName == nativeName) englishName else "$englishName · $nativeName"
}

internal object LanguagePreference {
    val options = listOf(
        LanguageOption("hi", "Hindi", "हिन्दी"),
        LanguageOption("en-IN", "English (India)", "English (India)"),
        LanguageOption("bn", "Bengali", "বাংলা"),
        LanguageOption("te", "Telugu", "తెలుగు"),
        LanguageOption("mr", "Marathi", "मराठी"),
        LanguageOption("ta", "Tamil", "தமிழ்"),
        LanguageOption("gu", "Gujarati", "ગુજરાતી"),
        LanguageOption("kn", "Kannada", "ಕನ್ನಡ"),
        LanguageOption("ml", "Malayalam", "മലയാളം"),
        LanguageOption("pa", "Punjabi", "ਪੰਜਾਬੀ"),
        LanguageOption("or", "Odia", "ଓଡ଼ିଆ"),
        LanguageOption("as", "Assamese", "অসমীয়া"),
        LanguageOption("ur", "Urdu", "اردو"),
        LanguageOption("ne", "Nepali", "नेपाली"),
        LanguageOption("sa", "Sanskrit", "संस्कृतम्"),
        LanguageOption("sd", "Sindhi", "سنڌي"),
        LanguageOption("ks", "Kashmiri", "کٲشُر"),
        LanguageOption("kok", "Konkani", "कोंकणी"),
        LanguageOption("mai", "Maithili", "मैथिली"),
        LanguageOption("doi", "Dogri", "डोगरी"),
        LanguageOption("mni", "Manipuri (Meitei)", "ꯃꯤꯇꯩꯂꯣꯟ"),
        LanguageOption("brx", "Bodo", "बड़ो"),
        LanguageOption("sat", "Santali", "ᱥᱟᱱᱛᱟᱲᱤ"),
        LanguageOption("bho", "Bhojpuri", "भोजपुरी"),
        LanguageOption("raj", "Rajasthani", "राजस्थानी"),
        LanguageOption("hne", "Chhattisgarhi", "छत्तीसगढ़ी"),
        LanguageOption("mag", "Magahi", "मगही"),
        LanguageOption("awa", "Awadhi", "अवधी"),
        LanguageOption("tcy", "Tulu", "ತುಳು"),
        LanguageOption("en-US", "English (US)", "English (US)"),
        LanguageOption("en-GB", "English (UK)", "English (UK)"),
        LanguageOption("en-AU", "English (Australia)", "English (Australia)"),
        LanguageOption("es", "Spanish", "Español"),
        LanguageOption("es-MX", "Spanish (Mexico)", "Español (México)"),
        LanguageOption("fr", "French", "Français"),
        LanguageOption("fr-CA", "French (Canada)", "Français (Canada)"),
        LanguageOption("de", "German", "Deutsch"),
        LanguageOption("it", "Italian", "Italiano"),
        LanguageOption("pt-BR", "Portuguese (Brazil)", "Português (Brasil)"),
        LanguageOption("pt-PT", "Portuguese (Portugal)", "Português (Portugal)"),
        LanguageOption("nl", "Dutch", "Nederlands"),
        LanguageOption("sv", "Swedish", "Svenska"),
        LanguageOption("da", "Danish", "Dansk"),
        LanguageOption("no", "Norwegian", "Norsk"),
        LanguageOption("fi", "Finnish", "Suomi"),
        LanguageOption("is", "Icelandic", "Íslenska"),
        LanguageOption("ru", "Russian", "Русский"),
        LanguageOption("uk", "Ukrainian", "Українська"),
        LanguageOption("pl", "Polish", "Polski"),
        LanguageOption("cs", "Czech", "Čeština"),
        LanguageOption("sk", "Slovak", "Slovenčina"),
        LanguageOption("hu", "Hungarian", "Magyar"),
        LanguageOption("ro", "Romanian", "Română"),
        LanguageOption("bg", "Bulgarian", "Български"),
        LanguageOption("el", "Greek", "Ελληνικά"),
        LanguageOption("sr", "Serbian", "Српски"),
        LanguageOption("hr", "Croatian", "Hrvatski"),
        LanguageOption("bs", "Bosnian", "Bosanski"),
        LanguageOption("sl", "Slovenian", "Slovenščina"),
        LanguageOption("mk", "Macedonian", "Македонски"),
        LanguageOption("sq", "Albanian", "Shqip"),
        LanguageOption("lt", "Lithuanian", "Lietuvių"),
        LanguageOption("lv", "Latvian", "Latviešu"),
        LanguageOption("et", "Estonian", "Eesti"),
        LanguageOption("be", "Belarusian", "Беларуская"),
        LanguageOption("ca", "Catalan", "Català"),
        LanguageOption("eu", "Basque", "Euskara"),
        LanguageOption("gl", "Galician", "Galego"),
        LanguageOption("ga", "Irish", "Gaeilge"),
        LanguageOption("cy", "Welsh", "Cymraeg"),
        LanguageOption("gd", "Scottish Gaelic", "Gàidhlig"),
        LanguageOption("mt", "Maltese", "Malti"),
        LanguageOption("lb", "Luxembourgish", "Lëtzebuergesch"),
        LanguageOption("br", "Breton", "Brezhoneg"),
        LanguageOption("la", "Latin", "Latina"),
        LanguageOption("eo", "Esperanto", "Esperanto"),
        LanguageOption("zh-CN", "Chinese (Mandarin, Simplified)", "简体中文"),
        LanguageOption("zh-TW", "Chinese (Traditional)", "繁體中文"),
        LanguageOption("yue", "Cantonese", "粵語"),
        LanguageOption("ja", "Japanese", "日本語"),
        LanguageOption("ko", "Korean", "한국어"),
        LanguageOption("vi", "Vietnamese", "Tiếng Việt"),
        LanguageOption("th", "Thai", "ไทย"),
        LanguageOption("id", "Indonesian", "Bahasa Indonesia"),
        LanguageOption("ms", "Malay", "Bahasa Melayu"),
        LanguageOption("fil", "Filipino (Tagalog)", "Filipino"),
        LanguageOption("my", "Burmese", "မြန်မာ"),
        LanguageOption("km", "Khmer", "ខ្មែរ"),
        LanguageOption("lo", "Lao", "ລາວ"),
        LanguageOption("si", "Sinhala", "සිංහල"),
        LanguageOption("mn", "Mongolian", "Монгол"),
        LanguageOption("bo", "Tibetan", "བོད་སྐད།"),
        LanguageOption("ug", "Uyghur", "ئۇيغۇرچە"),
        LanguageOption("jv", "Javanese", "Basa Jawa"),
        LanguageOption("su", "Sundanese", "Basa Sunda"),
        LanguageOption("ceb", "Cebuano", "Cebuano"),
        LanguageOption("ilo", "Ilocano", "Ilokano"),
        LanguageOption("hmn", "Hmong", "Hmoob"),
        LanguageOption("ar", "Arabic", "العربية"),
        LanguageOption("ar-EG", "Arabic (Egypt)", "العربية (مصر)"),
        LanguageOption("he", "Hebrew", "עברית"),
        LanguageOption("fa", "Persian (Farsi)", "فارسی"),
        LanguageOption("tr", "Turkish", "Türkçe"),
        LanguageOption("ku", "Kurdish", "Kurdî"),
        LanguageOption("ps", "Pashto", "پښتو"),
        LanguageOption("prs", "Dari", "دری"),
        LanguageOption("az", "Azerbaijani", "Azərbaycanca"),
        LanguageOption("hy", "Armenian", "Հայերեն"),
        LanguageOption("ka", "Georgian", "ქართული"),
        LanguageOption("kk", "Kazakh", "Қазақша"),
        LanguageOption("uz", "Uzbek", "Oʻzbekcha"),
        LanguageOption("ky", "Kyrgyz", "Кыргызча"),
        LanguageOption("tg", "Tajik", "Тоҷикӣ"),
        LanguageOption("tk", "Turkmen", "Türkmençe"),
        LanguageOption("tt", "Tatar", "Татарча"),
        LanguageOption("sw", "Swahili", "Kiswahili"),
        LanguageOption("am", "Amharic", "አማርኛ"),
        LanguageOption("ha", "Hausa", "Hausa"),
        LanguageOption("yo", "Yoruba", "Yorùbá"),
        LanguageOption("ig", "Igbo", "Igbo"),
        LanguageOption("zu", "Zulu", "isiZulu"),
        LanguageOption("xh", "Xhosa", "isiXhosa"),
        LanguageOption("af", "Afrikaans", "Afrikaans"),
        LanguageOption("st", "Sesotho", "Sesotho"),
        LanguageOption("tn", "Tswana", "Setswana"),
        LanguageOption("sn", "Shona", "chiShona"),
        LanguageOption("so", "Somali", "Soomaali"),
        LanguageOption("rw", "Kinyarwanda", "Ikinyarwanda"),
        LanguageOption("mg", "Malagasy", "Malagasy"),
        LanguageOption("ny", "Chichewa", "Chichewa"),
        LanguageOption("wo", "Wolof", "Wolof"),
        LanguageOption("ti", "Tigrinya", "ትግርኛ"),
        LanguageOption("om", "Oromo", "Afaan Oromoo"),
        LanguageOption("lg", "Luganda", "Luganda"),
        LanguageOption("ln", "Lingala", "Lingála"),
        LanguageOption("ff", "Fula", "Fulfulde"),
        LanguageOption("ber", "Berber (Tamazight)", "ⵜⴰⵎⴰⵣⵉⵖⵜ"),
        LanguageOption("ht", "Haitian Creole", "Kreyòl ayisyen"),
        LanguageOption("qu", "Quechua", "Runasimi"),
        LanguageOption("gn", "Guarani", "Avañeʼẽ"),
        LanguageOption("ay", "Aymara", "Aymar aru"),
        LanguageOption("haw", "Hawaiian", "ʻŌlelo Hawaiʻi"),
        LanguageOption("mi", "Maori", "Te Reo Māori"),
        LanguageOption("sm", "Samoan", "Gagana Samoa"),
        LanguageOption("to", "Tongan", "Lea faka-Tonga"),
        LanguageOption("fj", "Fijian", "Vosa Vakaviti"),
        LanguageOption("yi", "Yiddish", "ייִדיש"),
        LanguageOption("hi-Latn", "Hinglish (Hindi + English)", "Hinglish"),
    )
    const val AUTO_CODE = "auto"
    const val DEFAULT_CODE = AUTO_CODE
    val autoOption = LanguageOption(AUTO_CODE, "Auto — Hinglish", "")

    fun resolveCode(saved: String?): String {
        val value = saved?.trim().orEmpty()
        if (value.isEmpty() || value.equals(AUTO_CODE, ignoreCase = true) || value.equals("default", ignoreCase = true)) return AUTO_CODE
        if (value.equals("English", ignoreCase = true)) return "en-US"
        return options.firstOrNull { it.code.equals(value, ignoreCase = true) }?.code
            ?: options.firstOrNull { it.englishName.equals(value, ignoreCase = true) || it.nativeName.equals(value, ignoreCase = true) }?.code
            ?: AUTO_CODE
    }

    fun option(saved: String?): LanguageOption {
        val code = resolveCode(saved)
        return if (code == AUTO_CODE) autoOption else options.first { it.code == code }
    }

    fun optionForExactNameOrCode(value: String): LanguageOption? {
        val candidate = value.trim()
        if (candidate.isEmpty()) return null
        return options.firstOrNull {
            it.code.equals(candidate, ignoreCase = true) ||
                it.englishName.equals(candidate, ignoreCase = true) ||
                it.nativeName.equals(candidate, ignoreCase = true)
        }
    }

    /** The latest user message must directly request a persistent language change and name that exact choice. */
    fun hasExplicitChangeIntent(userText: String, code: String): Boolean {
        val option = options.firstOrNull { it.code == code } ?: return false
        val lower = userText.lowercase(java.util.Locale.ROOT)
        if (Regex("\\b(?:don't|do not|never|not)\\b.{0,36}\\b(?:change|switch|set|speak|reply|answer|use)\\b").containsMatchIn(lower)) return false
        if (Regex("^\\s*(?:if|when|maybe|whether|what if)\\b").containsMatchIn(lower)) return false

        fun isNamed(name: String): Boolean {
            val escaped = Regex.escape(name.lowercase(java.util.Locale.ROOT))
            return Regex("(?<![\\p{L}\\p{N}])$escaped(?![\\p{L}\\p{N}])").containsMatchIn(lower)
        }
        val namedMatches = options.flatMap { candidate ->
            listOf(candidate.englishName, candidate.nativeName).distinct()
                .filter { it.isNotBlank() }
                .flatMap { alias ->
                    val escaped = Regex.escape(alias.lowercase(java.util.Locale.ROOT))
                    Regex("(?<![\\p{L}\\p{N}])$escaped(?![\\p{L}\\p{N}])")
                        .findAll(lower)
                        .map { Triple(candidate.code, it.range.first, it.value.length) }
                        .toList()
                }
        }
        val namedChoiceCodes = namedMatches.groupBy { it.second }.values.flatMap { atSameStart ->
            val longest = atSameStart.maxOf { it.third }
            atSameStart.filter { it.third == longest }.map { it.first }
        }.distinct()
        if (namedChoiceCodes.isNotEmpty()) {
            if (namedChoiceCodes.size != 1 || namedChoiceCodes.single() != option.code) return false
        } else if (!isNamed(option.code)) {
            return false
        }
        val changeRequest = Regex("\\b(?:change|switch|set)\\b.{0,40}\\b(?:language|reply|to)\\b")
            .containsMatchIn(lower)
        val forwardSpeechRequest = Regex("^\\s*(?:from now on|going forward|for future replies)\\b.{0,50}\\b(?:speak|reply|answer|talk|use)\\b")
            .containsMatchIn(lower)
        return changeRequest || forwardSpeechRequest
    }

    fun promptInstruction(saved: String?): String {
        val language = option(saved)
        if (language.code == AUTO_CODE) return ""
        return if (language.code == "hi-Latn") {
            "\nLANGUAGE: Reply naturally in Hinglish (Hindi written in Latin script, with common English words). Keep names, app labels, code, URLs, and technical identifiers unchanged. If the user explicitly asks to switch languages, follow that request for the conversation.\n"
        } else {
            "\nLANGUAGE: Reply in ${language.englishName} (${language.nativeName}) by default, using its usual script and natural conversational phrasing. If the user explicitly asks to switch languages, follow that request for the conversation. Keep names, app labels, code, URLs, and technical identifiers unchanged.\n"
        }
    }
}
