# -*- coding: utf-8 -*-
"""Duniya ki languages — user chune, MYRA usi mein sunegi aur bolegi."""
import re

# (code, English naam, native naam)
LANGUAGES = [
    ("hi", "Hindi", "हिन्दी"), ("en-IN", "English (India)", "English (India)"), ("bn", "Bengali", "বাংলা"),
    ("te", "Telugu", "తెలుగు"), ("mr", "Marathi", "मराठी"), ("ta", "Tamil", "தமிழ்"), ("gu", "Gujarati", "ગુજરાતી"),
    ("kn", "Kannada", "ಕನ್ನಡ"), ("ml", "Malayalam", "മലയാളം"), ("pa", "Punjabi", "ਪੰਜਾਬੀ"), ("or", "Odia", "ଓଡ଼ିଆ"),
    ("as", "Assamese", "অসমীয়া"), ("ur", "Urdu", "اردو"), ("ne", "Nepali", "नेपाली"), ("sa", "Sanskrit", "संस्कृतम्"),
    ("sd", "Sindhi", "سنڌي"), ("ks", "Kashmiri", "کٲشُر"), ("kok", "Konkani", "कोंकणी"), ("mai", "Maithili", "मैथिली"),
    ("doi", "Dogri", "डोगरी"), ("mni", "Manipuri (Meitei)", "ꯃꯤꯇꯩꯂꯣꯟ"), ("brx", "Bodo", "बड़ो"), ("sat", "Santali", "ᱥᱟᱱᱛᱟᱲᱤ"),
    ("bho", "Bhojpuri", "भोजपुरी"), ("raj", "Rajasthani", "राजस्थानी"), ("hne", "Chhattisgarhi", "छत्तीसगढ़ी"),
    ("mag", "Magahi", "मगही"), ("awa", "Awadhi", "अवधी"), ("tcy", "Tulu", "ತುಳು"),
    ("en-US", "English (US)", "English (US)"), ("en-GB", "English (UK)", "English (UK)"), ("en-AU", "English (Australia)", "English (Australia)"),
    ("es", "Spanish", "Español"), ("es-MX", "Spanish (Mexico)", "Español (México)"), ("fr", "French", "Français"),
    ("fr-CA", "French (Canada)", "Français (Canada)"), ("de", "German", "Deutsch"), ("it", "Italian", "Italiano"),
    ("pt-BR", "Portuguese (Brazil)", "Português (Brasil)"), ("pt-PT", "Portuguese (Portugal)", "Português (Portugal)"),
    ("nl", "Dutch", "Nederlands"), ("sv", "Swedish", "Svenska"), ("da", "Danish", "Dansk"), ("no", "Norwegian", "Norsk"),
    ("fi", "Finnish", "Suomi"), ("is", "Icelandic", "Íslenska"), ("ru", "Russian", "Русский"), ("uk", "Ukrainian", "Українська"),
    ("pl", "Polish", "Polski"), ("cs", "Czech", "Čeština"), ("sk", "Slovak", "Slovenčina"), ("hu", "Hungarian", "Magyar"),
    ("ro", "Romanian", "Română"), ("bg", "Bulgarian", "Български"), ("el", "Greek", "Ελληνικά"), ("sr", "Serbian", "Српски"),
    ("hr", "Croatian", "Hrvatski"), ("bs", "Bosnian", "Bosanski"), ("sl", "Slovenian", "Slovenščina"), ("mk", "Macedonian", "Македонски"),
    ("sq", "Albanian", "Shqip"), ("lt", "Lithuanian", "Lietuvių"), ("lv", "Latvian", "Latviešu"), ("et", "Estonian", "Eesti"),
    ("be", "Belarusian", "Беларуская"), ("ca", "Catalan", "Català"), ("eu", "Basque", "Euskara"), ("gl", "Galician", "Galego"),
    ("ga", "Irish", "Gaeilge"), ("cy", "Welsh", "Cymraeg"), ("gd", "Scottish Gaelic", "Gàidhlig"), ("mt", "Maltese", "Malti"),
    ("lb", "Luxembourgish", "Lëtzebuergesch"), ("br", "Breton", "Brezhoneg"), ("la", "Latin", "Latina"), ("eo", "Esperanto", "Esperanto"),
    ("zh-CN", "Chinese (Mandarin, Simplified)", "简体中文"), ("zh-TW", "Chinese (Traditional)", "繁體中文"), ("yue", "Cantonese", "粵語"),
    ("ja", "Japanese", "日本語"), ("ko", "Korean", "한국어"), ("vi", "Vietnamese", "Tiếng Việt"), ("th", "Thai", "ไทย"),
    ("id", "Indonesian", "Bahasa Indonesia"), ("ms", "Malay", "Bahasa Melayu"), ("fil", "Filipino (Tagalog)", "Filipino"),
    ("my", "Burmese", "မြန်မာ"), ("km", "Khmer", "ខ្មែរ"), ("lo", "Lao", "ລາວ"), ("si", "Sinhala", "සිංහල"),
    ("mn", "Mongolian", "Монгол"), ("bo", "Tibetan", "བོད་སྐད།"), ("ug", "Uyghur", "ئۇيغۇرچە"), ("jv", "Javanese", "Basa Jawa"),
    ("su", "Sundanese", "Basa Sunda"), ("ceb", "Cebuano", "Cebuano"), ("ilo", "Ilocano", "Ilokano"), ("hmn", "Hmong", "Hmoob"),
    ("ar", "Arabic", "العربية"), ("ar-EG", "Arabic (Egypt)", "العربية (مصر)"), ("he", "Hebrew", "עברית"), ("fa", "Persian (Farsi)", "فارسی"),
    ("tr", "Turkish", "Türkçe"), ("ku", "Kurdish", "Kurdî"), ("ps", "Pashto", "پښتو"), ("prs", "Dari", "دری"), ("az", "Azerbaijani", "Azərbaycanca"),
    ("hy", "Armenian", "Հայերեն"), ("ka", "Georgian", "ქართული"), ("kk", "Kazakh", "Қазақша"), ("uz", "Uzbek", "Oʻzbekcha"),
    ("ky", "Kyrgyz", "Кыргызча"), ("tg", "Tajik", "Тоҷикӣ"), ("tk", "Turkmen", "Türkmençe"), ("tt", "Tatar", "Татарча"),
    ("sw", "Swahili", "Kiswahili"), ("am", "Amharic", "አማርኛ"), ("ha", "Hausa", "Hausa"), ("yo", "Yoruba", "Yorùbá"), ("ig", "Igbo", "Igbo"),
    ("zu", "Zulu", "isiZulu"), ("xh", "Xhosa", "isiXhosa"), ("af", "Afrikaans", "Afrikaans"), ("st", "Sesotho", "Sesotho"),
    ("tn", "Tswana", "Setswana"), ("sn", "Shona", "chiShona"), ("so", "Somali", "Soomaali"), ("rw", "Kinyarwanda", "Ikinyarwanda"),
    ("mg", "Malagasy", "Malagasy"), ("ny", "Chichewa", "Chichewa"), ("wo", "Wolof", "Wolof"), ("ti", "Tigrinya", "ትግርኛ"),
    ("om", "Oromo", "Afaan Oromoo"), ("lg", "Luganda", "Luganda"), ("ln", "Lingala", "Lingála"), ("ff", "Fula", "Fulfulde"),
    ("ber", "Berber (Tamazight)", "ⵜⴰⵎⴰⵣⵉⵖⵜ"),
    ("ht", "Haitian Creole", "Kreyòl ayisyen"), ("qu", "Quechua", "Runasimi"), ("gn", "Guarani", "Avañeʼẽ"), ("ay", "Aymara", "Aymar aru"),
    ("haw", "Hawaiian", "ʻŌlelo Hawaiʻi"), ("mi", "Maori", "Te Reo Māori"), ("sm", "Samoan", "Gagana Samoa"), ("to", "Tongan", "Lea faka-Tonga"),
    ("fj", "Fijian", "Vosa Vakaviti"), ("yi", "Yiddish", "ייִדיש"),
    ("hi-Latn", "Hinglish (Hindi + English)", "Hinglish"),
]

_ALIASES = {"hinglish": "hi-Latn", "english": "en-US", "chinese": "zh-CN", "mandarin": "zh-CN", "portuguese": "pt-BR",
            "farsi": "fa", "tagalog": "fil"}
_norm = lambda s: re.sub(r"[^\w]+", "", str(s or "").lower())
_BY_KEY = {}
for _it in LANGUAGES:
    for _k in _it:
        _BY_KEY.setdefault(_norm(_k), _it)
_BY_CODE = {it[0]: it for it in LANGUAGES}
for _a, _c in _ALIASES.items():
    _BY_KEY[_a] = _BY_CODE[_c]


def find(text):
    k = _norm(text)
    if not k or k in ("auto", "default"):
        return None
    if k in _BY_KEY:
        return _BY_KEY[k]
    for key, v in _BY_KEY.items():
        if len(key) > 4 and key in k:
            return v
    return None


def prompt_block(code):
    it = _BY_CODE.get(code)
    if not it or code == "hi-Latn":
        return ""
    _, e, n = it
    return (f"\nLANGUAGE (sabse zaroori): user ne **{e} ({n})** chuni hai. Ab se SIRF {e} mein bolo aur likho — har jawab, "
            f"confirmation aur error. Natural, bol-chaal wali {e} use karo ({n} script mein). User doosri language mein bole "
            f"to bhi jawab {e} mein do, jab tak wo khud na kahe ('ab English mein bolo') — tab set_language tool se badlo. "
            f"App/website ke naam aur code translate mat karo.\n")
