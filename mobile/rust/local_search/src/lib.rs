use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use serde::Serialize;
use serde_json::{json, Map, Value};
use std::panic::{catch_unwind, AssertUnwindSafe};
use unicode_normalization::UnicodeNormalization;
use unicode_segmentation::UnicodeSegmentation;

const MAX_REQUEST_BYTES: usize = 8_000_000;
const MAX_QUERY_BYTES: usize = 512;
const MAX_RESULTS: usize = 100;
const MAX_TITLE_CHARS: usize = 280;

#[derive(Debug, Serialize, PartialEq, Eq)]
struct ChatHit {
    conversation: String,
    title: String,
    matches: usize,
    score: u64,
}

fn normalize(text: &str) -> String {
    text.nfkc().flat_map(char::to_lowercase).collect()
}

fn words(text: &str) -> Vec<String> {
    let normalized = normalize(text);
    normalized.unicode_words().map(str::to_owned).collect()
}

fn message_score(query: &str, query_words: &[String], text: &str) -> Option<u64> {
    let normalized_text = normalize(text);
    let document_words = words(text);
    if query_words.is_empty() {
        return normalized_text.contains(query).then_some(1);
    }

    let mut score = 0_u64;
    for query_word in query_words {
        let best = document_words
            .iter()
            .filter(|word| word.contains(query_word.as_str()))
            .map(|word| if word == query_word { 100 } else { 55 })
            .max()?;
        score += best;
    }
    if !query.is_empty() && normalized_text.contains(query) {
        score += 500;
    }
    Some(score)
}

fn truncate_chars(value: &str, limit: usize) -> String {
    let mut chars = value.chars();
    let prefix: String = chars.by_ref().take(limit).collect();
    if chars.next().is_some() {
        format!("{prefix}…")
    } else {
        prefix
    }
}

fn rank_chats(query: &str, conversations: &Map<String, Value>) -> Vec<ChatHit> {
    let normalized_query = normalize(query.trim());
    let query_words = words(&normalized_query);
    let mut hits = Vec::new();

    for (conversation, messages) in conversations {
        let Some(messages) = messages.as_array() else {
            continue;
        };
        let mut best: Option<(u64, String)> = None;
        let mut matches = 0;
        for message in messages {
            let Some(text) = message.get("text").and_then(Value::as_str) else {
                continue;
            };
            if normalized_query.is_empty() {
                if best.is_none() && !text.is_empty() {
                    best = Some((0, text.to_owned()));
                }
                if !text.is_empty() {
                    matches += 1;
                }
                continue;
            }
            if let Some(score) = message_score(&normalized_query, &query_words, text) {
                matches += 1;
                if best
                    .as_ref()
                    .is_none_or(|(old_score, _)| score > *old_score)
                {
                    best = Some((score, text.to_owned()));
                }
            }
        }
        if matches > 0 {
            let score = best.as_ref().map_or(0, |(score, _)| *score);
            let title = best.map_or_else(String::new, |(_, text)| {
                truncate_chars(&text, MAX_TITLE_CHARS)
            });
            hits.push(ChatHit {
                conversation: conversation.clone(),
                title,
                matches,
                score,
            });
        }
    }

    hits.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| right.matches.cmp(&left.matches))
            .then_with(|| left.conversation.cmp(&right.conversation))
    });
    hits.truncate(MAX_RESULTS);
    hits
}

fn response_for_json(input: &str) -> Result<String, &'static str> {
    if input.len() > MAX_REQUEST_BYTES {
        return Err("request_too_large");
    }
    let request: Value = serde_json::from_str(input).map_err(|_| "invalid_request")?;
    let query = request
        .get("query")
        .and_then(Value::as_str)
        .ok_or("invalid_request")?;
    if query.len() > MAX_QUERY_BYTES {
        return Err("query_too_large");
    }
    let conversations = request
        .get("conversations")
        .and_then(Value::as_object)
        .ok_or("invalid_request")?;
    let response = json!({
        "engine": "rust",
        "results": rank_chats(query, conversations),
    });
    serde_json::to_string(&response).map_err(|_| "serialization_failed")
}

fn error_response(code: &str) -> String {
    json!({"engine":"rust", "error":code, "results":[]}).to_string()
}

#[no_mangle]
pub extern "system" fn Java_dev_personalagent_personal_1assistant_RustLocalSearch_search(
    mut env: JNIEnv,
    _class: JClass,
    request_json: JString,
) -> jstring {
    let response = catch_unwind(AssertUnwindSafe(|| {
        let input: String = env
            .get_string(&request_json)
            .map_err(|_| "invalid_request")?
            .into();
        response_for_json(&input)
    }))
    .unwrap_or(Err("native_search_failed"))
    .unwrap_or_else(error_response);

    env.new_string(response)
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chat(text: &str) -> Value {
        json!([{"role":"user", "text":text}])
    }

    #[test]
    fn ranks_exact_phrase_above_separate_word_matches() {
        let conversations = serde_json::from_value::<Value>(json!({
            "scattered": chat("velocity appears here; practice appears in another phrase"),
            "phrase": chat("velocity practice is the exact topic"),
        }))
        .unwrap();
        let hits = rank_chats("velocity practice", conversations.as_object().unwrap());
        assert_eq!(hits.first().unwrap().conversation, "phrase");
        assert_eq!(hits.len(), 2);
    }

    #[test]
    fn matches_hindi_assamese_and_hinglish_without_network_or_model() {
        let conversations = serde_json::from_value::<Value>(json!({
            "hindi": chat("आज पढ़ाई का समय है"),
            "assamese": chat("অসমীয়া পাঠ ভাল লাগিল"),
            "hinglish": chat("kal study session hai"),
        }))
        .unwrap();
        let map = conversations.as_object().unwrap();
        assert_eq!(rank_chats("पढ़ाई", map)[0].conversation, "hindi");
        assert_eq!(rank_chats("অসমীয়া", map)[0].conversation, "assamese");
        assert_eq!(rank_chats("study", map)[0].conversation, "hinglish");
    }

    #[test]
    fn all_query_terms_must_appear_in_one_message() {
        let conversations = serde_json::from_value::<Value>(json!({
            "split": [{"text":"velocity"}, {"text":"practice"}],
            "together": [{"text":"practice with velocity"}],
        }))
        .unwrap();
        let hits = rank_chats("velocity practice", conversations.as_object().unwrap());
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].conversation, "together");
    }

    #[test]
    fn empty_query_preserves_conversation_browse_behavior() {
        let conversations = serde_json::from_value::<Value>(json!({
            "one": chat("first message"),
            "empty": [],
        }))
        .unwrap();
        let hits = rank_chats("", conversations.as_object().unwrap());
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].conversation, "one");
        assert_eq!(hits[0].matches, 1);
    }

    #[test]
    fn rejects_oversized_and_malformed_requests() {
        assert_eq!(response_for_json("{"), Err("invalid_request"));
        assert_eq!(
            response_for_json(&"x".repeat(MAX_REQUEST_BYTES + 1)),
            Err("request_too_large")
        );
        let long_query =
            json!({"query":"x".repeat(MAX_QUERY_BYTES + 1), "conversations":{}}).to_string();
        assert_eq!(response_for_json(&long_query), Err("query_too_large"));
    }

    #[test]
    fn caps_result_count() {
        let conversations = (0..MAX_RESULTS + 7)
            .map(|index| (format!("chat-{index:03}"), chat("shared topic")))
            .collect::<Map<_, _>>();
        let hits = rank_chats("shared topic", &conversations);
        assert_eq!(hits.len(), MAX_RESULTS);
        assert_eq!(hits[0].conversation, "chat-000");
    }

    #[test]
    fn output_is_bounded() {
        let long = "x".repeat(MAX_TITLE_CHARS + 30);
        let conversations = serde_json::from_value::<Value>(json!({"long":chat(&long)})).unwrap();
        let hit = rank_chats("", conversations.as_object().unwrap()).remove(0);
        assert!(hit.title.chars().count() <= MAX_TITLE_CHARS + 1);
    }
}
