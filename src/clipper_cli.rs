// clipper_cli.rs — Subcomando 'notas clip <url>' para captura de páginas web en Markdown
use serde::Serialize;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use url::Url;

#[derive(Serialize, Debug)]
pub struct ClipResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slug: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub images_count: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub struct ClipOptions {
    pub url: String,
    pub download_images: bool,
    pub full_mode: bool,
    pub json_output: bool,
    pub to_note: Option<String>,
}

pub fn run(args: &[String]) {
    let mut opts = ClipOptions {
        url: String::new(),
        download_images: false,
        full_mode: false,
        json_output: false,
        to_note: None,
    };

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--images" | "-i" => {
                opts.download_images = true;
            }
            "--full" => {
                opts.full_mode = true;
            }
            "--json" => {
                opts.json_output = true;
            }
            "--to" => {
                if i + 1 < args.len() {
                    opts.to_note = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "-h" | "--help" => {
                print_help();
                return;
            }
            arg if !arg.starts_with('-') && opts.url.is_empty() => {
                opts.url = arg.to_string();
            }
            _ => {}
        }
        i += 1;
    }

    if opts.url.trim().is_empty() {
        emit_result(
            &opts,
            Err("Debe especificar una URL válida para recortar (ej: notas clip https://ejemplo.com)".into()),
        );
        return;
    }

    let res = execute_clip(&opts);
    emit_result(&opts, res);
}

fn print_help() {
    println!(
        "Uso: notas clip <URL> [OPCIONES]\n\n\
        Descarga una página web o artículo, limpia el contenido y lo guarda como nota Markdown.\n\n\
        Opciones:\n  \
        -i, --images    Descarga las imágenes a la carpeta local assets/ de la nota\n  \
        --full          Convierte la página completa omitiendo el filtro de modo lectura\n  \
        --to <nota>     Agrega el contenido al final de una nota existente\n  \
        --json          Devuelve el resultado en formato JSON estructurado\n  \
        -h, --help      Muestra esta ayuda"
    );
}

fn emit_result(opts: &ClipOptions, res: Result<(PathBuf, String, usize), String>) {
    match res {
        Ok((path, title, imgs)) => {
            let path_str = path.to_string_lossy().to_string();
            let slug = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();

            if opts.json_output {
                let resp = ClipResponse {
                    ok: true,
                    slug: Some(slug),
                    path: Some(path_str.clone()),
                    title: Some(title),
                    images_count: Some(imgs),
                    error: None,
                };
                println!("{}", serde_json::to_string(&resp).unwrap_or_default());
            } else {
                println!("✓ Artículo recortado exitosamente:");
                println!("  Título: {}", title);
                println!("  Ruta:   {}", path_str);
                if imgs > 0 {
                    println!("  Imágenes descargadas: {}", imgs);
                }
            }

            // Notificar a la app vía IPC para recargar o abrir la nota
            let _ = crate::try_send_ipc("open", &path_str);
        }
        Err(e) => {
            if opts.json_output {
                let resp = ClipResponse {
                    ok: false,
                    slug: None,
                    path: None,
                    title: None,
                    images_count: None,
                    error: Some(e),
                };
                println!("{}", serde_json::to_string(&resp).unwrap_or_default());
            } else {
                eprintln!("Error al recortar la página web: {}", e);
            }
            std::process::exit(1);
        }
    }
}

pub struct ParsedArticle {
    pub title: String,
    pub author: Option<String>,
    pub html_content: String,
    pub url: String,
}

pub fn execute_clip(opts: &ClipOptions) -> Result<(PathBuf, String, usize), String> {
    let clean_url = opts.url.trim();
    if !clean_url.starts_with("http://") && !clean_url.starts_with("https://") {
        return Err("Solo se admiten URLs con protocolo http:// o https://".to_string());
    }

    let (raw_bytes, final_url, content_type) = fetch_url_bytes(clean_url, Duration::from_secs(15))?;
    let html_string = decode_html_bytes(&raw_bytes, content_type.as_deref());

    let article = parse_article_content(&html_string, &final_url, opts.full_mode)?;

    let mut markdown = html_to_markdown(&article.html_content)?;

    let notes_dir = crate::cli_ops::resolve_notes_dir();
    let (target_path, images_count) = if let Some(ref to) = opts.to_note {
        let note_path = match crate::cli_ops::resolve_note_path(&notes_dir, to) {
            Some(p) => p,
            None => {
                let mut filename = to.to_string();
                if !filename.ends_with(".md") && !filename.ends_with(".txt") {
                    filename.push_str(".md");
                }
                notes_dir.join(&filename)
            }
        };
        let mut final_text = format!("\n\n---\n## [{}]({})\n\n", article.title, article.url);
        final_text.push_str(markdown.trim());
        final_text.push('\n');

        let mut file = fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(&note_path)
            .map_err(|e| format!("No se pudo abrir la nota destino: {}", e))?;
        file.write_all(final_text.as_bytes())
            .map_err(|e| format!("Error escribiendo en la nota destino: {}", e))?;
        (note_path, 0)
    } else {
        let base_slug = sanitize_slug(&article.title);
        let timestamp = current_formatted_time();

        if opts.download_images {
            // Nota-carpeta: <slug>/<slug>.md y <slug>/assets/
            let (folder_path, note_slug) = find_unique_folder_note(&notes_dir, &base_slug);
            let assets_dir = folder_path.join("assets");
            fs::create_dir_all(&assets_dir)
                .map_err(|e| format!("No se pudo crear carpeta de assets: {}", e))?;

            let (rewritten_md, img_count) =
                download_and_localize_images(&markdown, &article.url, &assets_dir);
            markdown = rewritten_md;

            let file_path = folder_path.join(format!("{}.md", note_slug));
            let content = build_frontmatter_document(&article, &timestamp, &markdown);
            fs::write(&file_path, content)
                .map_err(|e| format!("Error guardando archivo de nota: {}", e))?;
            (file_path, img_count)
        } else {
            // Nota simple: <slug>.md
            let (file_path, _) = find_unique_file_note(&notes_dir, &base_slug);
            let content = build_frontmatter_document(&article, &timestamp, &markdown);
            fs::write(&file_path, content)
                .map_err(|e| format!("Error guardando archivo de nota: {}", e))?;
            (file_path, 0)
        }
    };

    Ok((target_path, article.title, images_count))
}

fn fetch_url_bytes(
    url: &str,
    timeout: Duration,
) -> Result<(Vec<u8>, String, Option<String>), String> {
    let config = ureq::config::Config::builder()
        .timeout_global(Some(timeout))
        .http_status_as_error(false)
        .build();

    let agent = ureq::Agent::new_with_config(config);

    let response = agent
        .get(url)
        .header(
            "User-Agent",
            "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0 Notas/0.1.0 WebClipper",
        )
        .header(
            "Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        )
        .header("Accept-Language", "es-ES,es;q=0.9,en;q=0.8")
        .call()
        .map_err(|e| format!("Error en conexión HTTP: {}", e))?;

    let status = response.status();
    if status.as_u16() >= 400 {
        return Err(format!(
            "El servidor web devolvió código de error HTTP {}",
            status.as_u16()
        ));
    }

    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let mut body = response.into_body();
    let bytes = body
        .read_to_vec()
        .map_err(|e| format!("Error al descargar el contenido: {}", e))?;

    if bytes.len() > 10 * 1024 * 1024 {
        return Err("La página descargada excede el límite máximo de 10 MB".to_string());
    }

    Ok((bytes, url.to_string(), content_type))
}

pub fn decode_html_bytes(bytes: &[u8], content_type: Option<&str>) -> String {
    // 1. Detectar charset desde Content-Type header si está presente
    let mut detected_encoding = None;
    if let Some(ct) = content_type {
        if let Some(pos) = ct.to_lowercase().find("charset=") {
            let charset_part = &ct[pos + 8..];
            let charset_name = charset_part
                .split(';')
                .next()
                .unwrap_or("")
                .trim()
                .trim_matches('"')
                .trim_matches('\'');
            if let Some(enc) = encoding_rs::Encoding::for_label(charset_name.as_bytes()) {
                detected_encoding = Some(enc);
            }
        }
    }

    // 2. Si no se detectó en header, escanear primeros 2048 bytes para <meta charset="...">
    if detected_encoding.is_none() {
        let sample_len = bytes.len().min(2048);
        let sample = String::from_utf8_lossy(&bytes[..sample_len]).to_lowercase();
        if let Some(idx) = sample.find("charset=") {
            let rest = &sample[idx + 8..];
            let name = rest
                .split(|c: char| c == '"' || c == '\'' || c == ';' || c == '>' || c.is_whitespace())
                .next()
                .unwrap_or("")
                .trim();
            if let Some(enc) = encoding_rs::Encoding::for_label(name.as_bytes()) {
                detected_encoding = Some(enc);
            }
        }
    }

    let encoding = detected_encoding.unwrap_or(encoding_rs::UTF_8);
    let (cow, _, _) = encoding.decode(bytes);
    cow.into_owned()
}

pub fn parse_article_content(
    html: &str,
    page_url: &str,
    full_mode: bool,
) -> Result<ParsedArticle, String> {
    if !full_mode {
        if let Ok(mut readability) = dom_smoothie::Readability::new(html, Some(page_url), None) {
            if let Ok(article) = readability.parse() {
                let title = if !article.title.trim().is_empty() {
                    article.title.trim().to_string()
                } else {
                    extract_fallback_title(html).unwrap_or_else(|| "Artículo Web".to_string())
                };

                return Ok(ParsedArticle {
                    title,
                    author: article.byline.filter(|s| !s.trim().is_empty()),
                    html_content: article.content.to_string(),
                    url: page_url.to_string(),
                });
            }
        }
    }

    // Fallback de página completa: extraer <title> y <body>
    let title = extract_fallback_title(html).unwrap_or_else(|| "Página Web".to_string());
    let body_content = extract_body_content(html);

    Ok(ParsedArticle {
        title,
        author: None,
        html_content: body_content,
        url: page_url.to_string(),
    })
}

fn decode_html_entities_basic(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ")
}

fn extract_fallback_title(html: &str) -> Option<String> {
    let lower = html.to_lowercase();
    if let Some(start) = lower.find("<title") {
        if let Some(tag_close) = lower[start..].find('>') {
            let content_start = start + tag_close + 1;
            if let Some(end) = lower[content_start..].find("</title>") {
                let raw_title = &html[content_start..content_start + end];
                let decoded = decode_html_entities_basic(raw_title).trim().to_string();
                if !decoded.is_empty() {
                    return Some(decoded);
                }
            }
        }
    }
    None
}

fn extract_body_content(html: &str) -> String {
    let lower = html.to_lowercase();
    if let Some(start) = lower.find("<body") {
        if let Some(tag_close) = lower[start..].find('>') {
            let content_start = start + tag_close + 1;
            if let Some(end) = lower[content_start..].find("</body>") {
                return html[content_start..content_start + end].to_string();
            }
            return html[content_start..].to_string();
        }
    }
    html.to_string()
}

pub fn html_to_markdown(html: &str) -> Result<String, String> {
    let converter = htmd::HtmlToMarkdown::builder()
        .skip_tags(vec![
            "script", "style", "noscript", "svg", "iframe", "nav", "footer", "form",
        ])
        .build();

    converter
        .convert(html)
        .map_err(|e| format!("Error en conversión HTML a Markdown: {}", e))
}

pub fn download_and_localize_images(
    markdown: &str,
    base_url_str: &str,
    assets_dir: &Path,
) -> (String, usize) {
    let base_url = match Url::parse(base_url_str) {
        Ok(u) => u,
        Err(_) => return (markdown.to_string(), 0),
    };

    let agent_cfg = ureq::config::Config::builder()
        .timeout_global(Some(Duration::from_secs(10)))
        .http_status_as_error(false)
        .build();
    let agent = ureq::Agent::new_with_config(agent_cfg);

    let mut result_md = markdown.to_string();
    let mut downloaded_count = 0;
    let mut img_index = 1;

    // Patrón simple para encontrar imágenes Markdown: ![alt](url)
    let bytes = markdown.as_bytes();
    let len = bytes.len();
    let mut i = 0;
    let mut replacements: Vec<(String, String)> = Vec::new();

    while i + 2 < len {
        if bytes[i] == b'!' && bytes[i + 1] == b'[' {
            // Encontrar cierre de ']'
            if let Some(close_bracket) = markdown[i + 2..].find(']') {
                let bracket_end = i + 2 + close_bracket;
                if bracket_end + 1 < len && bytes[bracket_end + 1] == b'(' {
                    if let Some(close_paren) = markdown[bracket_end + 2..].find(')') {
                        let paren_end = bracket_end + 2 + close_paren;
                        let raw_url_part = markdown[bracket_end + 2..paren_end].trim();
                        // El url puede tener título al final: (url "title")
                        let raw_img_url = raw_url_part
                            .split_whitespace()
                            .next()
                            .unwrap_or("")
                            .trim_matches('<')
                            .trim_matches('>');

                        if !raw_img_url.is_empty()
                            && !raw_img_url.starts_with("data:")
                            && downloaded_count < 20
                        {
                            if let Ok(resolved_url) = base_url.join(raw_img_url) {
                                let scheme = resolved_url.scheme();
                                if scheme == "http" || scheme == "https" {
                                    let ext = guess_image_extension(&resolved_url);
                                    let filename = format!("image-{:02}.{}", img_index, ext);
                                    let dest_path = assets_dir.join(&filename);

                                    if download_single_image(
                                        &agent,
                                        resolved_url.as_str(),
                                        &dest_path,
                                    ) {
                                        downloaded_count += 1;
                                        img_index += 1;
                                        let old_match = markdown[i..paren_end + 1].to_string();
                                        let alt_text = &markdown[i + 2..bracket_end];
                                        let new_match =
                                            format!("![{}](./assets/{})", alt_text, filename);
                                        replacements.push((old_match, new_match));
                                    }
                                }
                            }
                        }
                        i = paren_end + 1;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }

    for (old, new) in replacements {
        result_md = result_md.replace(&old, &new);
    }

    (result_md, downloaded_count)
}

fn guess_image_extension(url: &Url) -> String {
    if let Some(path_seg) = url.path_segments().and_then(|mut s| s.next_back()) {
        if let Some(ext) = Path::new(path_seg).extension().and_then(|e| e.to_str()) {
            let clean = ext.to_lowercase();
            if clean == "jpg"
                || clean == "jpeg"
                || clean == "png"
                || clean == "webp"
                || clean == "gif"
                || clean == "svg"
            {
                return clean;
            }
        }
    }
    "jpg".to_string()
}

fn download_single_image(agent: &ureq::Agent, url: &str, dest: &Path) -> bool {
    let resp = match agent
        .get(url)
        .header(
            "User-Agent",
            "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0 Notas/0.1.0",
        )
        .header("Accept", "image/avif,image/webp,image/png,image/*,*/*;q=0.8")
        .call()
    {
        Ok(r) => r,
        Err(_) => return false,
    };

    if resp.status().as_u16() != 200 {
        return false;
    }

    let mut body = resp.into_body();
    let bytes = match body.read_to_vec() {
        Ok(b) => b,
        Err(_) => return false,
    };

    // Máximo 5 MB por imagen individual
    if bytes.is_empty() || bytes.len() > 5 * 1024 * 1024 {
        return false;
    }

    if let Ok(mut f) = File::create(dest) {
        return f.write_all(&bytes).is_ok();
    }

    false
}

fn build_frontmatter_document(article: &ParsedArticle, timestamp: &str, markdown: &str) -> String {
    let mut doc = String::new();
    doc.push_str("---\n");
    doc.push_str(&format!("title: \"{}\"\n", escape_yaml_string(&article.title)));
    doc.push_str(&format!("source: \"{}\"\n", escape_yaml_string(&article.url)));
    if let Some(ref author) = article.author {
        doc.push_str(&format!("author: \"{}\"\n", escape_yaml_string(author)));
    }
    doc.push_str(&format!("created: \"{}\"\n", timestamp));
    doc.push_str("tags: [web]\n");
    doc.push_str("---\n\n");

    // Agregar título H1 si el markdown no empieza ya con el título
    let trimmed_md = markdown.trim();
    if !trimmed_md.starts_with("# ") {
        doc.push_str(&format!("# {}\n\n", article.title));
    }
    doc.push_str(trimmed_md);
    doc.push('\n');
    doc
}

fn escape_yaml_string(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

pub fn sanitize_slug(raw_title: &str) -> String {
    let mut out = String::new();
    for c in raw_title.chars() {
        if c.is_alphanumeric() || c == '-' || c == '_' || c == ' ' {
            out.push(c);
        }
        if out.len() >= 50 {
            break;
        }
    }
    let res = out.trim().replace(' ', "-").to_lowercase();
    if res.is_empty() {
        "articulo-web".to_string()
    } else {
        res
    }
}

fn find_unique_file_note(dir: &Path, base_slug: &str) -> (PathBuf, String) {
    let mut slug = base_slug.to_string();
    let mut path = dir.join(format!("{}.md", slug));
    let mut counter = 2;
    while path.exists() {
        slug = format!("{}-{}", base_slug, counter);
        path = dir.join(format!("{}.md", slug));
        counter += 1;
    }
    (path, slug)
}

fn find_unique_folder_note(dir: &Path, base_slug: &str) -> (PathBuf, String) {
    let mut slug = base_slug.to_string();
    let mut folder = dir.join(&slug);
    let mut counter = 2;
    while folder.exists() {
        slug = format!("{}-{}", base_slug, counter);
        folder = dir.join(&slug);
        counter += 1;
    }
    (folder, slug)
}

fn current_formatted_time() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let days_since_epoch = now / 86400;
    let secs_of_day = now % 86400;
    let hours = secs_of_day / 3600;
    let minutes = (secs_of_day % 3600) / 60;

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_slug() {
        assert_eq!(sanitize_slug("Cómo Usar Rust en 2026!"), "cómo-usar-rust-en-2026");
        assert_eq!(sanitize_slug("   "), "articulo-web");
        assert_eq!(sanitize_slug("A/B/C Test * Special"), "abc-test--special");
    }

    #[test]
    fn test_decode_html_bytes() {
        let utf8_bytes = "<h1>Hola Mundo España</h1>".as_bytes();
        let decoded = decode_html_bytes(utf8_bytes, Some("text/html; charset=utf-8"));
        assert!(decoded.contains("Hola Mundo España"));

        let meta_bytes = b"<html><head><meta charset=\"utf-8\"></head><body>Texto</body></html>";
        let decoded_meta = decode_html_bytes(meta_bytes, None);
        assert!(decoded_meta.contains("Texto"));
    }

    #[test]
    fn test_html_to_markdown() {
        let html = "<h1>Título Principal</h1><p>Párrafo con <strong>negrita</strong> y <em>cursiva</em>.</p><ul><li>Uno</li><li>Dos</li></ul>";
        let md = html_to_markdown(html).expect("Conversión markdown falló");
        assert!(md.contains("# Título Principal"));
        assert!(md.contains("**negrita**"));
        assert!(md.contains("*cursiva*"));
        assert!(md.contains("Uno"));
    }

    #[test]
    fn test_build_frontmatter_document() {
        let article = ParsedArticle {
            title: "Guía de Notas".into(),
            author: Some("Tomas".into()),
            html_content: "<p>Contenido</p>".into(),
            url: "https://ejemplo.com/guia".into(),
        };
        let doc = build_frontmatter_document(&article, "2026-11-04 21:00", "Contenido en markdown");
        assert!(doc.contains("title: \"Guía de Notas\""));
        assert!(doc.contains("source: \"https://ejemplo.com/guia\""));
        assert!(doc.contains("author: \"Tomas\""));
        assert!(doc.contains("tags: [web]"));
        assert!(doc.contains("# Guía de Notas"));
        assert!(doc.contains("Contenido en markdown"));
    }

    #[test]
    fn test_guess_image_extension() {
        let url1 = Url::parse("https://ejemplo.com/img/foto.png?w=200").unwrap();
        assert_eq!(guess_image_extension(&url1), "png");

        let url2 = Url::parse("https://ejemplo.com/grafico.JPEG").unwrap();
        assert_eq!(guess_image_extension(&url2), "jpeg");

        let url3 = Url::parse("https://ejemplo.com/sin-extension").unwrap();
        assert_eq!(guess_image_extension(&url3), "jpg");
    }
}
