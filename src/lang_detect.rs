// src/lang_detect.rs — Detección nativa de idioma en Rust
// Combina análisis de script Unicode y distribución de frecuencias de palabras funcionales.

use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;

static STOPWORDS_ES: &[&str] = &[
    "de", "la", "que", "el", "en", "y", "a", "los", "del", "se", "las", "por", "un", "para", "con", "no", "una",
    "su", "al", "lo", "como", "más", "pero", "sus", "le", "ya", "o", "este", "sí", "porque", "esta", "son",
    "entre", "está", "cuando", "muy", "sin", "sobre", "también", "me", "hasta", "hay", "donde", "quien", "desde",
    "todo", "nos", "durante", "todos", "uno", "les", "ni", "contra", "otros", "ese", "eso", "ante", "ellos",
    "esto", "mí", "antes", "algunos", "qué", "unos", "yo", "otro", "otras", "otra", "él", "tanto", "esa", "estos",
    "mucho", "quienes", "nada", "muchos", "cual", "sea", "poco", "ella", "estar", "haber", "estas", "estaba", "estamos",
];

static STOPWORDS_EN: &[&str] = &[
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with", "he", "as",
    "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she", "or", "an", "will",
    "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if", "about", "who", "get", "which",
    "go", "me", "when", "make", "can", "like", "time", "no", "just", "him", "know", "take", "people", "into", "year",
    "your", "good", "some", "could", "them", "see", "other", "than", "then", "now", "look", "only", "come", "its",
    "over", "think", "also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
];

static STOPWORDS_PT: &[&str] = &[
    "de", "a", "o", "que", "e", "do", "da", "em", "um", "para", "é", "com", "não", "uma", "os", "no", "se", "na",
    "por", "mais", "as", "dos", "como", "mas", "foi", "ao", "ele", "das", "tem", "à", "seu", "sua", "ou", "ser",
    "quando", "muito", "há", "nos", "já", "está", "eu", "também", "só", "pelo", "pela", "até", "isso", "ela",
    "entre", "era", "depois", "sem", "mesmo", "aos", "ter", "seus", "quem", "nas", "me", "esse", "eles", "estão",
    "você", "tinha", "foram", "essa", "num", "nem", "suas", "meu", "às", "minha", "têm", "numa", "pelos", "elas",
];

static STOPWORDS_FR: &[&str] = &[
    "de", "la", "le", "et", "les", "des", "en", "un", "du", "une", "que", "est", "pour", "qui", "dans", "a", "par",
    "sur", "au", "pas", "plus", "ce", "ne", "sont", "avec", "se", "il", "ont", "son", "mais", "ou", "aux", "cette",
    "nous", "comme", "on", "tout", "ils", "sa", "leur", "ses", "faire", "même", "aussi", "été", "après", "elle",
    "bien", "encore", "peut", "ces", "sans", "tous", "sous", "très", "leurs", "autres", "donc", "temps", "dont", "notre",
];

static STOPWORDS_DE: &[&str] = &[
    "der", "die", "und", "in", "den", "von", "zu", "das", "mit", "sich", "des", "auf", "für", "ist", "im", "dem",
    "nicht", "ein", "eine", "als", "auch", "es", "an", "werden", "aus", "er", "hat", "dass", "sie", "nach", "wird",
    "bei", "einer", "um", "am", "sind", "noch", "wie", "einem", "über", "einen", "so", "zum", "war", "haben", "nur",
    "oder", "aber", "vor", "zur", "bis", "mehr", "durch", "man", "sein", "wurde", "sei", "hatte", "kann", "gegen",
];

static STOPWORDS_IT: &[&str] = &[
    "di", "e", "il", "che", "la", "a", "in", "per", "un", "del", "non", "i", "con", "si", "le", "da", "al", "della",
    "dei", "su", "delle", "una", "è", "ha", "sono", "dalla", "più", "lo", "ma", "degli", "questo", "ed", "anche",
    "nel", "dal", "ai", "se", "alle", "agli", "ci", "gli", "nei", "tra", "dallo", "nelle", "come", "loro", "fatto", "suo",
];

static STOPWORDS_CA: &[&str] = &[
    "de", "la", "i", "el", "a", "que", "en", "per", "els", "del", "un", "les", "va", "amb", "al", "una", "dels",
    "com", "ha", "és", "però", "van", "se", "no", "aquesta", "més", "entre", "aquest", "sobre", "era", "també",
    "fins", "durant", "ser", "havia", "són", "on", "quan", "seva", "dos", "ja", "després", "tot", "pel", "anys",
];

struct LanguageSets {
    es: HashSet<&'static str>,
    en: HashSet<&'static str>,
    pt: HashSet<&'static str>,
    fr: HashSet<&'static str>,
    de: HashSet<&'static str>,
    it: HashSet<&'static str>,
    ca: HashSet<&'static str>,
}

static LANG_SETS: OnceLock<LanguageSets> = OnceLock::new();

fn get_lang_sets() -> &'static LanguageSets {
    LANG_SETS.get_or_init(|| LanguageSets {
        es: STOPWORDS_ES.iter().copied().collect(),
        en: STOPWORDS_EN.iter().copied().collect(),
        pt: STOPWORDS_PT.iter().copied().collect(),
        fr: STOPWORDS_FR.iter().copied().collect(),
        de: STOPWORDS_DE.iter().copied().collect(),
        it: STOPWORDS_IT.iter().copied().collect(),
        ca: STOPWORDS_CA.iter().copied().collect(),
    })
}

pub fn detect_language(text: &str) -> Option<&'static str> {
    let raw = text.trim();
    if raw.len() < 8 {
        return None;
    }

    // 1. Detección por scripts no latinos
    for c in raw.chars() {
        match c {
            '\u{3040}'..='\u{309F}' | '\u{30A0}'..='\u{30FF}' => return Some("ja"),
            '\u{4E00}'..='\u{9FFF}' => return Some("zh"),
            '\u{0400}'..='\u{04FF}' => return Some("ru"),
            '\u{0370}'..='\u{03FF}' => return Some("el"),
            _ => {}
        }
    }

    // 2. Tokenización de palabras latinas
    let mut words: Vec<String> = Vec::new();
    let mut current = String::new();
    for c in raw.chars() {
        if c.is_alphabetic() {
            current.extend(c.to_lowercase());
        } else if !current.is_empty() {
            words.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        words.push(current);
    }

    if words.len() < 3 {
        return None;
    }

    let sets = get_lang_sets();
    let langs: [(&'static str, &HashSet<&'static str>); 7] = [
        ("es", &sets.es),
        ("en", &sets.en),
        ("pt", &sets.pt),
        ("fr", &sets.fr),
        ("de", &sets.de),
        ("it", &sets.it),
        ("ca", &sets.ca),
    ];

    let mut max_score = 0;
    let mut second_score = 0;
    let mut best_lang: Option<&'static str> = None;

    for (lang_code, set) in langs {
        let count = words.iter().filter(|w| set.contains(w.as_str())).count();
        if count > max_score {
            second_score = max_score;
            max_score = count;
            best_lang = Some(lang_code);
        } else if count > second_score {
            second_score = count;
        }
    }

    let min_confidence = (words.len() * 10 / 100).max(2);
    if max_score >= 2 && max_score >= min_confidence && max_score > second_score {
        return best_lang;
    }

    None
}

#[no_mangle]
pub extern "C" fn notas_detect_language(text_ptr: *const c_char) -> *mut c_char {
    if text_ptr.is_null() {
        return std::ptr::null_mut();
    }
    let text = unsafe { CStr::from_ptr(text_ptr) }.to_string_lossy();

    match detect_language(&text) {
        Some(lang) => match CString::new(lang) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}
