// src/diff_core.rs — Motor de Diff nativo en Rust (Algoritmo de Myers O(ND))
// Optimizado para cálculo de diferencias entre líneas y palabras en tiempo real.

use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct DiffLineOp {
    pub r#type: String,
    pub line: String,
    #[serde(rename = "aIdx")]
    pub a_idx: i32,
    #[serde(rename = "bIdx")]
    pub b_idx: i32,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct DiffWordOp {
    pub r#type: String,
    pub text: String,
}

struct InternalOp<T> {
    op_type: &'static str,
    val: T,
    a_idx: i32,
    b_idx: i32,
}

fn myers<T: Clone + PartialEq>(a: &[T], b: &[T]) -> Vec<InternalOp<T>> {
    let n = a.len();
    let m = b.len();

    if n == 0 {
        return b
            .iter()
            .enumerate()
            .map(|(bi, item)| InternalOp {
                op_type: "add",
                val: item.clone(),
                a_idx: -1,
                b_idx: bi as i32,
            })
            .collect();
    }

    if m == 0 {
        return a
            .iter()
            .enumerate()
            .map(|(ai, item)| InternalOp {
                op_type: "del",
                val: item.clone(),
                a_idx: ai as i32,
                b_idx: -1,
            })
            .collect();
    }

    let max_d = n + m;
    let offset = max_d as isize;
    let v_size = 2 * max_d + 3;
    let mut v = vec![-1isize; v_size];
    v[(offset + 1) as usize] = 0;

    let mut trace: Vec<Vec<isize>> = Vec::new();
    let mut found_d: Option<usize> = None;

    for d in 0..=max_d {
        trace.push(v.clone());

        let d_isize = d as isize;
        let mut k = -d_isize;
        while k <= d_isize {
            let k_idx = (offset + k) as usize;
            let mut x = if k == -d_isize || (k != d_isize && v[k_idx - 1] < v[k_idx + 1]) {
                v[k_idx + 1]
            } else {
                v[k_idx - 1] + 1
            };
            let mut y = x - k;

            while x < n as isize && y < m as isize && a[x as usize] == b[y as usize] {
                x += 1;
                y += 1;
            }

            v[k_idx] = x;

            if x >= n as isize && y >= m as isize {
                found_d = Some(d);
                break;
            }
            k += 2;
        }

        if found_d.is_some() {
            break;
        }
    }

    let mut script: Vec<InternalOp<T>> = Vec::new();
    let mut curr_x = n as isize;
    let mut curr_y = m as isize;

    for d_step in (1..trace.len()).rev() {
        let prev_v = &trace[d_step];
        let step_k = curr_x - curr_y;
        let step_k_idx = (offset + step_k) as usize;
        let d_isize = d_step as isize;

        let prev_k = if step_k == -d_isize || (step_k != d_isize && prev_v[step_k_idx - 1] < prev_v[step_k_idx + 1]) {
            step_k + 1
        } else {
            step_k - 1
        };

        let prev_x = prev_v[(offset + prev_k) as usize];
        let prev_y = prev_x - prev_k;

        while curr_x > prev_x && curr_y > prev_y {
            curr_x -= 1;
            curr_y -= 1;
            script.push(InternalOp {
                op_type: "equal",
                val: a[curr_x as usize].clone(),
                a_idx: curr_x as i32,
                b_idx: curr_y as i32,
            });
        }

        if curr_x == prev_x {
            curr_y -= 1;
            script.push(InternalOp {
                op_type: "add",
                val: b[curr_y as usize].clone(),
                a_idx: -1,
                b_idx: curr_y as i32,
            });
        } else if curr_y == prev_y {
            curr_x -= 1;
            script.push(InternalOp {
                op_type: "del",
                val: a[curr_x as usize].clone(),
                a_idx: curr_x as i32,
                b_idx: -1,
            });
        }
    }

    while curr_x > 0 && curr_y > 0 {
        curr_x -= 1;
        curr_y -= 1;
        script.push(InternalOp {
            op_type: "equal",
            val: a[curr_x as usize].clone(),
            a_idx: curr_x as i32,
            b_idx: curr_y as i32,
        });
    }

    script.reverse();
    script
}

pub fn diff_lines(text_a: &str, text_b: &str) -> Vec<DiffLineOp> {
    if text_a == text_b {
        if text_a.is_empty() {
            return Vec::new();
        }
        return text_a
            .split('\n')
            .enumerate()
            .map(|(idx, line)| DiffLineOp {
                r#type: "equal".to_string(),
                line: line.to_string(),
                a_idx: idx as i32,
                b_idx: idx as i32,
            })
            .collect();
    }

    let lines_a: Vec<&str> = text_a.split('\n').collect();
    let lines_b: Vec<&str> = text_b.split('\n').collect();

    // 1. Recortar prefijo común
    let mut start = 0;
    let min_len = lines_a.len().min(lines_b.len());
    while start < min_len && lines_a[start] == lines_b[start] {
        start += 1;
    }

    // 2. Recortar sufijo común
    let mut end_a = lines_a.len() as isize - 1;
    let mut end_b = lines_b.len() as isize - 1;
    let start_isize = start as isize;
    while end_a >= start_isize && end_b >= start_isize && lines_a[end_a as usize] == lines_b[end_b as usize] {
        end_a -= 1;
        end_b -= 1;
    }

    let mut res = Vec::new();

    // Prefijo común
    for p in 0..start {
        res.push(DiffLineOp {
            r#type: "equal".to_string(),
            line: lines_a[p].to_string(),
            a_idx: p as i32,
            b_idx: p as i32,
        });
    }

    // Centro con Myers
    let middle_a = if end_a >= start_isize {
        &lines_a[start..=(end_a as usize)]
    } else {
        &[]
    };
    let middle_b = if end_b >= start_isize {
        &lines_b[start..=(end_b as usize)]
    } else {
        &[]
    };

    if !middle_a.is_empty() || !middle_b.is_empty() {
        let diff_mid = myers(middle_a, middle_b);
        for item in diff_mid {
            res.push(DiffLineOp {
                r#type: item.op_type.to_string(),
                line: item.val.to_string(),
                a_idx: if item.a_idx != -1 { start as i32 + item.a_idx } else { -1 },
                b_idx: if item.b_idx != -1 { start as i32 + item.b_idx } else { -1 },
            });
        }
    }

    // Sufijo común
    let mut s_a = end_a + 1;
    let mut s_b = end_b + 1;
    while (s_a as usize) < lines_a.len() {
        res.push(DiffLineOp {
            r#type: "equal".to_string(),
            line: lines_a[s_a as usize].to_string(),
            a_idx: s_a as i32,
            b_idx: s_b as i32,
        });
        s_a += 1;
        s_b += 1;
    }

    res
}

fn tokenize_words(line: &str) -> Vec<String> {
    if line.is_empty() {
        return Vec::new();
    }

    let mut tokens = Vec::new();
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if is_word_char(c) {
            let start = i;
            while i < chars.len() && is_word_char(chars[i]) {
                i += 1;
            }
            tokens.push(chars[start..i].iter().collect());
        } else if c.is_whitespace() {
            let start = i;
            while i < chars.len() && chars[i].is_whitespace() {
                i += 1;
            }
            tokens.push(chars[start..i].iter().collect());
        } else {
            tokens.push(c.to_string());
            i += 1;
        }
    }
    tokens
}

fn is_word_char(c: char) -> bool {
    c.is_alphanumeric()
        || matches!(
            c,
            'á' | 'é' | 'í' | 'ó' | 'ú' | 'Á' | 'É' | 'Í' | 'Ó' | 'Ú' | 'ñ' | 'Ñ' | 'ü' | 'Ü'
        )
}

pub fn diff_words(line_a: &str, line_b: &str) -> Vec<DiffWordOp> {
    if line_a == line_b {
        return vec![DiffWordOp {
            r#type: "equal".to_string(),
            text: line_a.to_string(),
        }];
    }

    let tokens_a = tokenize_words(line_a);
    let tokens_b = tokenize_words(line_b);

    let raw_diff = myers(&tokens_a, &tokens_b);

    let mut merged: Vec<DiffWordOp> = Vec::new();
    for cur in raw_diff {
        if let Some(last) = merged.last_mut() {
            if last.r#type == cur.op_type {
                last.text.push_str(&cur.val);
                continue;
            }
        }
        merged.push(DiffWordOp {
            r#type: cur.op_type.to_string(),
            text: cur.val,
        });
    }

    merged
}

#[no_mangle]
pub extern "C" fn notas_diff_lines(text_a_ptr: *const c_char, text_b_ptr: *const c_char) -> *mut c_char {
    if text_a_ptr.is_null() || text_b_ptr.is_null() {
        return std::ptr::null_mut();
    }
    let text_a = unsafe { CStr::from_ptr(text_a_ptr) }.to_string_lossy();
    let text_b = unsafe { CStr::from_ptr(text_b_ptr) }.to_string_lossy();

    let ops = diff_lines(&text_a, &text_b);
    match serde_json::to_string(&ops) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn notas_diff_words(line_a_ptr: *const c_char, line_b_ptr: *const c_char) -> *mut c_char {
    if line_a_ptr.is_null() || line_b_ptr.is_null() {
        return std::ptr::null_mut();
    }
    let line_a = unsafe { CStr::from_ptr(line_a_ptr) }.to_string_lossy();
    let line_b = unsafe { CStr::from_ptr(line_b_ptr) }.to_string_lossy();

    let ops = diff_words(&line_a, &line_b);
    match serde_json::to_string(&ops) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}
