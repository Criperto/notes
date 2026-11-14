use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CatalogLang {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub native: String,
    #[serde(default)]
    pub url_aff: String,
    #[serde(default)]
    pub url_dic: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Catalog {
    #[serde(default)]
    pub languages: Vec<CatalogLang>,
}

#[derive(Serialize, Clone, Debug)]
pub struct DictInfo {
    pub code: String,
    pub name: String,
    pub native: String,
    pub installed: bool,
    pub system: bool,
    pub path: String,
    pub source: String,
}

fn xdg_data_base() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        if !xdg.trim().is_empty() {
            return PathBuf::from(xdg);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".local").join("share")
}

pub fn get_dicts_dir() -> PathBuf {
    xdg_data_base().join("criperto-notes").join("dictionaries")
}

pub fn get_catalog_path() -> PathBuf {
    let installed_cat = xdg_data_base().join("criperto-notes").join("catalog.json");
    if installed_cat.exists() {
        return installed_cat;
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let legacy_cat = PathBuf::from(&home).join(".local").join("share").join("criperto-notes").join("catalog.json");
    if legacy_cat.exists() {
        return legacy_cat;
    }
    let dev_cat = PathBuf::from("assets").join("spellcheck").join("catalog.json");
    if dev_cat.exists() {
        return dev_cat;
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(bin_dir) = exe.parent() {
            let exe_cat = bin_dir.join("../share/criperto-notes/catalog.json");
            if exe_cat.exists() {
                return exe_cat;
            }
        }
    }
    let flatpak_cat = PathBuf::from("/app/share/criperto-notes/catalog.json");
    if flatpak_cat.exists() {
        return flatpak_cat;
    }
    let sys_cat = PathBuf::from("/usr/share/criperto-notes/catalog.json");
    if sys_cat.exists() {
        return sys_cat;
    }
    installed_cat
}

pub fn get_stamp_path() -> PathBuf {
    get_dicts_dir().join(".dicts_stamp")
}

pub fn notify_change() {
    let stamp = get_stamp_path();
    if let Some(parent) = stamp.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(1);
    let _ = fs::write(stamp, now.to_string());
}

pub fn get_system_dict_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(bin_dir) = exe.parent() {
            dirs.push(bin_dir.join("../share/criperto-notes/dictionaries"));
        }
    }
    dirs.push(PathBuf::from("/app/share/criperto-notes/dictionaries"));
    dirs.push(PathBuf::from("/usr/share/criperto-notes/dictionaries"));
    dirs
}

pub fn load_catalog() -> Catalog {
    let cat_path = get_catalog_path();
    if let Ok(content) = fs::read_to_string(&cat_path) {
        if let Ok(cat) = serde_json::from_str::<Catalog>(&content) {
            return cat;
        }
    }
    const DEFAULT_CATALOG: &str = include_str!("../assets/spellcheck/catalog.json");
    if let Ok(cat) = serde_json::from_str::<Catalog>(DEFAULT_CATALOG) {
        return cat;
    }
    Catalog { languages: Vec::new() }
}

pub fn get_installed_dicts() -> HashMap<String, (bool, PathBuf)> {
    let mut map = HashMap::new();

    // 0. Diccionarios base integrados en el binario (alta velocidad, cero dependencias)
    for code in crate::spell_engine::embedded_languages() {
        map.insert(code.to_string(), (true, PathBuf::from(code)));
    }

    // 1. System dictionaries
    for dir in get_system_dict_dirs() {
        if !dir.is_dir() {
            continue;
        }
        if let Ok(rd) = fs::read_dir(&dir) {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.extension().map_or(false, |ext| ext == "dic") {
                    let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
                    let aff_path = dir.join(format!("{}.aff", stem));
                    if aff_path.exists() && !stem.is_empty() {
                        let base_path = dir.join(stem);
                        map.insert(stem.to_string(), (true, base_path));
                    }
                }
            }
        }
    }

    // 2. Local dictionaries (override system and embedded)
    let local_dir = get_dicts_dir();
    if local_dir.is_dir() {
        if let Ok(rd) = fs::read_dir(&local_dir) {
            for entry in rd.flatten() {
                let p = entry.path();
                if p.extension().map_or(false, |ext| ext == "dic") {
                    let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
                    let aff_path = local_dir.join(format!("{}.aff", stem));
                    if aff_path.exists() && !stem.is_empty() {
                        let base_path = local_dir.join(stem);
                        map.insert(stem.to_string(), (false, base_path));
                    }
                }
            }
        }
    }

    map
}

pub fn run(args: &[String]) {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("list");

    match cmd {
        "list" => cmd_list(),
        "install" => {
            if let Some(code) = args.get(1) {
                cmd_install(code);
            } else {
                eprintln!("Uso: notas spell install <code>");
                std::process::exit(1);
            }
        }
        "remove" => {
            if let Some(code) = args.get(1) {
                cmd_remove(code);
            } else {
                eprintln!("Uso: notas spell remove <code>");
                std::process::exit(1);
            }
        }
        "import" => {
            if let Some(path) = args.get(1) {
                cmd_import(path);
            } else {
                eprintln!("Uso: notas spell import <file>");
                std::process::exit(1);
            }
        }
        "resolve" => {
            if let Some(codes) = args.get(1) {
                cmd_resolve(codes);
            } else {
                println!("");
            }
        }
        unknown => {
            eprintln!("Subcomando spell desconocido: {}", unknown);
            std::process::exit(1);
        }
    }
}

fn cmd_list() {
    let catalog = load_catalog();
    let installed = get_installed_dicts();

    let mut result = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for lang in &catalog.languages {
        let is_embedded = crate::spell_engine::is_embedded(&lang.code);
        let is_inst = is_embedded || installed.contains_key(&lang.code);
        let (is_sys, p) = installed
            .get(&lang.code)
            .map(|(s, p)| (*s, p.to_string_lossy().to_string()))
            .unwrap_or_else(|| {
                if is_embedded {
                    (true, lang.code.clone())
                } else {
                    (false, String::new())
                }
            });

        seen.insert(lang.code.clone());
        result.push(DictInfo {
            code: lang.code.clone(),
            name: lang.name.clone(),
            native: if !lang.native.is_empty() {
                lang.native.clone()
            } else {
                lang.name.clone()
            },
            installed: is_inst,
            system: is_sys,
            path: p,
            source: if is_embedded {
                "embedded".to_string()
            } else if is_inst {
                if is_sys { "system".to_string() } else { "local".to_string() }
            } else {
                "catalog".to_string()
            },
        });
    }

    for (code, (is_sys, p)) in installed {
        if !seen.contains(&code) {
            let is_embedded = crate::spell_engine::is_embedded(&code);
            result.push(DictInfo {
                code: code.clone(),
                name: code.clone(),
                native: code.clone(),
                installed: true,
                system: is_sys,
                path: p.to_string_lossy().to_string(),
                source: if is_embedded {
                    "embedded".to_string()
                } else if is_sys {
                    "system".to_string()
                } else {
                    "local".to_string()
                },
            });
        }
    }

    result.sort_by(|a, b| a.name.cmp(&b.name));
    println!("{}", serde_json::to_string(&result).unwrap_or_default());
}

fn cmd_install(code: &str) {
    let catalog = load_catalog();
    let target = catalog.languages.iter().find(|l| l.code.eq_ignore_ascii_case(code));

    let (canonical_code, url_aff, url_dic) = match target {
        Some(t) => (t.code.clone(), t.url_aff.clone(), t.url_dic.clone()),
        None => {
            let err = serde_json::json!({
                "status": "error",
                "message": format!("Idioma '{}' no encontrado en el catálogo", code)
            });
            println!("{}", err);
            return;
        }
    };

    let dicts_dir = get_dicts_dir();
    if let Err(e) = fs::create_dir_all(&dicts_dir) {
        let err = serde_json::json!({
            "status": "error",
            "message": format!("No se pudo crear carpeta de diccionarios: {}", e)
        });
        println!("{}", err);
        return;
    }

    println!("{}", serde_json::json!({ "status": "progress", "progress": 10, "stage": "start" }));
    let _ = std::io::stdout().flush();

    let dest_aff = dicts_dir.join(format!("{}.aff", canonical_code));
    let tmp_aff = dicts_dir.join(format!("{}.aff.tmp", canonical_code));
    let dest_dic = dicts_dir.join(format!("{}.dic", canonical_code));
    let tmp_dic = dicts_dir.join(format!("{}.dic.tmp", canonical_code));

    println!("{}", serde_json::json!({ "status": "progress", "progress": 25, "stage": "aff" }));
    let _ = std::io::stdout().flush();

    let status_aff = Command::new("curl")
        .args(["-sSL", "--fail", "--retry", "2", "-o"])
        .arg(&tmp_aff)
        .arg(&url_aff)
        .status();

    if status_aff.map_or(false, |s| s.success()) && tmp_aff.exists() && fs::metadata(&tmp_aff).map_or(0, |m| m.len()) > 0 {
        let _ = fs::rename(&tmp_aff, &dest_aff);
    } else {
        let _ = fs::remove_file(&tmp_aff);
        let err = serde_json::json!({
            "status": "error",
            "message": format!("Fallo al descargar reglas .aff para {}", canonical_code)
        });
        println!("{}", err);
        return;
    }

    println!("{}", serde_json::json!({ "status": "progress", "progress": 60, "stage": "dic" }));
    let _ = std::io::stdout().flush();

    let status_dic = Command::new("curl")
        .args(["-sSL", "--fail", "--retry", "2", "-o"])
        .arg(&tmp_dic)
        .arg(&url_dic)
        .status();

    if status_dic.map_or(false, |s| s.success()) && tmp_dic.exists() && fs::metadata(&tmp_dic).map_or(0, |m| m.len()) > 0 {
        let _ = fs::rename(&tmp_dic, &dest_dic);
    } else {
        let _ = fs::remove_file(&tmp_dic);
        let _ = fs::remove_file(&dest_aff);
        let err = serde_json::json!({
            "status": "error",
            "message": format!("Fallo al descargar vocabulario .dic para {}", canonical_code)
        });
        println!("{}", err);
        return;
    }

    notify_change();
    println!("{}", serde_json::json!({ "status": "installed", "code": canonical_code, "progress": 100 }));
}

fn cmd_remove(code: &str) {
    let trimmed = code.trim();
    if trimmed.is_empty() || trimmed.contains("..") || trimmed.contains('/') || trimmed.contains('\\') || trimmed.contains('\0') {
        println!("{}", serde_json::json!({
            "success": false,
            "code": code,
            "reason": "invalid_code",
            "message": "Código de idioma inválido."
        }));
        return;
    }

    let installed = get_installed_dicts();
    let canonical_key = installed
        .keys()
        .find(|k| k.eq_ignore_ascii_case(trimmed))
        .cloned()
        .unwrap_or_else(|| trimmed.to_string());

    if let Some((is_sys, _)) = installed.get(&canonical_key) {
        if *is_sys {
            println!("{}", serde_json::json!({
                "success": false,
                "code": canonical_key,
                "reason": "system_dict",
                "message": "Es un diccionario del sistema; solo se puede desactivar."
            }));
            return;
        }
    }

    let dicts_dir = get_dicts_dir();
    let dic = dicts_dir.join(format!("{}.dic", canonical_key));
    let aff = dicts_dir.join(format!("{}.aff", canonical_key));

    let _ = fs::remove_file(dic);
    let _ = fs::remove_file(aff);
    notify_change();

    println!("{}", serde_json::json!({ "status": "removed", "code": canonical_key, "success": true }));
}

fn cmd_import(filepath_str: &str) {
    let path = Path::new(filepath_str);
    if !path.exists() {
        println!("{}", serde_json::json!({ "status": "error", "message": format!("El archivo '{}' no existe", filepath_str) }));
        return;
    }

    let dicts_dir = get_dicts_dir();
    let _ = fs::create_dir_all(&dicts_dir);

    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("diccionario");

    let mut imported = Vec::new();

    if ext == "dic" || ext == "aff" {
        let parent = path.parent().unwrap_or(Path::new("."));
        let aff_src = parent.join(format!("{}.aff", stem));
        let dic_src = parent.join(format!("{}.dic", stem));

        if aff_src.exists() && dic_src.exists() {
            let dest_aff = dicts_dir.join(format!("{}.aff", stem));
            let dest_dic = dicts_dir.join(format!("{}.dic", stem));
            let _ = fs::copy(&aff_src, &dest_aff);
            let _ = fs::copy(&dic_src, &dest_dic);
            imported.push(stem.to_string());
        } else {
            println!("{}", serde_json::json!({
                "status": "error",
                "message": format!("Se requieren ambos archivos '{}.aff' y '{}.dic' en la misma carpeta.", stem, stem)
            }));
            return;
        }
    } else if ext == "oxt" || ext == "zip" {
        // Descomprimir usando bsdtar o unzip
        let tmp_extract = dicts_dir.join(format!("tmp_extract_{}", stem));
        let _ = fs::create_dir_all(&tmp_extract);

        let unz_res = Command::new("unzip")
            .arg("-q")
            .arg(path)
            .arg("-d")
            .arg(&tmp_extract)
            .status();

        if unz_res.map_or(false, |s| s.success()) {
            if let Ok(entries) = walkdir_search_dicts(&tmp_extract) {
                for (aff, dic, bname) in entries {
                    let _ = fs::copy(&aff, dicts_dir.join(format!("{}.aff", bname)));
                    let _ = fs::copy(&dic, dicts_dir.join(format!("{}.dic", bname)));
                    imported.push(bname);
                }
            }
        }
        let _ = fs::remove_dir_all(&tmp_extract);
    }

    if !imported.is_empty() {
        notify_change();
        println!("{}", serde_json::json!({ "status": "imported", "codes": imported }));
    } else {
        println!("{}", serde_json::json!({ "status": "error", "message": "No se encontraron diccionarios válidos dentro del archivo." }));
    }
}

fn walkdir_search_dicts(root: &Path) -> Result<Vec<(PathBuf, PathBuf, String)>, std::io::Error> {
    let mut pairs = Vec::new();
    let walker = walkdir::WalkDir::new(root);
    for entry in walker.into_iter().filter_map(|e| e.ok()) {
        let p = entry.path();
        if p.extension().map_or(false, |ext| ext.eq_ignore_ascii_case("dic")) {
            let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            if let Some(parent) = p.parent() {
                let aff = parent.join(format!("{}.aff", stem));
                if aff.exists() {
                    pairs.push((aff, p.to_path_buf(), stem.to_string()));
                }
            }
        }
    }
    Ok(pairs)
}

fn cmd_resolve(codes_str: &str) {
    let installed = get_installed_dicts();
    let local_dir = get_dicts_dir();
    let codes: Vec<&str> = codes_str.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
    let mut paths = Vec::new();

    for c in codes {
        if let Some((_, p)) = installed.get(c) {
            paths.push(p.to_string_lossy().to_string());
        } else {
            let loc = local_dir.join(c);
            if loc.with_extension("dic").exists() {
                paths.push(loc.to_string_lossy().to_string());
            }
        }
    }
    println!("{}", paths.join(","));
}
