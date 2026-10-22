# Offline model language qualification

Status: not passed. This is a candidate evaluation plan, not evidence that any model supports these languages. Offline AI must stay unavailable until one specifically licensed model artifact passes the language/tutoring checks and the Android runtime/device gates below. Do not download or bundle a candidate as part of this qualification document.

## Candidate record

For each candidate, record the exact model name, version, artifact hash, quantization, license/terms, inference runtime/version, device/build, available storage before installation, and the complete prompt/output for each case. Do not treat a Linux or hosted result as Android evidence. Score each case independently; a good average cannot hide a language or safety failure.

## Language and tutoring fixtures

Run every fixture against the exact candidate with its intended offline settings. Repeat each case at least three times. A fluent reviewer should check Assamese, Hindi and Hinglish wording/naturalness; retain the unedited output and any failure. All answers must be factually correct, show the calculation and unit, stay concise, and follow the requested language and script. The expected result for the calculation is 6 N.

1. English (`en-IN`): “For a Class 12/JEE learner, explain Newton’s second law in two or three short sentences. A 2 kg cart accelerates at 3 m/s². Use F = m × a, show the calculation and unit, and answer in English.”
2. Assamese (`as-IN`): “দ্বাদশ শ্ৰেণীৰ/JEE শিক্ষাৰ্থীৰ বাবে নিউটনৰ দ্বিতীয় নিয়মটো দুই-তিনিটা চুটি বাক্যত বুজাই দিয়া। 2 kg ভৰৰ এখন গাড়ীৰ ত্বৰণ 3 m/s²। F = m × a ব্যৱহাৰ কৰি গণনা আৰু একক দেখুওৱা, আৰু অসমীয়াত উত্তৰ দিয়া।”
3. Hindi (`hi-IN`): “कक्षा 12/JEE के विद्यार्थी के लिए न्यूटन का दूसरा नियम दो या तीन छोटे वाक्यों में समझाइए। 2 kg की गाड़ी का त्वरण 3 m/s² है। F = m × a लगाकर गणना और इकाई दिखाइए और देवनागरी हिन्दी में उत्तर दीजिए।”
4. Hinglish (`hi-Latn-IN`): “Class 12/JEE student ko Newton’s second law 2–3 short sentences mein natural Hinglish mein samjhao. 2 kg ki cart 3 m/s² se accelerate karti hai. F = m × a lagao, calculation aur unit dikhao, aur Roman script mein jawab do.”

For each language, also ask the tutor to check a learner’s wrong claim (“the force is 20 N”) rather than agree: it must gently correct the result to 6 N with the same language/script. Check that no response invents a tool action, source, or unsupported confidence. The Assamese fixture and all other non-English output need fluent review before any pass is recorded. Qualification requires every repeated run of every fixture to be correct, concise, in the requested language and script, and factually grounded; one failed run or one language failure disqualifies that candidate (no averaging across languages).

## Voice checks are a separate gate

- On-device recognition: verify the exact installed locale reported by Android for `en-IN`, `as-IN`, `hi-IN` and `hi-Latn-IN`; use representative spoken prompts, compare transcripts with the spoken words, and repeat in realistic background noise. For Hinglish, include Hindi-English code switching in Latin script. A locale in the app’s allowlist or an Android recognizer’s generic availability flag is not proof that its offline language pack exists or performs well.
- Offline speech output: verify an installed non-network voice for the exact locale, script and pronunciation. Check Hindi in Devanagari and Hinglish code-switch pronunciation separately. If the exact voice is absent or poor, keep the reply readable as text; never substitute another language or use a network voice silently.
- Do not infer language auto-detection, interruption, or noise robustness from a single dictated sentence. Record each result per locale and per actual device.

## Device and safety gate

A candidate must also have an allowed license, a supported Android 16 inference runtime, measured memory/latency/heat behavior, cancellation and restart checks, actual free-space preflight, and testing on both API 36 and the owner’s physical target phone. Preserve strict no-network fallback throughout installation, generation, errors and cancellation. Only after all model-quality, licensing, runtime and device gates pass may Offline AI be considered for enabling. No such qualification has been completed by adding these fixtures.
