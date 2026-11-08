// src/instance_hub.rs — Registro y coordinación multi-instancia de criperto.notes
use std::fs;
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct InstanceInfo {
    pub pid: u32,
    #[serde(default)]
    pub active_note: String,
    #[serde(default)]
    pub is_editing: bool,
    #[serde(default)]
    pub last_focused: u64,
}

impl InstanceInfo {
    pub fn sock_path(&self) -> PathBuf {
        get_instances_dir().join(format!("{}.sock", self.pid))
    }
}

pub fn get_instances_dir() -> PathBuf {
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let dir = PathBuf::from(runtime_dir).join("criperto-notes").join("instances");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn is_process_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{}", pid)).exists()
}

pub fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Escanea y retorna todas las instancias activas vivas, limpiando sockets huérfanos.
/// Ordenadas de la más recientemente enfocada a la más antigua.
pub fn list_active_instances() -> Vec<InstanceInfo> {
    let dir = get_instances_dir();
    let mut active = Vec::new();

    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) == Some("json") {
                if let Ok(content) = fs::read_to_string(&path) {
                    if let Ok(info) = serde_json::from_str::<InstanceInfo>(&content) {
                        if is_process_alive(info.pid) {
                            active.push(info);
                            continue;
                        }
                    }
                }
                // Si el proceso ya no está vivo o el JSON estaba corrupto, limpiar
                let _ = fs::remove_file(&path);
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    let sock_path = dir.join(format!("{}.sock", stem));
                    let _ = fs::remove_file(sock_path);
                }
            }
        }
    }

    active.sort_by(|a, b| b.last_focused.cmp(&a.last_focused));
    active
}

/// Envía un comando IPC a una instancia específica
pub fn send_ipc_to_instance(sock_path: &Path, action: &str, target: &str) -> bool {
    if let Ok(mut stream) = UnixStream::connect(sock_path) {
        let payload = serde_json::json!({
            "action": action,
            "target": target,
        });
        if stream.write_all(payload.to_string().as_bytes()).is_ok()
            && stream.write_all(b"\n").is_ok()
            && stream.flush().is_ok()
        {
            return true;
        }
    }
    false
}

/// Envía un comando a la instancia con foco más reciente
pub fn send_to_focused_instance(action: &str, target: &str) -> bool {
    let instances = list_active_instances();
    for inst in instances {
        if send_ipc_to_instance(&inst.sock_path(), action, target) {
            return true;
        }
    }
    false
}

/// Envía un comando a todas las instancias activas
pub fn broadcast_to_all(action: &str, target: &str, exclude_pid: Option<u32>) {
    let instances = list_active_instances();
    for inst in instances {
        if Some(inst.pid) == exclude_pid {
            continue;
        }
        let _ = send_ipc_to_instance(&inst.sock_path(), action, target);
    }
}
