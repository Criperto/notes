// cli_ops.rs — Operaciones headless por línea de comandos para Notas
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

#[derive(Serialize, Clone, Debug)]
pub struct SearchResult {
    pub slug: String,
    pub title: String,
    pub path: String,
    pub tags: Vec<String>,
    pub snippet: String,
    pub modified: String,
    #[serde(skip_serializing)]
    pub score: i32,
}

/// Resuelve la carpeta de notas de forma portable sin hardcodear rutas:
/// 1. ~/.config/notas/config.json -> notasDir (expandiendo $HOME y $XDG_DOCUMENTS_DIR)
/// 2. dirs::document_dir()/notes
/// 3. ~/Documentos/notes o ~/Documents/notes
pub fn resolve_notes_dir() -> PathBuf {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    let config_path = home.join(".config").join("notas").join("config.json");

    if let Ok(content) = fs::read_to_string(&config_path) {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
            if let Some(dir_str) = val.get("notasDir").and_then(|v| v.as_str()) {
                let expanded = expand_env_vars(dir_str, &home);
                let p = PathBuf::from(expanded);
                if p.is_dir() || (!p.exists() && fs::create_dir_all(&p).is_ok()) {
                    return p;
                }
            }
        }
    }

    if let Some(docs) = dirs::document_dir() {
        let p = docs.join("notes");
        if p.is_dir() {
            return p;
        }
    }

    let doc_es = home.join("Documentos").join("notes");
    if doc_es.is_dir() {
        return doc_es;
    }

    let doc_en = home.join("Documents").join("notes");
    if doc_en.is_dir() {
        return doc_en;
    }

    // Si ninguna existe, usar Documentos/notes o Documents/notes por defecto
    if let Some(docs) = dirs::document_dir() {
        let p = docs.join("notes");
        let _ = fs::create_dir_all(&p);
        p
    } else {
        let p = home.join("Documentos").join("notes");
        let _ = fs::create_dir_all(&p);
        p
    }
}

fn expand_env_vars(s: &str, home: &Path) -> String {
    let mut res = s.trim().to_string();
    let home_str = home.to_string_lossy();

    if res == "~" {
        return home_str.to_string();
    }
    if res.starts_with("~/") {
        res = format!("{}{}", home_str, &res[1..]);
    }

    if res.contains("$HOME") {
        res = res.replace("$HOME", &home_str);
    }

    if res.contains("$XDG_DOCUMENTS_DIR") {
        let docs = dirs::document_dir()
            .map(|d| d.to_string_lossy().to_string())
            .unwrap_or_else(|| format!("{}/Documentos", home_str));
        res = res.replace("$XDG_DOCUMENTS_DIR", &docs);
    }

    res
}

/// Normaliza texto para búsqueda: minúsculas y sin acentos
fn normalize_for_search(text: &str) -> String {
    let lower = text.to_lowercase();
    let mut out = String::with_capacity(lower.len());
    for c in lower.chars() {
        match c {
            'á' | 'à' | 'ä' | 'â' | 'ã' => out.push('a'),
            'é' | 'è' | 'ë' | 'ê' => out.push('e'),
            'í' | 'ì' | 'ï' | 'î' => out.push('i'),
            'ó' | 'ò' | 'ö' | 'ô' | 'õ' => out.push('o'),
            'ú' | 'ù' | 'ü' | 'û' => out.push('u'),
            _ => out.push(c),
        }
    }
    out
}

/// Comando --search: busca notas por texto en título, tags y cuerpo
pub fn cmd_search(query: &str, tag_filter: Option<&str>, limit: usize, paths_only: bool, json_output: bool) {
    let notes_dir = resolve_notes_dir();
    let norm_query = normalize_for_search(query);
    let norm_tag = tag_filter.map(|t| normalize_for_search(t.trim_start_matches('#')));

    let mut results: Vec<SearchResult> = Vec::new();

    let walker = WalkDir::new(&notes_dir).into_iter().filter_entry(|e| {
        let name = e.file_name().to_string_lossy();
        if name.starts_with('.') && name != "." {
            return false;
        }
        true
    });

    for entry in walker.filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }

        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();

        if ext != "md" && ext != "txt" {
            continue;
        }

        let content = match fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let (title, subtitle, tags, modified, body) = parse_note_content(&content, path);

        if let Some(ref target_tag) = norm_tag {
            let has_tag = tags.iter().any(|t| normalize_for_search(t) == *target_tag);
            if !has_tag {
                continue;
            }
        }

        let norm_title = normalize_for_search(&title);
        let norm_sub = normalize_for_search(&subtitle);
        let norm_tags: Vec<String> = tags.iter().map(|t| normalize_for_search(t)).collect();
        let norm_body = normalize_for_search(&body);

        let mut score = 0;
        let mut snippet = String::new();

        if norm_query.is_empty() {
            score = 1;
        } else {
            if norm_title == norm_query {
                score += 150;
            } else if norm_title.starts_with(&norm_query) {
                score += 100;
            } else if norm_title.contains(&norm_query) {
                score += 70;
            }

            if norm_sub.contains(&norm_query) {
                score += 30;
            }

            for t in &norm_tags {
                if t == &norm_query {
                    score += 80;
                } else if t.contains(&norm_query) {
                    score += 40;
                }
            }

            if let Some(idx) = norm_body.find(&norm_query) {
                score += 30;
                // Extraer snippet de contexto de ~80 caracteres
                let start = idx.saturating_sub(35);
                let end = (idx + norm_query.len() + 45).min(body.len());
                let raw_sub = &body[start..end];
                let clean_snippet = raw_sub.replace('\n', " ").trim().to_string();
                snippet = if start > 0 { format!("…{}…", clean_snippet) } else { format!("{}…", clean_snippet) };
            }
        }

        if score > 0 {
            let rel_path = path.strip_prefix(&notes_dir).unwrap_or(path);
            let slug = rel_path.with_extension("").to_string_lossy().to_string();

            if snippet.is_empty() {
                snippet = if !subtitle.is_empty() {
                    subtitle
                } else {
                    body.lines().find(|l| !l.trim().is_empty()).unwrap_or("").to_string()
                };
            }

            results.push(SearchResult {
                slug,
                title,
                path: path.to_string_lossy().to_string(),
                tags,
                snippet,
                modified,
                score,
            });
        }
    }

    // Ordenar por score descendente
    results.sort_by(|a, b| b.score.cmp(&a.score));
    if limit > 0 && results.len() > limit {
        results.truncate(limit);
    }

    if json_output {
        println!("{}", serde_json::to_string_pretty(&results).unwrap_or_else(|_| "[]".to_string()));
        return;
    }

    if paths_only {
        for r in &results {
            println!("{}", r.path);
        }
        return;
    }

    // Salida TSV / amigable para launchers o terminal
    if results.is_empty() {
        eprintln!("No se encontraron notas que coincidan con la búsqueda.");
        return;
    }

    for r in &results {
        println!("{}\t{}\t{}", r.path, r.title, r.snippet);
    }
}

/// Extrae título, subtítulo, tags, fecha de modificación y cuerpo limpio
fn parse_note_content(raw: &str, file_path: &Path) -> (String, String, Vec<String>, String, String) {
    let mut title = String::new();
    let mut subtitle = String::new();
    let mut tags = Vec::new();
    let mut modified = String::new();

    let lines: Vec<&str> = raw.lines().collect();
    let mut i = 0;

    // Frontmatter YAML
    if lines.first().map(|l| l.trim() == "---").unwrap_or(false) {
        i = 1;
        while i < lines.len() {
            let line = lines[i];
            if line.trim() == "---" {
                i += 1;
                break;
            }

            if let Some((k, v)) = line.split_once(':') {
                let key = k.trim().to_lowercase();
                let val = v.trim().trim_matches('"').trim_matches('\'');
                match key.as_str() {
                    "title" => title = val.to_string(),
                    "subtitle" => subtitle = val.to_string(),
                    "modified" => modified = val.to_string(),
                    "tags" => {
                        let trimmed = val.trim_start_matches('[').trim_end_matches(']');
                        for t in trimmed.split(',') {
                            let tag = t.trim().trim_matches('"').trim_matches('\'').trim_start_matches('#');
                            if !tag.is_empty() {
                                tags.push(tag.to_string());
                            }
                        }
                    }
                    _ => {}
                }
            }
            i += 1;
        }
    }

    let body_lines = if i < lines.len() { &lines[i..] } else { &[] };
    let body = body_lines.join("\n");

    if title.is_empty() {
        for line in body_lines {
            let tr = line.trim();
            if let Some(h) = tr.strip_prefix("# ") {
                title = h.trim().to_string();
                break;
            }
        }
    }

    if title.is_empty() {
        title = file_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Sin título")
            .to_string();
    }

    (title, subtitle, tags, modified, body)
}

/// Resuelve la ruta exacta de una nota por nombre, slug o búsqueda exacta
pub fn resolve_note_path(notes_dir: &Path, note_query: &str) -> Option<PathBuf> {
    let q = note_query.trim();
    if q.is_empty() {
        return None;
    }

    // 1. Si es ruta absoluta o existente
    let p = Path::new(q);
    if p.is_file() {
        return Some(p.to_path_buf());
    }

    // 2. Ruta directa en notes_dir con o sin extensión
    let direct_md = notes_dir.join(format!("{}.md", q));
    if direct_md.is_file() {
        return Some(direct_md);
    }
    let direct_txt = notes_dir.join(format!("{}.txt", q));
    if direct_txt.is_file() {
        return Some(direct_txt);
    }
    let direct_exact = notes_dir.join(q);
    if direct_exact.is_file() {
        return Some(direct_exact);
    }

    // 3. Búsqueda por slug o nombre de archivo (case-insensitive)
    let norm_q = normalize_for_search(q);
    let walker = WalkDir::new(notes_dir).into_iter().filter_entry(|e| {
        let name = e.file_name().to_string_lossy();
        !name.starts_with('.') || name == "."
    });

    for entry in walker.filter_map(|e| e.ok()) {
        let ep = entry.path();
        if !ep.is_file() {
            continue;
        }
        let stem = ep.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if normalize_for_search(stem) == norm_q {
            return Some(ep.to_path_buf());
        }
    }

    None
}

/// Comando --path-of
pub fn cmd_path_of(note_query: &str) {
    let notes_dir = resolve_notes_dir();
    if let Some(path) = resolve_note_path(&notes_dir, note_query) {
        println!("{}", path.to_string_lossy());
    } else {
        eprintln!("Error: No se encontró la nota '{}' en {:?}", note_query, notes_dir);
        std::process::exit(1);
    }
}

/// Comando --append: agrega texto al final de una nota (o crea inbox.md si no existe)
pub fn cmd_append(text_input: &str, to_note: &str, with_stamp: bool) {
    let notes_dir = resolve_notes_dir();
    let target_name = if to_note.trim().is_empty() { "inbox" } else { to_note.trim() };

    let target_path = match resolve_note_path(&notes_dir, target_name) {
        Some(p) => p,
        None => {
            // Si no existe, crear target_name.md
            let mut filename = target_name.to_string();
            if !filename.ends_with(".md") && !filename.ends_with(".txt") {
                filename.push_str(".md");
            }
            let p = notes_dir.join(&filename);
            let title = p.file_stem().and_then(|s| s.to_str()).unwrap_or("Inbox");
            let initial_content = format!("---\ntitle: \"{}\"\ncreated: \"{}\"\n---\n# {}\n\n",
                title,
                current_timestamp(),
                title
            );
            if let Err(e) = fs::write(&p, initial_content) {
                eprintln!("Error al crear nota {:?}: {}", p, e);
                std::process::exit(1);
            }
            p
        }
    };

    let append_text = if text_input == "-" {
        let mut buffer = String::new();
        if let Err(e) = io::stdin().read_to_string(&mut buffer) {
            eprintln!("Error leyendo texto desde stdin: {}", e);
            std::process::exit(1);
        }
        buffer
    } else {
        text_input.to_string()
    };

    if append_text.trim().is_empty() {
        eprintln!("Aviso: Texto para agregar está vacío.");
        return;
    }

    let mut final_append = String::new();
    if with_stamp {
        final_append.push_str(&format!("\n\n### {}\n\n", current_timestamp()));
    } else {
        final_append.push_str("\n\n");
    }
    final_append.push_str(append_text.trim_end());
    final_append.push('\n');

    let mut file = match OpenOptions::new().append(true).open(&target_path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("Error abriendo {:?} para agregar: {}", target_path, e);
            std::process::exit(1);
        }
    };

    if let Err(e) = file.write_all(final_append.as_bytes()) {
        eprintln!("Error escribiendo en {:?}: {}", target_path, e);
        std::process::exit(1);
    }

    println!("✓ Contenido agregado exitosamente a: {}", target_path.to_string_lossy());

    // Notificar a la app vía IPC si está abierta para que recargue en vivo
    notify_app_reload(&target_path.to_string_lossy());
}

/// Comando --clip: crea una nota nueva o agrega a `--to` desde el portapapeles
pub fn cmd_clip(to_note: Option<&str>, with_stamp: bool) {
    let clip_text = read_system_clipboard();
    if clip_text.trim().is_empty() {
        eprintln!("Error: El portapapeles está vacío o no contiene texto.");
        std::process::exit(1);
    }

    if let Some(target) = to_note {
        cmd_append(&clip_text, target, with_stamp);
        return;
    }

    // Crear nota nueva a partir del portapapeles
    let notes_dir = resolve_notes_dir();
    let lines: Vec<&str> = clip_text.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect();

    let raw_title = lines.first().copied().unwrap_or("Nota rápida");
    let clean_title = sanitize_title_for_filename(raw_title);
    let title_display = if raw_title.len() > 60 { &raw_title[..60] } else { raw_title };

    let mut filename = format!("{}.md", clean_title);
    let mut file_path = notes_dir.join(&filename);
    let mut counter = 2;
    while file_path.exists() {
        filename = format!("{} ({}).md", clean_title, counter);
        file_path = notes_dir.join(&filename);
        counter += 1;
    }

    let is_url = clip_text.trim().starts_with("http://") || clip_text.trim().starts_with("https://");
    let content = if is_url {
        format!("---\ntitle: \"{}\"\ncreated: \"{}\"\ntags: [web, clip]\n---\n# {}\n\n[{}]({})\n",
            title_display,
            current_timestamp(),
            title_display,
            title_display,
            clip_text.trim()
        )
    } else {
        format!("---\ntitle: \"{}\"\ncreated: \"{}\"\ntags: [clip]\n---\n# {}\n\n{}\n",
            title_display,
            current_timestamp(),
            title_display,
            clip_text.trim()
        )
    };

    if let Err(e) = fs::write(&file_path, content) {
        eprintln!("Error al crear nota {:?}: {}", file_path, e);
        std::process::exit(1);
    }

    let path_str = file_path.to_string_lossy().to_string();
    println!("✓ Nota creada desde portapapeles: {}", path_str);

    // Intentar abrir en la app vía IPC
    let _ = crate::try_send_ipc("open", &path_str);
}

fn read_system_clipboard() -> String {
    // 1. Intentar con arboard
    if let Ok(mut cb) = arboard::Clipboard::new() {
        if let Ok(text) = cb.get_text() {
            if !text.trim().is_empty() {
                return text;
            }
        }
    }

    // 2. Fallback a wl-paste
    if let Ok(out) = Command::new("wl-paste").arg("-n").output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).to_string();
            if !s.trim().is_empty() {
                return s;
            }
        }
    }

    String::new()
}

fn sanitize_title_for_filename(raw: &str) -> String {
    let mut out = String::new();
    for c in raw.chars() {
        if c.is_alphanumeric() || c == '-' || c == '_' || c == ' ' {
            out.push(c);
        }
        if out.len() >= 45 {
            break;
        }
    }
    let res = out.trim().replace(' ', "-").to_lowercase();
    if res.is_empty() {
        "nota-rapida".to_string()
    } else {
        res
    }
}

fn current_timestamp() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Formato simple YYYY-MM-DD HH:MM
    let days_since_epoch = now / 86400;
    let secs_of_day = now % 86400;
    let hours = secs_of_day / 3600;
    let minutes = (secs_of_day % 3600) / 60;

    // Aproximación simple de fecha UTC
    let mut year = 1970;
    let mut days = days_since_epoch;
    loop {
        let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        let days_in_year = if leap { 366 } else { 365 };
        if days < days_in_year {
            break;
        }
        days -= days_in_year;
        year += 1;
    }

    let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    let month_days = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut month = 1;
    for &d in &month_days {
        if days < d {
            break;
        }
        days -= d;
        month += 1;
    }
    let day = days + 1;

    format!("{:04}-{:02}-{:02} {:02}:{:02}", year, month, day, hours, minutes)
}

fn notify_app_reload(target_path: &str) {
    let _ = crate::try_send_ipc("reload", target_path);
}
