// src/spell_engine.rs — Motor ortográfico integrado basado en Spellbook y diccionarios embebidos
use std::collections::HashSet;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};

/// Diccionarios base embebidos en el binario (cero dependencias externas en tiempo de ejecución)
pub const EMBEDDED_DICTS: &[(&str, &str, &str)] = &[
    (
        "es_AR",
        include_str!("../assets/spellcheck/dicts/es_AR.aff"),
        include_str!("../assets/spellcheck/dicts/es_AR.dic"),
    ),
    (
        "es_ES",
        include_str!("../assets/spellcheck/dicts/es_ES.aff"),
        include_str!("../assets/spellcheck/dicts/es_ES.dic"),
    ),
    (
        "en_US",
        include_str!("../assets/spellcheck/dicts/en_US.aff"),
        include_str!("../assets/spellcheck/dicts/en_US.dic"),
    ),
];

pub fn embedded_languages() -> Vec<&'static str> {
    EMBEDDED_DICTS.iter().map(|(code, _, _)| *code).collect()
}

pub fn is_embedded(code: &str) -> bool {
    EMBEDDED_DICTS.iter().any(|(c, _, _)| {
        c.eq_ignore_ascii_case(code)
            || code.replace('-', "_").eq_ignore_ascii_case(c)
            || (code.eq_ignore_ascii_case("es") && *c == "es_ES")
            || (code.eq_ignore_ascii_case("en") && *c == "en_US")
    })
}

pub fn load_dictionary(code_or_path: &str) -> Result<spellbook::Dictionary, String> {
    let clean = code_or_path.trim();
    if clean.is_empty() {
        return Err("Código de idioma o ruta vacía".to_string());
    }

    // 1. Ruta directa al archivo (o base sin extensión)
    let p = Path::new(clean);
    if p.is_file() || clean.contains('/') || clean.ends_with(".dic") || clean.ends_with(".aff") {
        let base = if clean.ends_with(".dic") || clean.ends_with(".aff") {
            &clean[..clean.len() - 4]
        } else {
            clean
        };
        let aff_p = format!("{}.aff", base);
        let dic_p = format!("{}.dic", base);
        let aff = fs::read_to_string(&aff_p).map_err(|e| format!("No se pudo leer {}: {}", aff_p, e))?;
        let dic = fs::read_to_string(&dic_p).map_err(|e| format!("No se pudo leer {}: {}", dic_p, e))?;
        return spellbook::Dictionary::new(&aff, &dic).map_err(|e| format!("Error en diccionario {}: {:?}", base, e));
    }

    // 2. Directorio de usuario ($XDG_DATA_HOME/criperto-notes/dictionaries o ~/.local/share/criperto-notes/dictionaries)
    let mut user_dirs: Vec<PathBuf> = Vec::new();
    if let Ok(xdg_data) = std::env::var("XDG_DATA_HOME") {
        if !xdg_data.trim().is_empty() {
            user_dirs.push(PathBuf::from(xdg_data).join("criperto-notes/dictionaries"));
        }
    }
    let home = std::env::var("HOME").unwrap_or_default();
    if !home.is_empty() {
        user_dirs.push(PathBuf::from(&home).join(".local/share/criperto-notes/dictionaries"));
    }
    for dir in user_dirs {
        let user_aff = dir.join(format!("{}.aff", clean));
        let user_dic = dir.join(format!("{}.dic", clean));
        if user_aff.is_file() && user_dic.is_file() {
            let aff = fs::read_to_string(&user_aff).map_err(|e| format!("Error leyendo {}: {}", user_aff.display(), e))?;
            let dic = fs::read_to_string(&user_dic).map_err(|e| format!("Error leyendo {}: {}", user_dic.display(), e))?;
            return spellbook::Dictionary::new(&aff, &dic).map_err(|e| format!("Error parseando {}: {:?}", clean, e));
        }
    }

    // 3. Directorio del sistema (/app/share o /usr/share)
    for sys_dir in [
        PathBuf::from("/app/share/criperto-notes/dictionaries"),
        PathBuf::from("/usr/share/criperto-notes/dictionaries"),
    ] {
        let sys_aff = sys_dir.join(format!("{}.aff", clean));
        let sys_dic = sys_dir.join(format!("{}.dic", clean));
        if sys_aff.is_file() && sys_dic.is_file() {
            let aff = fs::read_to_string(&sys_aff).map_err(|e| format!("Error leyendo {}: {}", sys_aff.display(), e))?;
            let dic = fs::read_to_string(&sys_dic).map_err(|e| format!("Error leyendo {}: {}", sys_dic.display(), e))?;
            return spellbook::Dictionary::new(&aff, &dic).map_err(|e| format!("Error parseando {}: {:?}", clean, e));
        }
    }

    // 4. Diccionarios embebidos de alta velocidad
    for &(code, aff, dic) in EMBEDDED_DICTS {
        if code.eq_ignore_ascii_case(clean)
            || clean.replace('-', "_").eq_ignore_ascii_case(code)
            || (clean.eq_ignore_ascii_case("es") && code == "es_ES")
            || (clean.eq_ignore_ascii_case("en") && code == "en_US")
        {
            return spellbook::Dictionary::new(aff, dic).map_err(|e| format!("Error cargando diccionario embebido {}: {:?}", code, e));
        }
    }

    Err(format!("Diccionario no encontrado para código o ruta '{}'", clean))
}

pub fn load_personal_words(path: &Path) -> HashSet<String> {
    let mut words = HashSet::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            let w = line.trim();
            if !w.is_empty() {
                words.insert(w.to_lowercase());
            }
        }
    }
    words
}

/// Ejecuta el proceso de corrección interactivo por tubería (emulando el protocolo Ispell/Hunspell -a)
pub fn run_pipe_cli(args: &[String]) {
    let mut dict_code = "es_AR".to_string();
    let mut personal_dic: Option<PathBuf> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-d" => {
                if i + 1 < args.len() {
                    dict_code = args[i + 1].clone();
                    i += 1;
                }
            }
            "-p" => {
                if i + 1 < args.len() {
                    personal_dic = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                }
            }
            "-a" => {
                // Compatible con invocaciones de estilo hunspell -a
            }
            other if !other.starts_with('-') && dict_code.is_empty() => {
                dict_code = other.to_string();
            }
            _ => {}
        }
        i += 1;
    }

    let dict = match load_dictionary(&dict_code) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[SpellPipe] {}", e);
            std::process::exit(1);
        }
    };

    let personal_words = personal_dic
        .as_ref()
        .map(|p| load_personal_words(p))
        .unwrap_or_default();

    let stdout = io::stdout();
    let mut out = stdout.lock();

    // Banner de identificación del protocolo
    let _ = writeln!(out, "@(#) International Ispell Version 3.2.06 (but really Spellbook)");
    let _ = out.flush();

    let stdin = io::stdin();
    for line_res in stdin.lock().lines() {
        let line = match line_res {
            Ok(l) => l,
            Err(_) => break,
        };

        let raw = line.trim();
        if raw.is_empty() {
            let _ = writeln!(out);
            let _ = out.flush();
            continue;
        }

        let word = if raw.starts_with('^') {
            &raw[1..]
        } else {
            raw
        };

        if word.is_empty() {
            let _ = writeln!(out);
            let _ = out.flush();
            continue;
        }

        // Chequeo en palabras personales del usuario
        if personal_words.contains(&word.to_lowercase()) {
            let _ = writeln!(out, "*\n");
            let _ = out.flush();
            continue;
        }

        // Chequeo con Spellbook
        if dict.check(word) {
            let _ = writeln!(out, "*\n");
            let _ = out.flush();
        } else {
            let mut sugs = Vec::new();
            dict.suggest(word, &mut sugs);
            sugs.truncate(5);
            if !sugs.is_empty() {
                let _ = writeln!(out, "& {} {} 0: {}\n", word, sugs.len(), sugs.join(", "));
            } else {
                let _ = writeln!(out, "# {} 0\n", word);
            }
            let _ = out.flush();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_embedded_dictionaries() {
        let es_ar = load_dictionary("es_AR").expect("Cargar es_AR embebido");
        assert!(es_ar.check("casa"));
        assert!(es_ar.check("árbol"));
        assert!(!es_ar.check("arbol"));
        assert!(!es_ar.check("holaa"));

        let mut sugs = Vec::new();
        es_ar.suggest("holaa", &mut sugs);
        assert!(!sugs.is_empty());
        assert!(sugs.contains(&"hola".to_string()));

        let en_us = load_dictionary("en_US").expect("Cargar en_US embebido");
        assert!(en_us.check("world"));
        assert!(!en_us.check("wrold"));
    }
}
