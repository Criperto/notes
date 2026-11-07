// math_cli.rs — Motor de renderizado LaTeX a SVG nativo en Rust puro
// Utiliza latex-rust con fuentes matemáticas STIX Two Math embebidas y modelo de cajas TeX.
// Provee tanto interfaz CLI como exportación FFI C directa para la GUI en QML/C++.

use latex_rust::{latex_to_svg, Color, Dim, MathFont, SvgOptions};
use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;

static MATH_FONT: OnceLock<Option<MathFont>> = OnceLock::new();

fn get_math_font() -> Result<&'static MathFont, String> {
    let opt = MATH_FONT.get_or_init(|| MathFont::stix_two_math().ok());
    opt.as_ref().ok_or_else(|| "Error cargando fuentes STIX Two Math".to_string())
}

fn parse_hex_color(hex_str: &str) -> Option<Color> {
    let clean = hex_str.trim().trim_start_matches('#');
    if clean.len() == 3 {
        let r = u8::from_str_radix(&clean[0..1], 16).ok()? * 17;
        let g = u8::from_str_radix(&clean[1..2], 16).ok()? * 17;
        let b = u8::from_str_radix(&clean[2..3], 16).ok()? * 17;
        Some(Color::rgb(r, g, b))
    } else if clean.len() >= 6 {
        let r = u8::from_str_radix(&clean[0..2], 16).ok()?;
        let g = u8::from_str_radix(&clean[2..4], 16).ok()?;
        let b = u8::from_str_radix(&clean[4..6], 16).ok()?;
        Some(Color::rgb(r, g, b))
    } else {
        None
    }
}

pub fn render_latex_to_svg(
    latex: &str,
    display: bool,
    color_hex: Option<&str>,
    pt_size: Option<f64>,
) -> Result<String, String> {
    let font = get_math_font()?;
    let mut options = SvgOptions::new();
    options.display = display;

    if let Some(pt) = pt_size {
        if pt > 0.0 {
            options.font_size_pt = Dim::ratio((pt * 10.0).round() as i64, 10);
        }
    }

    let col = color_hex
        .and_then(parse_hex_color)
        .unwrap_or(Color::rgb(255, 255, 255));
    options.color = col;

    latex_to_svg(latex, font, &options)
        .map_err(|e| format!("{:?}", e))
}

// ── Exportación FFI C directa para la GUI en QML/C++ (cero subprocesos) ───────

#[no_mangle]
pub extern "C" fn notas_render_latex_svg(
    latex_ptr: *const c_char,
    display: bool,
    color_ptr: *const c_char,
    pt_size: f64,
) -> *mut c_char {
    if latex_ptr.is_null() {
        return std::ptr::null_mut();
    }
    let c_str = unsafe { CStr::from_ptr(latex_ptr) };
    let latex = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let color_opt = if !color_ptr.is_null() {
        let col_c_str = unsafe { CStr::from_ptr(color_ptr) };
        col_c_str.to_str().ok()
    } else {
        None
    };
    let pt_opt = if pt_size > 0.0 { Some(pt_size) } else { None };

    match render_latex_to_svg(latex, display, color_opt, pt_opt) {
        Ok(svg) => match CString::new(svg) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(err_msg) => {
            let err_str = format!("ERROR:{}", err_msg);
            match CString::new(err_str) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn notas_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// ── Despacho CLI headless (notas math "<latex>" [opciones]) ─────────────────

pub fn run(args: &[String]) {
    if args.is_empty() || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
        println!(
            "Uso: criperto.notes math \"<formula_latex>\" [opciones]\n\n\
             Opciones:\n  \
               --display              Renderizar como bloque centrado (display style)\n  \
               --color <#hex>         Color de primer plano (ej: #ffffff o #e56018)\n  \
               --size <pt>            Tamaño de fuente en puntos (por defecto 12pt)\n\n\
             Ejemplos:\n  \
               criperto.notes math \"\\frac{{-b \\pm \\sqrt{{b^2 - 4ac}}}}{{2a}}\" --display\n  \
               criperto.notes math \"E = mc^2\" --color \"#ffffff\""
        );
        return;
    }

    let latex = &args[0];
    let mut display = false;
    let mut color = None;
    let mut size = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--display" => {
                display = true;
                i += 1;
            }
            "--color" if i + 1 < args.len() => {
                color = Some(args[i + 1].as_str());
                i += 2;
            }
            "--size" if i + 1 < args.len() => {
                if let Ok(s) = args[i + 1].parse::<f64>() {
                    size = Some(s);
                }
                i += 2;
            }
            _ => {
                i += 1;
            }
        }
    }

    match render_latex_to_svg(latex, display, color, size) {
        Ok(svg) => {
            print!("{}", svg);
        }
        Err(err) => {
            eprintln!("Error renderizando LaTeX: {}", err);
            std::process::exit(1);
        }
    }
}
