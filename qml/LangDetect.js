// LangDetect.js — Detección ligera de idioma por bloque de texto
// Combina análisis de script Unicode (cirílico, CJK, kana, griego) y
// distribución de frecuencia de palabras funcionales (stopwords).

var SCRIPT_REGEX = {
    cjk: /[\u4E00-\u9FFF]/,
    kana: /[\u3040-\u309F\u30A0-\u30FF]/,
    cyrillic: /[\u0400-\u04FF]/,
    greek: /[\u0370-\u03FF]/
};

var STOPWORDS = {
    es: [
        "de", "la", "que", "el", "en", "y", "a", "los", "del", "se", "las", "por", "un", "para", "con", "no", "una",
        "su", "al", "lo", "como", "más", "pero", "sus", "le", "ya", "o", "este", "sí", "porque", "esta", "son",
        "entre", "está", "cuando", "muy", "sin", "sobre", "también", "me", "hasta", "hay", "donde", "quien", "desde",
        "todo", "nos", "durante", "todos", "uno", "les", "ni", "contra", "otros", "ese", "eso", "ante", "ellos",
        "esto", "mí", "antes", "algunos", "qué", "unos", "yo", "otro", "otras", "otra", "él", "tanto", "esa", "estos",
        "mucho", "quienes", "nada", "muchos", "cual", "sea", "poco", "ella", "estar", "haber", "estas", "estaba", "estamos"
    ],
    en: [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with", "he", "as",
        "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she", "or", "an", "will",
        "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if", "about", "who", "get", "which",
        "go", "me", "when", "make", "can", "like", "time", "no", "just", "him", "know", "take", "people", "into", "year",
        "your", "good", "some", "could", "them", "see", "other", "than", "then", "now", "look", "only", "come", "its",
        "over", "think", "also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even"
    ],
    pt: [
        "de", "a", "o", "que", "e", "do", "da", "em", "um", "para", "é", "com", "não", "uma", "os", "no", "se", "na",
        "por", "mais", "as", "dos", "como", "mas", "foi", "ao", "ele", "das", "tem", "à", "seu", "sua", "ou", "ser",
        "quando", "muito", "há", "nos", "já", "está", "eu", "também", "só", "pelo", "pela", "até", "isso", "ela",
        "entre", "era", "depois", "sem", "mesmo", "aos", "ter", "seus", "quem", "nas", "me", "esse", "eles", "estão",
        "você", "tinha", "foram", "essa", "num", "nem", "suas", "meu", "às", "minha", "têm", "numa", "pelos", "elas"
    ],
    fr: [
        "de", "la", "le", "et", "les", "des", "en", "un", "du", "une", "que", "est", "pour", "qui", "dans", "a", "par",
        "sur", "au", "pas", "plus", "ce", "ne", "sont", "avec", "se", "il", "ont", "son", "mais", "ou", "aux", "cette",
        "nous", "comme", "on", "tout", "ils", "sa", "leur", "ses", "faire", "même", "aussi", "été", "après", "elle",
        "bien", "encore", "peut", "ces", "sans", "tous", "sous", "très", "leurs", "autres", "donc", "temps", "dont", "notre"
    ],
    de: [
        "der", "die", "und", "in", "den", "von", "zu", "das", "mit", "sich", "des", "auf", "für", "ist", "im", "dem",
        "nicht", "ein", "eine", "als", "auch", "es", "an", "werden", "aus", "er", "hat", "dass", "sie", "nach", "wird",
        "bei", "einer", "um", "am", "sind", "noch", "wie", "einem", "über", "einen", "so", "zum", "war", "haben", "nur",
        "oder", "aber", "vor", "zur", "bis", "mehr", "durch", "man", "sein", "wurde", "sei", "hatte", "kann", "gegen"
    ],
    it: [
        "di", "e", "il", "che", "la", "a", "in", "per", "un", "del", "non", "i", "con", "si", "le", "da", "al", "della",
        "dei", "su", "delle", "una", "è", "ha", "sono", "dalla", "più", "lo", "ma", "degli", "questo", "ed", "anche",
        "nel", "dal", "ai", "se", "alle", "agli", "ci", "gli", "nei", "tra", "dallo", "nelle", "come", "loro", "fatto", "suo"
    ],
    ca: [
        "de", "la", "i", "el", "a", "que", "en", "per", "els", "del", "un", "les", "va", "amb", "al", "una", "dels",
        "com", "ha", "és", "però", "van", "se", "no", "aquesta", "més", "entre", "aquest", "sobre", "era", "també",
        "fins", "durant", "ser", "havia", "són", "on", "quan", "seva", "dos", "ja", "després", "tot", "pel", "anys"
    ]
};

var _stopwordSets = null;

function _getStopwordSets() {
    if (_stopwordSets) return _stopwordSets;
    _stopwordSets = {};
    for (var lang in STOPWORDS) {
        var set = {};
        var arr = STOPWORDS[lang];
        for (var i = 0; i < arr.length; i++) {
            set[arr[i]] = true;
        }
        _stopwordSets[lang] = set;
    }
    return _stopwordSets;
}

/**
 * Detecta el idioma principal de un texto o párrafo.
 * @param {string} text
 * @returns {string|null} Código ISO de idioma ("es", "en", "pt", "fr", "de", "it", "ca", "ru", "zh", "ja", "el") o null si es desconocido/ambiguo.
 */
function detect(text) {
    if (!text || typeof text !== "string") return null;
    var raw = text.trim();
    if (raw.length < 8) return null;

    if (typeof Sys !== "undefined" && typeof Sys.detectLanguage === "function") {
        var nativeLang = Sys.detectLanguage(raw);
        if (nativeLang && nativeLang !== "") {
            return nativeLang;
        }
    }

    // 1. Detección por script no latino
    if (SCRIPT_REGEX.kana.test(raw)) return "ja";
    if (SCRIPT_REGEX.cjk.test(raw)) return "zh";
    if (SCRIPT_REGEX.cyrillic.test(raw)) return "ru";
    if (SCRIPT_REGEX.greek.test(raw)) return "el";

    // 2. Tokenización para alfabeto latino
    var words = raw.toLowerCase().match(/[a-zA-Z\u00C0-\u024F]+/g);
    if (!words || words.length < 3) return null;

    var sets = _getStopwordSets();
    var maxScore = 0;
    var bestLang = null;
    var secondScore = 0;

    for (var lang in sets) {
        var set = sets[lang];
        var count = 0;
        for (var i = 0; i < words.length; i++) {
            if (set[words[i]]) count++;
        }
        if (count > maxScore) {
            secondScore = maxScore;
            maxScore = count;
            bestLang = lang;
        } else if (count > secondScore) {
            secondScore = count;
        }
    }

    // Umbral de confianza
    var minConfidence = Math.max(2, Math.floor(words.length * 0.10));
    if (maxScore >= 2 && maxScore >= minConfidence) {
        if (maxScore > secondScore) {
            return bestLang;
        }
    }

    return null;
}
