// history_cli.rs — Backend de historial de versiones y snapshots para Notas
// Almacena snapshots fuera de la carpeta de notas (~/.local/state/qs-notes/history/)
// y provee subcomandos headless y operaciones CLI para la GUI.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VersionMeta {
    pub id: String,
    pub timestamp: String,
    pub label: String,
    #[serde(default)]
    pub is_manual: bool,
    pub size: usize,
    pub hash: String,
    pub added: usize,
    pub removed: usize,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct HistoryMeta {
    pub path: String,
    #[serde(default)]
    pub versions: Vec<VersionMeta>,
}

// ── Hash FNV-1a determinista de 64 bits ───────────────────────────────────────
pub fn hash_content(s: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", h)
}

pub fn hash_path_short(path: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in path.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    let folded = ((h >> 32) ^ (h & 0xffffffff)) as u32;
    format!("{:08x}", folded)
}

// ── Directorio base de historial ─────────────────────────────────────────────
pub fn history_base_dir() -> PathBuf {
    if let Ok(state_home) = std::env::var("XDG_STATE_HOME") {
        PathBuf::from(state_home).join("qs-notes").join("history")
    } else if let Ok(home) = std::env::var("HOME") {
        PathBuf::from(home).join(".local").join("state").join("qs-notes").join("history")
    } else {
        std::env::temp_dir().join("qs-notes-history")
    }
}

pub fn note_history_dir(note_path: &Path) -> PathBuf {
    let abs_path = if note_path.is_absolute() {
        note_path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")).join(note_path)
    };
    let file_stem = abs_path.file_stem().and_then(|s| s.to_str()).unwrap_or("note");
    let safe_stem: String = file_stem
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect();
    let hash = hash_path_short(&abs_path.to_string_lossy());
    let folder_name = format!("{}-{}", safe_stem, hash);
    history_base_dir().join(folder_name)
}

// ── Estimación de líneas añadidas/eliminadas (LCS simple) ───────────────────
pub fn count_line_diff(prev: &str, curr: &str) -> (usize, usize) {
    let prev_lines: Vec<&str> = prev.lines().collect();
    let curr_lines: Vec<&str> = curr.lines().collect();

    let n = prev_lines.len();
    let m = curr_lines.len();

    if n == 0 {
        return (m, 0);
    }
    if m == 0 {
        return (0, n);
    }

    // Matriz LCS acotada para prevenir explosión de memoria en archivos enormes
    if n > 2000 || m > 2000 {
        let added = if m > n { m - n } else { 0 };
        let removed = if n > m { n - m } else { 0 };
        return (added, removed);
    }

    let mut dp = vec![vec![0u16; m + 1]; n + 1];
    for i in 0..n {
        for j in 0..m {
            if prev_lines[i] == curr_lines[j] {
                dp[i + 1][j + 1] = dp[i][j] + 1;
            } else {
                dp[i + 1][j + 1] = dp[i + 1][j].max(dp[i][j + 1]);
            }
        }
    }

    let lcs = dp[n][m] as usize;
    let added = m.saturating_sub(lcs);
    let removed = n.saturating_sub(lcs);
    (added, removed)
}

// ── Cargar / Guardar metadata ────────────────────────────────────────────────
fn load_meta(hist_dir: &Path, note_path_str: &str) -> HistoryMeta {
    let meta_file = hist_dir.join("meta.json");
    if let Ok(content) = fs::read_to_string(&meta_file) {
        if let Ok(meta) = serde_json::from_str::<HistoryMeta>(&content) {
            return meta;
        }
    }
    HistoryMeta {
        path: note_path_str.to_string(),
        versions: Vec::new(),
    }
}

fn save_meta(hist_dir: &Path, meta: &HistoryMeta) -> Result<(), std::io::Error> {
    let meta_file = hist_dir.join("meta.json");
    let content = serde_json::to_string_pretty(meta).unwrap_or_else(|_| "{}".to_string());
    fs::write(meta_file, content)
}

// ── Formatear timestamp actual ISO-8601 UTC ──────────────────────────────────
fn current_iso_time() -> (String, String) {
    let now = SystemTime::now();
    let secs = now.duration_since(SystemTime::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);

    // Conversión UTC determinista
    let sec = secs % 60;
    let min = (secs / 60) % 60;
    let hour = (secs / 3600) % 24;
    let days = secs / 86400;

    // Algoritmo civil day to date
    let z = days as i64 + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    let id = format!("{:04}{:02}{:02}-{:02}{:02}{:02}", year, m, d, hour, min, sec);
    let iso = format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", year, m, d, hour, min, sec);
    (id, iso)
}

// ── Operación: Snapshot ──────────────────────────────────────────────────────
pub fn cmd_snapshot(
    note_path_str: &str,
    label: Option<&str>,
    is_manual: bool,
    max_versions: usize,
) -> Result<VersionMeta, String> {
    let note_path = Path::new(note_path_str);
    if !note_path.exists() {
        return Err(format!("El archivo no existe: {}", note_path_str));
    }

    let content = fs::read_to_string(note_path)
        .map_err(|e| format!("Error leyendo nota: {}", e))?;

    let cur_hash = hash_content(&content);
    let hist_dir = note_history_dir(note_path);
    let v_dir = hist_dir.join("v");

    fs::create_dir_all(&v_dir).map_err(|e| format!("Error creando dir de historial: {}", e))?;

    let mut meta = load_meta(&hist_dir, note_path_str);

    // Deduplicación: si el último snapshot tiene el mismo hash exacto, no duplicar
    if let Some(last) = meta.versions.last() {
        if last.hash == cur_hash && !is_manual {
            return Ok(last.clone());
        }
    }

    // Calcular added y removed contra el snapshot anterior
    let (added, removed) = if let Some(last) = meta.versions.last() {
        let last_file = v_dir.join(format!("{}.md", last.id));
        if let Ok(prev_text) = fs::read_to_string(&last_file) {
            count_line_diff(&prev_text, &content)
        } else {
            (content.lines().count(), 0)
        }
    } else {
        (content.lines().count(), 0)
    };

    let (id, iso_ts) = current_iso_time();
    let snapshot_file = v_dir.join(format!("{}.md", id));

    fs::write(&snapshot_file, &content)
        .map_err(|e| format!("Error guardando snapshot {}: {}", id, e))?;

    let default_label = if is_manual {
        "manual"
    } else if meta.versions.is_empty() {
        "auto · base"
    } else {
        "auto"
    };

    let v_meta = VersionMeta {
        id: id.clone(),
        timestamp: iso_ts,
        label: label.unwrap_or(default_label).to_string(),
        is_manual,
        size: content.len(),
        hash: cur_hash,
        added,
        removed,
    };

    meta.versions.push(v_meta.clone());

    // Poda automática
    prune_meta(&mut meta, &v_dir, max_versions);

    save_meta(&hist_dir, &meta).map_err(|e| format!("Error guardando metadata: {}", e))?;

    Ok(v_meta)
}

// ── Poda de versiones ────────────────────────────────────────────────────────
fn prune_meta(meta: &mut HistoryMeta, v_dir: &Path, max_versions: usize) {
    if meta.versions.len() <= max_versions {
        return;
    }

    // Separar manuales (nunca se podan) de automáticas
    let mut kept: Vec<VersionMeta> = Vec::new();
    let mut to_delete_ids: Vec<String> = Vec::new();

    let _now_secs = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let _one_day = 86400;

    // Dejar las manuales y clasificar automáticas
    let mut autos: Vec<VersionMeta> = Vec::new();
    for v in meta.versions.drain(..) {
        if v.is_manual {
            kept.push(v);
        } else {
            autos.push(v);
        }
    }

    // Permitidas para automáticas
    let allowed_autos = max_versions.saturating_sub(kept.len());
    if autos.len() > allowed_autos {
        let prune_count = autos.len() - allowed_autos;
        // Podar las más viejas
        for v in autos.drain(..prune_count) {
            to_delete_ids.push(v.id);
        }
    }

    kept.extend(autos);
    // Ordenar cronológicamente por id
    kept.sort_by(|a, b| a.id.cmp(&b.id));
    meta.versions = kept;

    // Borrar archivos de disco
    for del_id in to_delete_ids {
        let f = v_dir.join(format!("{}.md", del_id));
        let _ = fs::remove_file(f);
    }
}

// ── Operación: Listar ────────────────────────────────────────────────────────
pub fn cmd_list(note_path_str: &str, as_json: bool) -> Result<String, String> {
    let note_path = Path::new(note_path_str);
    let hist_dir = note_history_dir(note_path);
    let meta = load_meta(&hist_dir, note_path_str);

    if as_json {
        serde_json::to_string_pretty(&meta.versions)
            .map_err(|e| format!("Error serializando JSON: {}", e))
    } else {
        if meta.versions.is_empty() {
            return Ok(format!("No hay historial registrado para: {}", note_path_str));
        }
        let mut out = format!("Historial de versiones para {}:\n", note_path_str);
        out.push_str(&format!("{:<17} {:<22} {:<15} {:<8} {:<10}\n", "ID", "FECHA", "ETIQUETA", "TIPO", "CAMBIOS"));
        out.push_str(&format!("{}\n", "-".repeat(78)));
        for v in meta.versions.iter().rev() {
            let tipo = if v.is_manual { "manual" } else { "auto" };
            let cambios = format!("+{} -{}", v.added, v.removed);
            out.push_str(&format!(
                "{:<17} {:<22} {:<15} {:<8} {:<10}\n",
                v.id, v.timestamp, v.label, tipo, cambios
            ));
        }
        Ok(out)
    }
}

// ── Operación: Mostrar snapshot ──────────────────────────────────────────────
pub fn cmd_show(note_path_str: &str, version_id: &str) -> Result<String, String> {
    let note_path = Path::new(note_path_str);
    let hist_dir = note_history_dir(note_path);
    let snapshot_file = hist_dir.join("v").join(format!("{}.md", version_id));

    if !snapshot_file.exists() {
        return Err(format!("No se encontró la versión '{}' para {}", version_id, note_path_str));
    }

    fs::read_to_string(&snapshot_file)
        .map_err(|e| format!("Error leyendo versión {}: {}", version_id, e))
}

// ── Operación: Restaurar versión ─────────────────────────────────────────────
pub fn cmd_restore(note_path_str: &str, version_id: &str) -> Result<String, String> {
    let note_path = Path::new(note_path_str);
    if !note_path.exists() {
        return Err(format!("El archivo de destino no existe: {}", note_path_str));
    }

    let hist_dir = note_history_dir(note_path);
    let snapshot_file = hist_dir.join("v").join(format!("{}.md", version_id));

    if !snapshot_file.exists() {
        return Err(format!("No se encontró la versión '{}' a restaurar", version_id));
    }

    // 1. Crear un snapshot del estado actual antes de sobrescribir
    let _ = cmd_snapshot(note_path_str, Some("Antes de restaurar"), true, 50);

    // 2. Sobrescribir nota con el snapshot elegido
    let version_content = fs::read_to_string(&snapshot_file)
        .map_err(|e| format!("Error leyendo versión: {}", e))?;

    fs::write(note_path, version_content)
        .map_err(|e| format!("Error escribiendo nota restaurada: {}", e))?;

    Ok(format!("Versión '{}' restaurada exitosamente en {}", version_id, note_path_str))
}

// ── Operación: Purgar historial ──────────────────────────────────────────────
pub fn cmd_purge(note_path_str: &str) -> Result<(), String> {
    let note_path = Path::new(note_path_str);
    let hist_dir = note_history_dir(note_path);
    if hist_dir.exists() {
        fs::remove_dir_all(&hist_dir)
            .map_err(|e| format!("Error eliminando directorio de historial: {}", e))?;
    }
    Ok(())
}

// ── Operación: Mover / Renombrar historial ────────────────────────────────────
pub fn cmd_move(old_path_str: &str, new_path_str: &str) -> Result<(), String> {
    let old_dir = note_history_dir(Path::new(old_path_str));
    let new_dir = note_history_dir(Path::new(new_path_str));

    if old_dir.exists() && old_dir != new_dir {
        if let Some(parent) = new_dir.parent() {
            let _ = fs::create_dir_all(parent);
        }
        fs::rename(&old_dir, &new_dir)
            .map_err(|e| format!("Error renombrando carpeta de historial: {}", e))?;

        // Actualizar la ruta en meta.json
        let mut meta = load_meta(&new_dir, new_path_str);
        meta.path = new_path_str.to_string();
        let _ = save_meta(&new_dir, &meta);
    }
    Ok(())
}

// ── Operación: Guardar / Cargar pila de Undo persistente ──────────────────────
pub fn save_undo_stack(note_path_str: &str, undo_json: &str) -> Result<(), String> {
    let hist_dir = note_history_dir(Path::new(note_path_str));
    fs::create_dir_all(&hist_dir).map_err(|e| e.to_string())?;
    let undo_file = hist_dir.join("undo.json");
    fs::write(&undo_file, undo_json).map_err(|e| format!("Error guardando undo stack: {}", e))
}

pub fn load_undo_stack(note_path_str: &str) -> Result<String, String> {
    let hist_dir = note_history_dir(Path::new(note_path_str));
    let undo_file = hist_dir.join("undo.json");
    if undo_file.exists() {
        fs::read_to_string(&undo_file).map_err(|e| format!("Error leyendo undo stack: {}", e))
    } else {
        Ok(String::new())
    }
}

// ── Operación: Despacho desde el CLI ─────────────────────────────────────────
pub fn handle_history_command(args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
        return Ok(
            "Uso: notas history <snapshot|list|show|restore|purge|move|save-undo|load-undo> <archivo.md> [opciones]\n\
             Comandos:\n  \
               snapshot <nota> [--label <etiqueta>] [--manual]  Crear un snapshot\n  \
               list <nota> [--json]                            Listar versiones\n  \
               show <nota> <version_id>                        Mostrar contenido de una versión\n  \
               restore <nota> <version_id>                     Restaurar versión\n  \
               purge <nota>                                    Eliminar historial\n  \
               move <vieja_ruta> <nueva_ruta>                  Renombrar historial\n  \
               save-undo <nota> <json_data>                    Guardar pila de undo\n  \
               load-undo <nota>                                Cargar pila de undo"
                .to_string(),
        );
    }

    let subcmd = args[0].as_str();
    match subcmd {
        "snapshot" => {
            if args.len() < 2 {
                return Err("Falta la ruta del archivo. Uso: notas history snapshot <nota.md>".to_string());
            }
            let path = &args[1];
            let mut label = None;
            let mut is_manual = false;
            let mut i = 2;
            while i < args.len() {
                if args[i] == "--label" && i + 1 < args.len() {
                    label = Some(args[i + 1].as_str());
                    i += 2;
                } else if args[i] == "--manual" {
                    is_manual = true;
                    i += 1;
                } else {
                    i += 1;
                }
            }
            let res = cmd_snapshot(path, label, is_manual, 50)?;
            serde_json::to_string_pretty(&res).map_err(|e| e.to_string())
        }
        "list" => {
            if args.len() < 2 {
                return Err("Falta la ruta del archivo. Uso: notas history list <nota.md> [--json]".to_string());
            }
            let path = &args[1];
            let as_json = args.iter().any(|a| a == "--json");
            cmd_list(path, as_json)
        }
        "show" => {
            if args.len() < 3 {
                return Err("Falta ID de versión. Uso: notas history show <nota.md> <version_id>".to_string());
            }
            cmd_show(&args[1], &args[2])
        }
        "restore" => {
            if args.len() < 3 {
                return Err("Falta ID de versión. Uso: notas history restore <nota.md> <version_id>".to_string());
            }
            cmd_restore(&args[1], &args[2])
        }
        "purge" => {
            if args.len() < 2 {
                return Err("Falta la ruta del archivo. Uso: notas history purge <nota.md>".to_string());
            }
            cmd_purge(&args[1])?;
            Ok(format!("Historial purgado para: {}", args[1]))
        }
        "move" => {
            if args.len() < 3 {
                return Err("Faltan rutas. Uso: notas history move <origen.md> <destino.md>".to_string());
            }
            cmd_move(&args[1], &args[2])?;
            Ok(format!("Historial movido de {} a {}", args[1], args[2]))
        }
        "save-undo" => {
            if args.len() < 3 {
                return Err("Uso: notas history save-undo <nota.md> <json_data>".to_string());
            }
            save_undo_stack(&args[1], &args[2])?;
            Ok("ok".to_string())
        }
        "load-undo" => {
            if args.len() < 2 {
                return Err("Uso: notas history load-undo <nota.md>".to_string());
            }
            load_undo_stack(&args[1])
        }
        other => Err(format!("Comando de historial desconocido: '{}'", other)),
    }
}
