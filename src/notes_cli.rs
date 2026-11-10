use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::process::Command;
use std::time::UNIX_EPOCH;
use walkdir::WalkDir;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct NoteMeta {
    pub key: String,
    pub slug: String,
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    #[serde(rename = "filePath")]
    pub file_path: String,
    #[serde(rename = "fileModified")]
    pub file_modified: String,
    pub mtime: f64,
    pub size: u64,
    #[serde(rename = "isFolderNote")]
    pub is_folder_note: bool,
    #[serde(rename = "baseFolder")]
    pub base_folder: String,
    pub title: String,
    pub subtitle: String,
    pub tags: Vec<String>,
    pub pinned: bool,
    pub color: String,
    pub created: String,
    pub modified: String,
    #[serde(rename = "previewImages")]
    pub preview_images: Vec<String>,
    pub hash: u32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ImageDims {
    pub width: u32,
    pub height: u32,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct NotesIndexResponse {
    pub ok: bool,
    pub notes: Vec<NoteMeta>,
    pub images: HashMap<String, ImageDims>,
}

pub fn run(args: &[String]) {
    if args.is_empty() {
        eprintln!("Uso: notas notes <index | paste-image | image-dims> [args...]");
        std::process::exit(1);
    }

    match args[0].as_str() {
        "index" => {
            if args.len() < 2 {
                eprintln!("Uso: notas notes index <notes_dir>");
                std::process::exit(1);
            }
            cmd_index(&args[1]);
        }
        "paste-image" => {
            if args.len() < 3 {
                eprintln!("Uso: notas notes paste-image <assets_dir> <base_name> [rel_prefix]");
                std::process::exit(1);
            }
            let rel_prefix = if args.len() >= 4 { &args[3] } else { "assets/" };
            cmd_paste_image(&args[1], &args[2], rel_prefix);
        }
        "image-dims" => {
            if args.len() < 2 {
                eprintln!("Uso: notas notes image-dims <image_path>");
                std::process::exit(1);
            }
            cmd_image_dims(&args[1]);
        }
        unknown => {
            eprintln!("Subcomando desconocido: notes {}", unknown);
            std::process::exit(1);
        }
    }
}

fn cmd_index(notes_dir_str: &str) {
    println!("{}", index_notes_to_json(notes_dir_str));
}

pub fn index_notes_to_json(notes_dir_str: &str) -> String {
    let notes_dir = Path::new(notes_dir_str);
    if !notes_dir.exists() || !notes_dir.is_dir() {
        let resp = NotesIndexResponse {
            ok: false,
            notes: Vec::new(),
            images: HashMap::new(),
        };
        return serde_json::to_string(&resp).unwrap_or_default();
    }

    let mut notes = Vec::new();
    let mut images = HashMap::new();

    let walker = WalkDir::new(notes_dir).into_iter().filter_entry(|e| {
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

        let rel_path = match path.strip_prefix(notes_dir) {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(_) => continue,
        };

        if ext == "md" || ext == "txt" {
            if let Some(meta) = parse_note_meta(notes_dir, path, &rel_path) {
                notes.push(meta);
            }
        } else if matches!(
            ext.as_str(),
            "png" | "jpg" | "jpeg" | "webp" | "gif" | "bmp" | "svg"
        ) {
            if let Some(dims) = parse_image_dimensions(path) {
                images.insert(rel_path, dims);
            }
        }
    }

    notes.sort_by(|a, b| {
        b.pinned
            .cmp(&a.pinned)
            .then_with(|| b.mtime.partial_cmp(&a.mtime).unwrap_or(std::cmp::Ordering::Equal))
    });

    let resp = NotesIndexResponse {
        ok: true,
        notes,
        images,
    };

    serde_json::to_string(&resp).unwrap_or_default()
}

#[no_mangle]
pub extern "C" fn notas_index_notes(notes_dir_ptr: *const std::os::raw::c_char) -> *mut std::os::raw::c_char {
    if notes_dir_ptr.is_null() {
        return std::ptr::null_mut();
    }
    let c_str = unsafe { std::ffi::CStr::from_ptr(notes_dir_ptr) };
    let notes_dir_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let json_str = index_notes_to_json(notes_dir_str);
    match std::ffi::CString::new(json_str) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn parse_note_meta(notes_dir: &Path, file_path: &Path, rel_path: &str) -> Option<NoteMeta> {
    let metadata = fs::metadata(file_path).ok()?;
    let size = metadata.len();
    let mtime = metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs_f64() * 1000.0)
        .unwrap_or(0.0);

    let file_modified = metadata
        .modified()
        .ok()
        .map(|t| {
            let dur = t.duration_since(UNIX_EPOCH).unwrap_or_default();
            format!("{}", dur.as_secs())
        })
        .unwrap_or_default();

    let parent_dir = file_path.parent().unwrap_or(notes_dir);
    let is_folder_note = if let Some(parent_name) = parent_dir.file_name().and_then(|n| n.to_str()) {
        let stem = file_path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        parent_name == stem || stem == "index"
    } else {
        false
    };

    let base_folder = if is_folder_note {
        parent_dir.to_string_lossy().to_string()
    } else {
        parent_dir.to_string_lossy().to_string()
    };

    let mut slug = rel_path.to_string();
    if slug.ends_with(".md") {
        slug.truncate(slug.len() - 3);
    } else if slug.ends_with(".txt") {
        slug.truncate(slug.len() - 4);
    }

    let default_title = file_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(&slug)
        .to_string();

    let mut title = default_title.clone();
    let mut subtitle = String::new();
    let mut tags = Vec::new();
    let mut pinned = false;
    let mut color = String::new();
    let mut created = String::new();
    let mut modified = String::new();
    let mut preview_images = Vec::new();

    let mut file = File::open(file_path).ok()?;
    let mut buffer = [0u8; 8192];
    let bytes_read = file.read(&mut buffer).ok().unwrap_or(0);
    let sample = String::from_utf8_lossy(&buffer[..bytes_read]);

    let mut lines = sample.lines();
    if let Some(first_line) = lines.next() {
        if first_line.trim() == "---" {
            for line in lines.by_ref() {
                let trimmed = line.trim();
                if trimmed == "---" {
                    break;
                }
                if let Some((k, v)) = trimmed.split_once(':') {
                    let key = k.trim().to_lowercase();
                    let val = v.trim().trim_matches('"').trim_matches('\'').trim();
                    match key.as_str() {
                        "title" => {
                            if !val.is_empty() {
                                title = val.to_string();
                            }
                        }
                        "subtitle" => subtitle = val.to_string(),
                        "pinned" => pinned = val.eq_ignore_ascii_case("true"),
                        "color" => color = val.to_string(),
                        "created" => created = val.to_string(),
                        "modified" => modified = val.to_string(),
                        "tags" => {
                            let clean = val.trim_matches('[').trim_matches(']');
                            for t in clean.split(',') {
                                let tag = t.trim().trim_matches('"').trim_matches('\'').trim();
                                if !tag.is_empty() && !tags.contains(&tag.to_string()) {
                                    tags.push(tag.to_string());
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    if title == default_title {
        for line in sample.lines() {
            let t = line.trim();
            if let Some(h1) = t.strip_prefix("# ") {
                let candidate = h1.trim();
                if !candidate.is_empty() {
                    title = candidate.to_string();
                    break;
                }
            }
        }
    }

    if subtitle.is_empty() {
        let mut in_fm = false;
        let mut passed_fm = false;
        let mut found_h1 = false;
        for line in sample.lines() {
            let t = line.trim();
            if !passed_fm {
                if t == "---" {
                    if in_fm {
                        passed_fm = true;
                        continue;
                    } else {
                        in_fm = true;
                        continue;
                    }
                }
                if in_fm {
                    continue;
                }
            }
            if !found_h1 {
                if t.starts_with("# ") {
                    found_h1 = true;
                }
            } else if !t.is_empty() && !t.starts_with("```") {
                if let Some(h2) = t.strip_prefix("## ") {
                    subtitle = h2.trim().to_string();
                } else if !t.starts_with('#') && !t.starts_with("![") {
                    subtitle = t.to_string();
                }
                break;
            }
        }
    }

    let mut search_pos = 0;
    while let Some(idx) = sample[search_pos..].find("![") {
        let abs_idx = search_pos + idx;
        if let Some(close_bracket) = sample[abs_idx..].find("](") {
            let url_start = abs_idx + close_bracket + 2;
            if let Some(close_paren) = sample[url_start..].find(')') {
                let url = sample[url_start..url_start + close_paren].trim();
                let clean_url = url.split_whitespace().next().unwrap_or("").trim_matches('<').trim_matches('>');
                if !clean_url.is_empty()
                    && !clean_url.starts_with("http://")
                    && !clean_url.starts_with("https://")
                    && !preview_images.contains(&clean_url.to_string())
                {
                    preview_images.push(clean_url.to_string());
                }
                search_pos = url_start + close_paren + 1;
                continue;
            }
        }
        search_pos = abs_idx + 2;
    }

    let hash = (mtime as u32) ^ (size as u32);

    Some(NoteMeta {
        key: rel_path.to_string(),
        slug,
        id: rel_path.to_string(),
        file_name: rel_path.to_string(),
        file_path: file_path.to_string_lossy().to_string(),
        file_modified,
        mtime,
        size,
        is_folder_note,
        base_folder,
        title,
        subtitle,
        tags,
        pinned,
        color,
        created,
        modified,
        preview_images,
        hash,
    })
}

fn parse_image_dimensions(path: &Path) -> Option<ImageDims> {
    let mut file = File::open(path).ok()?;
    let mut header = [0u8; 32];
    let n = file.read(&mut header).ok()?;
    if n < 16 {
        return None;
    }

    // PNG
    if &header[..8] == b"\x89PNG\r\n\x1a\n" && n >= 24 {
        let w = u32::from_be_bytes([header[16], header[17], header[18], header[19]]);
        let h = u32::from_be_bytes([header[20], header[21], header[22], header[23]]);
        return Some(ImageDims { width: w, height: h });
    }

    // GIF
    if (&header[..6] == b"GIF87a" || &header[..6] == b"GIF89a") && n >= 10 {
        let w = u16::from_le_bytes([header[6], header[7]]) as u32;
        let h = u16::from_le_bytes([header[8], header[9]]) as u32;
        return Some(ImageDims { width: w, height: h });
    }

    // BMP
    if &header[..2] == b"BM" && n >= 26 {
        let w = i32::from_le_bytes([header[18], header[19], header[20], header[21]]).unsigned_abs();
        let h = i32::from_le_bytes([header[22], header[23], header[24], header[25]]).unsigned_abs();
        return Some(ImageDims { width: w, height: h });
    }

    // JPEG
    if header[0] == 0xFF && header[1] == 0xD8 {
        let mut full_buf = Vec::new();
        let _ = file.read_to_end(&mut full_buf);
        let mut all = Vec::with_capacity(header.len() + full_buf.len());
        all.extend_from_slice(&header[..n]);
        all.extend_from_slice(&full_buf);

        let mut i = 2;
        while i + 4 < all.len() {
            if all[i] != 0xFF {
                i += 1;
                continue;
            }
            let marker = all[i + 1];
            if marker == 0xD9 || marker == 0xDA {
                break;
            }
            let len = u16::from_be_bytes([all[i + 2], all[i + 3]]) as usize;
            if matches!(marker, 0xC0..=0xC3 | 0xC5..=0xC7 | 0xC9..=0xCB | 0xCD..=0xCF) && i + 8 < all.len() {
                let h = u16::from_be_bytes([all[i + 5], all[i + 6]]) as u32;
                let w = u16::from_be_bytes([all[i + 7], all[i + 8]]) as u32;
                return Some(ImageDims { width: w, height: h });
            }
            i += 2 + len;
        }
    }

    None
}

fn cmd_image_dims(path_str: &str) {
    let p = Path::new(path_str);
    if let Some(dims) = parse_image_dimensions(p) {
        println!("{}", serde_json::to_string(&dims).unwrap_or_default());
    } else {
        eprintln!("No se pudieron determinar las dimensiones de: {}", path_str);
        std::process::exit(1);
    }
}

fn cmd_paste_image(assets_dir_str: &str, base_name: &str, rel_prefix: &str) {
    let assets_dir = Path::new(assets_dir_str);
    if let Err(e) = fs::create_dir_all(assets_dir) {
        eprintln!("Error creando directorio assets {}: {}", assets_dir_str, e);
        std::process::exit(1);
    }

    let output = match Command::new("wl-paste").arg("-l").output() {
        Ok(out) => out,
        Err(e) => {
            eprintln!("Error ejecutando wl-paste -l: {}", e);
            std::process::exit(1);
        }
    };

    let types_str = String::from_utf8_lossy(&output.stdout);
    let mut selected_mime = "";
    let mut ext = "png";

    for line in types_str.lines() {
        let t = line.trim();
        match t.to_lowercase().as_str() {
            "image/png" => {
                selected_mime = "image/png";
                ext = "png";
                break;
            }
            "image/jpeg" | "image/jpg" => {
                selected_mime = t;
                ext = "jpg";
                break;
            }
            "image/webp" => {
                selected_mime = "image/webp";
                ext = "webp";
                break;
            }
            "image/gif" => {
                selected_mime = "image/gif";
                ext = "gif";
                break;
            }
            "image/svg+xml" => {
                selected_mime = "image/svg+xml";
                ext = "svg";
                break;
            }
            "image/bmp" | "image/x-bmp" | "image/x-ms-bmp" => {
                selected_mime = t;
                ext = "bmp";
                break;
            }
            _ => {}
        }
    }

    if !selected_mime.is_empty() {
        let dest_filename = format!("{}.{}", base_name, ext);
        let dest_path = assets_dir.join(&dest_filename);
        let tmp_path = assets_dir.join(format!("{}.{}.tmp", base_name, ext));

        let dump = Command::new("wl-paste")
            .arg("-t")
            .arg(selected_mime)
            .output();

        if let Ok(dump_out) = dump {
            if dump_out.status.success() && !dump_out.stdout.is_empty() {
                if fs::write(&tmp_path, &dump_out.stdout).is_ok() {
                    if fs::rename(&tmp_path, &dest_path).is_ok() {
                        println!("{}{}", rel_prefix, dest_filename);
                        return;
                    }
                }
                let _ = fs::remove_file(&tmp_path);
            }
        }
    }

    eprintln!("No se encontró imagen válida en el portapapeles.");
    std::process::exit(1);
}
