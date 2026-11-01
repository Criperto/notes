#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
"""doc-to-md.py — Conversor universal de documentos a Markdown (.md)
Soporta PDF, ODT, EPUB, HTML, RTF, CSV, TSV y XLSX.
Soporta extracción de imágenes (FolderNotes), YAML frontmatter y reporte de progreso.

Uso:
    python3 -B doc-to-md.py --input "/ruta/documento.ext" --notes-dir "/home/u/Documentos/notes" --mode copy|move
"""

import sys
sys.dont_write_bytecode = True

import os
import re
import csv
import subprocess
import datetime
import argparse
import zipfile
import html
from html.parser import HTMLParser
import xml.etree.ElementTree as ET


def report_progress(val: float, message: str = ""):
    val = max(0.0, min(1.0, float(val)))
    sys.stdout.write(f"PROGRESS:{val:.2f}\n")
    if message:
        sys.stdout.write(f"STATUS:{message}\n")
    sys.stdout.flush()


def sanitize_title(name: str) -> str:
    base = os.path.splitext(os.path.basename(name))[0]
    return base.strip() or "nota"


def slugify(text: str) -> str:
    s = text.strip().lower()
    s = re.sub(r'[\/\\:*?"<>|\x00-\x1f\x7f¿¡]', ' ', s)
    s = re.sub(r'[\s\-_]+', '_', s)
    s = s.strip('_')
    return s[:80] if s else "nota"


def make_frontmatter(title: str, doc_type: str, tags: list[str] = None) -> str:
    now_iso = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    tag_list = ["importado", doc_type]
    if tags:
        for t in tags:
            clean_t = re.sub(r'[\s,#]+', '_', str(t).strip().lower())
            if clean_t and clean_t not in tag_list:
                tag_list.append(clean_t)
    tags_str = ", ".join(tag_list)
    return (
        "---\n"
        f"title: \"{title.replace('\"', '\\\"')}\"\n"
        f"created: \"{now_iso}\"\n"
        f"modified: \"{now_iso}\"\n"
        "type: note\n"
        f"tags: [{tags_str}]\n"
        "---\n\n"
    )


# ═════════════════════════════════════════════════════════════════════════════
# 1. HTML PARSER (Reutilizable para HTML y EPUB)
# ═════════════════════════════════════════════════════════════════════════════

VOID_ELEMENTS = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}

class HtmlToMarkdownParser(HTMLParser):
    def __init__(self, assets_dir: str = "", base_dir: str = ""):
        super().__init__()
        self.assets_dir = assets_dir
        self.base_dir = base_dir
        self.output = []
        self.tags_stack = []
        self.list_stack = []  # ('ul'|'ol', counter)
        self.in_table = False
        self.table_rows = []
        self.current_row = []
        self.current_cell = []
        self.in_cell = False
        self.is_header_cell = False
        self.cell_is_header = False
        self.in_pre = False
        self.in_code = False
        self.image_count = 0
        self.extracted_images = []
        self.link_stack = []  # hrefs
        self.current_link_text = []

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        tag = tag.lower()
        if tag not in VOID_ELEMENTS:
            self.tags_stack.append(tag)

        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            level = int(tag[1])
            self._ensure_newline(2)
            self.output.append('#' * level + ' ')
        elif tag == 'p':
            self._ensure_newline(2)
        elif tag == 'br':
            self.output.append('\n')
        elif tag == 'hr':
            self._ensure_newline(2)
            self.output.append('---\n\n')
        elif tag in ('strong', 'b'):
            self.output.append('**')
        elif tag in ('em', 'i'):
            self.output.append('*')
        elif tag in ('del', 's', 'strike'):
            self.output.append('~~')
        elif tag == 'code':
            if not self.in_pre:
                self.output.append('`')
            self.in_code = True
        elif tag == 'pre':
            self._ensure_newline(2)
            self.output.append('```\n')
            self.in_pre = True
        elif tag == 'blockquote':
            self._ensure_newline(2)
            self.output.append('> ')
        elif tag == 'ul':
            self._ensure_newline(1)
            self.list_stack.append(('ul', 0))
        elif tag == 'ol':
            self._ensure_newline(1)
            self.list_stack.append(('ol', 1))
        elif tag == 'li':
            self._ensure_newline(1)
            indent = "  " * max(0, len(self.list_stack) - 1)
            if self.list_stack and self.list_stack[-1][0] == 'ol':
                c = self.list_stack[-1][1]
                self.list_stack[-1] = ('ol', c + 1)
                self.output.append(f"{indent}{c}. ")
            else:
                self.output.append(f"{indent}- ")
        elif tag == 'a':
            href = attrs_dict.get('href', '')
            self.link_stack.append(href)
            self.current_link_text = []
        elif tag == 'img':
            src = attrs_dict.get('src', '')
            alt = attrs_dict.get('alt', 'imagen')
            if src:
                resolved_src = self._handle_image(src)
                if self.in_cell:
                    self.current_cell.append(f"![{alt}]({resolved_src})")
                else:
                    self._ensure_newline(1)
                    self.output.append(f"![{alt}]({resolved_src})\n\n")
        elif tag == 'table':
            self._ensure_newline(2)
            self.in_table = True
            self.table_rows = []
        elif tag == 'tr':
            self.current_row = []
        elif tag in ('th', 'td'):
            self.in_cell = True
            self.cell_is_header = (tag == 'th')
            self.current_cell = []

    def handle_endtag(self, tag):
        tag = tag.lower()
        while tag in self.tags_stack:
            popped = self.tags_stack.pop()
            if popped == tag:
                break

        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self.output.append('\n\n')
        elif tag == 'p':
            self.output.append('\n\n')
        elif tag in ('strong', 'b'):
            self.output.append('**')
        elif tag in ('em', 'i'):
            self.output.append('*')
        elif tag in ('del', 's', 'strike'):
            self.output.append('~~')
        elif tag == 'code':
            if not self.in_pre:
                self.output.append('`')
            self.in_code = False
        elif tag == 'pre':
            self._ensure_newline(1)
            self.output.append('```\n\n')
            self.in_pre = False
        elif tag == 'blockquote':
            self.output.append('\n\n')
        elif tag in ('ul', 'ol'):
            if self.list_stack:
                self.list_stack.pop()
            self.output.append('\n')
        elif tag == 'li':
            self.output.append('\n')
        elif tag == 'a':
            if self.link_stack:
                href = self.link_stack.pop()
                link_text = "".join(self.current_link_text).strip() or href
                if href:
                    self.output.append(f"[{link_text}]({href})")
                else:
                    self.output.append(link_text)
                self.current_link_text = []
        elif tag in ('th', 'td'):
            self.in_cell = False
            cell_txt = "".join(self.current_cell).replace('\n', ' ').replace('|', '\\|').strip()
            self.current_row.append((cell_txt, self.cell_is_header))
            self.current_cell = []
        elif tag == 'tr':
            if self.current_row:
                self.table_rows.append(self.current_row)
            self.current_row = []
        elif tag == 'table':
            self.in_table = False
            self._flush_table()

    def handle_data(self, data):
        # Ignorar contenido dentro de script, style, head, noscript
        active_ignored = [t for t in self.tags_stack if t in ('script', 'style', 'head', 'noscript')]
        if active_ignored:
            return

        text = data
        if not self.in_pre:
            text = re.sub(r'[ \t\r\n]+', ' ', text)

        if self.link_stack:
            self.current_link_text.append(text)
            return

        if self.in_cell:
            self.current_cell.append(text)
            return

        if text:
            self.output.append(text)

    def _ensure_newline(self, count=1):
        if not self.output:
            return
        last = "".join(self.output[-2:]) if len(self.output) >= 2 else self.output[-1]
        tail_newlines = 0
        for ch in reversed(last):
            if ch == '\n':
                tail_newlines += 1
            else:
                break
        needed = count - tail_newlines
        if needed > 0:
            self.output.append('\n' * needed)

    def _handle_image(self, src: str) -> str:
        if src.startswith(('http://', 'https://', 'data:')):
            return src
        if not self.assets_dir:
            return src

        # Intentar copiar archivo local
        cand_path = os.path.join(self.base_dir, src) if self.base_dir else src
        if os.path.isfile(cand_path):
            self.image_count += 1
            ext = os.path.splitext(cand_path)[1].lower() or ".png"
            dest_name = f"image_{self.image_count}{ext}"
            dest_path = os.path.join(self.assets_dir, dest_name)
            try:
                os.makedirs(self.assets_dir, exist_ok=True)
                with open(cand_path, 'rb') as rf, open(dest_path, 'wb') as wf:
                    wf.write(rf.read())
                rel_path = f"assets/{dest_name}"
                self.extracted_images.append(dest_path)
                return rel_path
            except Exception:
                return src
        return src

    def _flush_table(self):
        if not self.table_rows:
            return
        num_cols = max(len(r) for r in self.table_rows)
        if num_cols == 0:
            return

        # Cabecera
        header = self.table_rows[0]
        header_cells = [c[0] for c in header] + [""] * (num_cols - len(header))
        self.output.append("| " + " | ".join(header_cells) + " |\n")
        self.output.append("| " + " | ".join(["---"] * num_cols) + " |\n")

        # Filas siguientes
        for row in self.table_rows[1:]:
            cells = [c[0] for c in row] + [""] * (num_cols - len(row))
            self.output.append("| " + " | ".join(cells) + " |\n")
        self.output.append("\n")

    def get_markdown(self) -> str:
        raw = "".join(self.output)
        # Limpieza de exceso de saltos de línea
        raw = re.sub(r'\n{3,}', '\n\n', raw)
        return raw.strip()


# ═════════════════════════════════════════════════════════════════════════════
# 2. CONVERTIDOR DE PDF (PyMuPDF)
# ═════════════════════════════════════════════════════════════════════════════

def convert_pdf(input_path: str, assets_dir: str) -> tuple[str, list[str]]:
    try:
        import fitz  # PyMuPDF
    except ImportError:
        sys.stderr.write("MISSING_DEP:python-pymupdf\n")
        sys.exit(2)

    doc = fitz.open(input_path)
    total_pages = len(doc)
    extracted_images = []
    page_outputs = []

    # Estadísticas para detectar median font size y títulos
    font_sizes = []
    for p_num in range(min(5, total_pages)):
        page = doc[p_num]
        d = page.get_text("dict")
        for b in d.get("blocks", []):
            if b.get("type") == 0:  # texto
                for line in b.get("lines", []):
                    for span in line.get("spans", []):
                        sz = span.get("size", 0)
                        txt = span.get("text", "").strip()
                        if sz > 0 and len(txt) > 2:
                            font_sizes.append(sz)

    median_font = sorted(font_sizes)[len(font_sizes) // 2] if font_sizes else 11.0

    report_progress(0.20, f"Procesando {total_pages} páginas de PDF...")

    image_idx = 0
    total_text_chars = 0

    for p_num in range(total_pages):
        page = doc[p_num]
        progress_val = 0.20 + (0.70 * (p_num / max(1, total_pages)))
        report_progress(progress_val, f"Página {p_num + 1}/{total_pages}...")

        # 1. Detectar tablas con Page.find_tables()
        table_markdowns = []
        table_rects = []
        try:
            tabs = page.find_tables()
            for tab in tabs:
                df = tab.extract()
                if df and len(df) > 1:
                    table_rects.append(fitz.Rect(tab.bbox))
                    lines = []
                    header = [str(c or "").replace('\n', ' ').replace('|', '\\|').strip() for c in df[0]]
                    lines.append("| " + " | ".join(header) + " |")
                    lines.append("| " + " | ".join(["---"] * len(header)) + " |")
                    for r in df[1:]:
                        row_cells = [str(c or "").replace('\n', ' ').replace('|', '\\|').strip() for c in r]
                        # Asegurar igual cantidad de celdas
                        if len(row_cells) < len(header):
                            row_cells += [""] * (len(header) - len(row_cells))
                        lines.append("| " + " | ".join(row_cells[:len(header)]) + " |")
                    table_markdowns.append("\n" + "\n".join(lines) + "\n\n")
        except Exception:
            pass

        # 2. Extraer imágenes si assets_dir está configurado
        page_images = []
        if assets_dir:
            try:
                for img_info in page.get_images(full=True):
                    xref = img_info[0]
                    base_img = doc.extract_image(xref)
                    w, h = base_img.get("width", 0), base_img.get("height", 0)
                    # Filtrar íconos pequeños o decoraciones < 64px
                    if w >= 64 and h >= 64:
                        image_idx += 1
                        ext = base_img.get("ext", "png")
                        img_filename = f"image_{image_idx}.{ext}"
                        img_path = os.path.join(assets_dir, img_filename)
                        os.makedirs(assets_dir, exist_ok=True)
                        with open(img_path, "wb") as f_img:
                            f_img.write(base_img["image"])
                        extracted_images.append(img_path)
                        page_images.append(f"![](assets/{img_filename})\n\n")
            except Exception:
                pass

        # 3. Extraer texto estructurado con tamaños de fuentes
        d = page.get_text("dict")
        page_lines = []

        for b in d.get("blocks", []):
            if b.get("type") == 0:  # bloque de texto
                # Comprobar si intersecta con alguna tabla para no duplicar texto
                block_rect = fitz.Rect(b.get("bbox", [0, 0, 0, 0]))
                if any(block_rect.intersects(t_rect) for t_rect in table_rects):
                    continue

                for line in b.get("lines", []):
                    line_spans = []
                    max_span_sz = 0
                    for span in line.get("spans", []):
                        txt = span.get("text", "")
                        sz = span.get("size", 11.0)
                        flags = span.get("flags", 0)
                        max_span_sz = max(max_span_sz, sz)

                        is_bold = bool(flags & 16) or ("bold" in span.get("font", "").lower())
                        is_italic = bool(flags & 2) or ("italic" in span.get("font", "").lower())

                        fmt_txt = txt
                        if is_bold and is_italic:
                            fmt_txt = f"***{txt.strip()}***"
                        elif is_bold:
                            fmt_txt = f"**{txt.strip()}**"
                        elif is_italic:
                            fmt_txt = f"*{txt.strip()}*"

                        if txt.startswith(" ") and not fmt_txt.startswith(" "):
                            fmt_txt = " " + fmt_txt
                        if txt.endswith(" ") and not fmt_txt.endswith(" "):
                            fmt_txt = fmt_txt + " "
                        line_spans.append(fmt_txt)

                    line_text = "".join(line_spans).strip()
                    if not line_text:
                        continue

                    total_text_chars += len(line_text)

                    # Clasificar encabezados vs texto
                    if max_span_sz >= median_font * 1.85:
                        page_lines.append(f"\n# {line_text}\n")
                    elif max_span_sz >= median_font * 1.45:
                        page_lines.append(f"\n## {line_text}\n")
                    elif max_span_sz >= median_font * 1.25:
                        page_lines.append(f"\n### {line_text}\n")
                    elif line_text.startswith(("• ", "- ", "* ")):
                        page_lines.append(f"- {line_text[2:].strip()}")
                    elif re.match(r'^\d+\.\s', line_text):
                        page_lines.append(line_text)
                    else:
                        page_lines.append(line_text)

        joined_page = "\n".join(page_lines)
        # Tablas agregadas al final de la página
        for t_md in table_markdowns:
            joined_page += "\n" + t_md
        # Imágenes de la página
        for img_md in page_images:
            joined_page += "\n" + img_md

        if joined_page.strip():
            page_outputs.append(joined_page.strip())

    if total_text_chars < 50:
        page_outputs.insert(0, "> [!NOTE]\n> Este documento contiene poco o ningún texto seleccionable (parece ser un PDF escaneado).\n")

    full_md = "\n\n---\n\n".join(page_outputs)
    return full_md, extracted_images


# ═════════════════════════════════════════════════════════════════════════════
# 3. CONVERTIDOR DE ODT (OpenDocument Text vía stdlib)
# ═════════════════════════════════════════════════════════════════════════════

ODT_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
}


def convert_odt(input_path: str, assets_dir: str) -> tuple[str, list[str]]:
    extracted_images = []
    output_parts = []
    image_idx = 0

    with zipfile.ZipFile(input_path) as z:
        # Leer estilos de texto (negrita, cursiva)
        style_fmt = {}  # style_name -> ('bold'|'italic'|'bold_italic')
        for styles_file in ('styles.xml', 'content.xml'):
            if styles_file in z.namelist():
                try:
                    st_tree = ET.fromstring(z.read(styles_file))
                    for st in st_tree.findall('.//style:style', ODT_NS):
                        name = st.attrib.get(f"{{{ODT_NS['style']}}}name")
                        tp = st.find('.//style:text-properties', ODT_NS)
                        if name and tp is not None:
                            fw = tp.attrib.get(f"{{{ODT_NS['fo']}}}font-weight", "")
                            fs = tp.attrib.get(f"{{{ODT_NS['fo']}}}font-style", "")
                            is_b = fw == "bold" or "bold" in fw.lower()
                            is_i = fs == "italic" or "italic" in fs.lower()
                            if is_b and is_i:
                                style_fmt[name] = "bold_italic"
                            elif is_b:
                                style_fmt[name] = "bold"
                            elif is_i:
                                style_fmt[name] = "italic"
                except Exception:
                    pass

        # Leer contenido
        tree = ET.fromstring(z.read('content.xml'))
        body = tree.find('.//office:body/office:text', ODT_NS)
        if body is None:
            return "", []

        def parse_text_node(node) -> str:
            nonlocal image_idx
            res = []
            if node.text:
                res.append(node.text)

            for child in node:
                tag = child.tag
                if tag == f"{{{ODT_NS['text']}}}span":
                    st_name = child.attrib.get(f"{{{ODT_NS['text']}}}style-name", "")
                    fmt = style_fmt.get(st_name, "")
                    inner = parse_text_node(child).strip()
                    if inner:
                        if fmt == "bold_italic":
                            res.append(f" ***{inner}*** ")
                        elif fmt == "bold":
                            res.append(f" **{inner}** ")
                        elif fmt == "italic":
                            res.append(f" *{inner}* ")
                        else:
                            res.append(inner)
                elif tag == f"{{{ODT_NS['text']}}}a":
                    href = child.attrib.get(f"{{{ODT_NS['xlink']}}}href", "")
                    inner = parse_text_node(child).strip() or href
                    res.append(f"[{inner}]({href})")
                elif tag == f"{{{ODT_NS['text']}}}line-break":
                    res.append("\n")
                elif tag == f"{{{ODT_NS['text']}}}tab":
                    res.append("\t")
                elif tag == f"{{{ODT_NS['draw']}}}frame":
                    img_elem = child.find(f".//{{{ODT_NS['draw']}}}image", ODT_NS)
                    if img_elem is not None:
                        href = img_elem.attrib.get(f"{{{ODT_NS['xlink']}}}href", "")
                        if href in z.namelist() and assets_dir:
                            image_idx += 1
                            ext = os.path.splitext(href)[1].lower() or ".png"
                            dest_name = f"image_{image_idx}{ext}"
                            dest_path = os.path.join(assets_dir, dest_name)
                            os.makedirs(assets_dir, exist_ok=True)
                            with open(dest_path, "wb") as f_img:
                                f_img.write(z.read(href))
                            extracted_images.append(dest_path)
                            res.append(f"\n\n![](assets/{dest_name})\n\n")
                else:
                    res.append(parse_text_node(child))

                if child.tail:
                    res.append(child.tail)

            return "".join(res)

        def walk_elements(parent, list_lvl=0):
            for elem in parent:
                tag = elem.tag
                if tag == f"{{{ODT_NS['text']}}}h":
                    lvl = elem.attrib.get(f"{{{ODT_NS['text']}}}outline-level", "1")
                    try:
                        lvl_n = min(6, max(1, int(lvl)))
                    except Exception:
                        lvl_n = 1
                    t = parse_text_node(elem).strip()
                    if t:
                        output_parts.append(f"\n{'#' * lvl_n} {t}\n\n")
                elif tag == f"{{{ODT_NS['text']}}}p":
                    t = parse_text_node(elem).strip()
                    if t:
                        output_parts.append(f"{t}\n\n")
                elif tag == f"{{{ODT_NS['text']}}}list":
                    walk_list(elem, list_lvl)
                elif tag == f"{{{ODT_NS['table']}}}table":
                    parse_table(elem)
                elif tag == f"{{{ODT_NS['text']}}}section":
                    walk_elements(elem, list_lvl)

        def walk_list(list_elem, lvl=0):
            indent = "  " * lvl
            for item in list_elem.findall(f"{{{ODT_NS['text']}}}list-item", ODT_NS):
                item_texts = []
                for child in item:
                    if child.tag == f"{{{ODT_NS['text']}}}p":
                        t = parse_text_node(child).strip()
                        if t:
                            item_texts.append(t)
                    elif child.tag == f"{{{ODT_NS['text']}}}list":
                        walk_list(child, lvl + 1)
                if item_texts:
                    output_parts.append(f"{indent}- {' '.join(item_texts)}\n")
            if lvl == 0:
                output_parts.append("\n")

        def parse_table(tab_elem):
            rows = []
            for tr in tab_elem.findall(f".//{{{ODT_NS['table']}}}table-row", ODT_NS):
                row_cells = []
                for tc in tr.findall(f".//{{{ODT_NS['table']}}}table-cell", ODT_NS):
                    txt = parse_text_node(tc).replace('\n', ' ').replace('|', '\\|').strip()
                    row_cells.append(txt)
                if row_cells:
                    rows.append(row_cells)
            if not rows:
                return

            num_cols = max(len(r) for r in rows)
            header = rows[0] + [""] * (num_cols - len(rows[0]))
            output_parts.append("\n| " + " | ".join(header) + " |\n")
            output_parts.append("| " + " | ".join(["---"] * num_cols) + " |\n")
            for r in rows[1:]:
                cells = r + [""] * (num_cols - len(r))
                output_parts.append("| " + " | ".join(cells) + " |\n")
            output_parts.append("\n")

        walk_elements(body)

    full_md = "".join(output_parts)
    full_md = re.sub(r'\n{3,}', '\n\n', full_md).strip()
    return full_md, extracted_images


# ═════════════════════════════════════════════════════════════════════════════
# 4. CONVERTIDOR DE EPUB (stdlib zipfile + OPF + HTML)
# ═════════════════════════════════════════════════════════════════════════════

def convert_epub(input_path: str, assets_dir: str) -> tuple[str, list[str]]:
    extracted_images = []
    chapter_mds = []

    with zipfile.ZipFile(input_path) as z:
        # 1. Encontrar OPF a través de container.xml
        container_bytes = z.read('META-INF/container.xml')
        c_tree = ET.fromstring(container_bytes)
        rootfile = c_tree.find('.//{*}rootfile')
        if rootfile is None:
            raise ValueError("EPUB inválido: sin rootfile en container.xml")
        opf_path = rootfile.attrib.get('full-path', 'content.opf')
        opf_dir = os.path.dirname(opf_path)

        # 2. Leer OPF (manifest y spine)
        opf_tree = ET.fromstring(z.read(opf_path))
        manifest = {}
        for item in opf_tree.findall('.//{*}manifest/{*}item'):
            i_id = item.attrib.get('id')
            href = item.attrib.get('href')
            media_type = item.attrib.get('media-type', '')
            if i_id and href:
                manifest[i_id] = (href, media_type)

        spine_items = []
        for itemref in opf_tree.findall('.//{*}spine/{*}itemref'):
            idref = itemref.attrib.get('idref')
            if idref in manifest:
                spine_items.append(manifest[idref][0])

        report_progress(0.25, f"Extrayendo {len(spine_items)} capítulos de EPUB...")

        # 3. Extraer imágenes del manifest a assets_dir
        image_idx = 0
        img_href_map = {}
        if assets_dir:
            for i_id, (href, media_type) in manifest.items():
                if media_type.startswith('image/'):
                    norm_href = os.path.normpath(os.path.join(opf_dir, href)).replace('\\', '/')
                    if norm_href in z.namelist():
                        image_idx += 1
                        ext = os.path.splitext(norm_href)[1].lower() or ".png"
                        dest_name = f"image_{image_idx}{ext}"
                        dest_path = os.path.join(assets_dir, dest_name)
                        os.makedirs(assets_dir, exist_ok=True)
                        with open(dest_path, "wb") as f_img:
                            f_img.write(z.read(norm_href))
                        extracted_images.append(dest_path)
                        img_href_map[href] = f"assets/{dest_name}"
                        img_href_map[os.path.basename(href)] = f"assets/{dest_name}"

        # 4. Procesar cada capítulo con el conversor HTML
        for idx, chapter_href in enumerate(spine_items):
            progress_val = 0.25 + (0.65 * (idx / max(1, len(spine_items))))
            report_progress(progress_val, f"Capítulo {idx + 1}/{len(spine_items)}...")

            norm_ch_path = os.path.normpath(os.path.join(opf_dir, chapter_href)).replace('\\', '/')
            if norm_ch_path in z.namelist():
                content_bytes = z.read(norm_ch_path)
                try:
                    ch_html = content_bytes.decode('utf-8')
                except UnicodeDecodeError:
                    ch_html = content_bytes.decode('latin-1', errors='replace')

                # Reemplazar hrefs de imágenes locales mapeadas
                for orig_href, new_ref in img_href_map.items():
                    ch_html = ch_html.replace(f'src="{orig_href}"', f'src="{new_ref}"')
                    ch_html = ch_html.replace(f"src='{orig_href}'", f"src='{new_ref}'")

                parser = HtmlToMarkdownParser(assets_dir=assets_dir, base_dir=opf_dir)
                parser.feed(ch_html)
                ch_md = parser.get_markdown()
                if ch_md.strip():
                    chapter_mds.append(ch_md.strip())

    full_md = "\n\n---\n\n".join(chapter_mds)
    return full_md, extracted_images


# ═════════════════════════════════════════════════════════════════════════════
# 5. CONVERTIDOR DE HTML
# ═════════════════════════════════════════════════════════════════════════════

def convert_html(input_path: str, assets_dir: str) -> tuple[str, list[str]]:
    with open(input_path, 'rb') as f:
        raw = f.read()
    try:
        content = raw.decode('utf-8')
    except UnicodeDecodeError:
        content = raw.decode('latin-1', errors='replace')

    base_dir = os.path.dirname(input_path)
    parser = HtmlToMarkdownParser(assets_dir=assets_dir, base_dir=base_dir)
    parser.feed(content)
    md = parser.get_markdown()
    return md, parser.extracted_images


# ═════════════════════════════════════════════════════════════════════════════
# 6. CONVERTIDOR DE RTF (Rich Text Format vía stdlib)
# ═════════════════════════════════════════════════════════════════════════════

def convert_rtf(input_path: str) -> str:
    with open(input_path, 'rb') as f:
        data = f.read()

    # Tokenizador básico de RTF
    # Ignora grupos no textuales (fonttbl, colortbl, stylesheet, info, pict)
    IGNORED_GROUPS = {b'fonttbl', b'colortbl', b'stylesheet', b'info', b'pict', b'header', b'footer'}
    
    output = []
    stack = []
    i = 0
    n = len(data)

    bold = False
    italic = False
    in_table_row = False
    current_row = []
    current_cell = []

    def flush_cell():
        nonlocal current_cell
        txt = "".join(current_cell).replace('\n', ' ').replace('|', '\\|').strip()
        current_row.append(txt)
        current_cell = []

    def flush_row():
        nonlocal current_row, in_table_row
        if current_row:
            output.append("| " + " | ".join(current_row) + " |\n")
        current_row = []

    while i < n:
        b = data[i:i+1]
        if b == b'{':
            # Ver si es un grupo ignorado
            j = i + 1
            while j < n and data[j:j+1] in (b' ', b'\\'):
                j += 1
            kw_match = re.match(rb'^([a-zA-Z]+)', data[j:])
            kw = kw_match.group(1) if kw_match else b''
            stack.append(kw in IGNORED_GROUPS)
            i += 1
        elif b == b'}':
            if stack:
                stack.pop()
            i += 1
        elif any(stack):
            # Dentro de grupo ignorado
            i += 1
        elif b == b'\\':
            i += 1
            # Control word o símbolo
            if i >= n:
                break
            nxt = data[i:i+1]
            if nxt in (b'\\', b'{', b'}'):
                output.append(nxt.decode('latin-1'))
                i += 1
            elif nxt == b"'":
                # Carácter hexadecimal \'xx
                hex_str = data[i+1:i+3]
                try:
                    char_code = int(hex_str, 16)
                    output.append(bytes([char_code]).decode('latin-1', errors='replace'))
                except Exception:
                    pass
                i += 3
            else:
                kw_match = re.match(rb'^([a-zA-Z]+)(-?\d*)?', data[i:])
                if kw_match:
                    kw = kw_match.group(1).lower()
                    param = kw_match.group(2)
                    i += len(kw_match.group(0))
                    # Espacio delimitador
                    if i < n and data[i:i+1] == b' ':
                        i += 1

                    if kw == b'par' or kw == b'line':
                        output.append('\n\n')
                    elif kw == b'tab':
                        output.append('\t')
                    elif kw == b'bullet':
                        output.append('\n- ')
                    elif kw == b'b':
                        is_on = (param != b'0')
                        if is_on != bold:
                            bold = is_on
                            output.append('**')
                    elif kw == b'i':
                        is_on = (param != b'0')
                        if is_on != italic:
                            italic = is_on
                            output.append('*')
                    elif kw == b'trowd':
                        in_table_row = True
                        current_row = []
                    elif kw == b'cell':
                        flush_cell()
                    elif kw == b'row':
                        flush_row()
                        in_table_row = False
                    elif kw == b'u':
                        try:
                            code_point = int(param)
                            if code_point < 0:
                                code_point += 65536
                            output.append(chr(code_point))
                        except Exception:
                            pass
                else:
                    i += 1
        elif b in (b'\r', b'\n'):
            i += 1
        else:
            try:
                ch = b.decode('latin-1')
                if in_table_row:
                    current_cell.append(ch)
                else:
                    output.append(ch)
            except Exception:
                pass
            i += 1

    text = "".join(output)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


# ═════════════════════════════════════════════════════════════════════════════
# 7. CONVERTIDOR DE CSV / TSV (stdlib csv)
# ═════════════════════════════════════════════════════════════════════════════

def convert_csv(input_path: str, is_tsv: bool = False) -> str:
    delimiter = '\t' if is_tsv else ','
    with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
        # Detectar delimitador si es csv
        if not is_tsv:
            sample = f.read(2048)
            f.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters=',;\t|')
                delimiter = dialect.delimiter
            except Exception:
                delimiter = ','

        reader = csv.reader(f, delimiter=delimiter)
        rows = []
        truncated = False
        for idx, row in enumerate(reader):
            if idx >= 2000:
                truncated = True
                break
            rows.append(row)

    if not rows:
        return "*Archivo CSV/TSV vacío.*"

    num_cols = max(len(r) for r in rows)
    lines = []

    header = [c.replace('\n', ' ').replace('|', '\\|').strip() for c in rows[0]] + [""] * (num_cols - len(rows[0]))
    lines.append("| " + " | ".join(header) + " |")
    lines.append("| " + " | ".join(["---"] * num_cols) + " |")

    for r in rows[1:]:
        cells = [c.replace('\n', ' ').replace('|', '\\|').strip() for c in r] + [""] * (num_cols - len(r))
        lines.append("| " + " | ".join(cells) + " |")

    if truncated:
        lines.append("\n> [!NOTE]\n> La tabla fue truncada a 2000 filas para garantizar fluidez en el editor.\n")

    return "\n".join(lines)


# ═════════════════════════════════════════════════════════════════════════════
# 8. CONVERTIDOR DE XLSX (openpyxl)
# ═════════════════════════════════════════════════════════════════════════════

def convert_xlsx(input_path: str) -> str:
    try:
        import openpyxl
    except ImportError:
        sys.stderr.write("MISSING_DEP:python-openpyxl\n")
        sys.exit(2)

    wb = openpyxl.load_workbook(input_path, read_only=True, data_only=True)
    sheet_mds = []

    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        lines = [f"## {sheet_name}\n"]
        rows = []
        truncated = False

        for idx, row in enumerate(sheet.iter_rows(values_only=True)):
            if idx >= 2000:
                truncated = True
                break
            # Filtrar filas completamente vacías al final
            if any(c is not None for c in row):
                row_str = [str(c if c is not None else "").replace('\n', ' ').replace('|', '\\|').strip() for c in row]
                rows.append(row_str)

        if rows:
            num_cols = max(len(r) for r in rows)
            header = rows[0] + [""] * (num_cols - len(rows[0]))
            lines.append("| " + " | ".join(header) + " |")
            lines.append("| " + " | ".join(["---"] * num_cols) + " |")

            for r in rows[1:]:
                cells = r + [""] * (num_cols - len(r))
                lines.append("| " + " | ".join(cells) + " |")

            if truncated:
                lines.append("\n> [!NOTE]\n> Hoja truncada a 2000 filas.\n")
            sheet_mds.append("\n".join(lines))

    wb.close()
    return "\n\n".join(sheet_mds) if sheet_mds else "*Libro Excel vacío.*"


# ═════════════════════════════════════════════════════════════════════════════
# 9. DISPATCHER PRINCIPAL
# ═════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Conversor universal de documentos a Markdown")
    parser.add_argument("--input", "-i", required=True, help="Ruta al archivo a convertir")
    parser.add_argument("--notes-dir", "-d", default="", help="Directorio base de notas")
    parser.add_argument("--mode", "-m", choices=["copy", "move"], default="copy", help="Modo (copy o move)")
    args = parser.parse_args()

    input_file = os.path.abspath(os.path.expanduser(args.input))
    if not os.path.isfile(input_file):
        sys.stderr.write(f"Error: no existe el archivo {input_file}\n")
        sys.exit(1)

    notes_dir = os.path.abspath(os.path.expanduser(args.notes_dir)) if args.notes_dir else os.path.dirname(input_file)
    os.makedirs(notes_dir, exist_ok=True)

    raw_title = sanitize_title(input_file)
    ext = os.path.splitext(input_file)[1].lstrip('.').lower()

    report_progress(0.05, f"Iniciando conversión de {ext.upper()}...")

    # Crear directorio temporal para assets potenciales
    # Si al final hay imágenes, se convertirá en nota-carpeta.
    temp_slug = slugify(raw_title)
    cand_folder = os.path.join(notes_dir, raw_title)
    cand_assets = os.path.join(cand_folder, "assets")

    extracted_images = []
    body_md = ""

    if ext == "pdf":
        body_md, extracted_images = convert_pdf(input_file, cand_assets)
    elif ext == "odt":
        body_md, extracted_images = convert_odt(input_file, cand_assets)
    elif ext == "epub":
        body_md, extracted_images = convert_epub(input_file, cand_assets)
    elif ext in ("html", "htm"):
        body_md, extracted_images = convert_html(input_file, cand_assets)
    elif ext == "rtf":
        body_md = convert_rtf(input_file)
    elif ext == "csv":
        body_md = convert_csv(input_file, is_tsv=False)
    elif ext == "tsv":
        body_md = convert_csv(input_file, is_tsv=True)
    elif ext == "xlsx":
        body_md = convert_xlsx(input_file)
    elif ext == "docx":
        # Redirigir a docx-to-md.py si estuviera disponible
        script_dir = os.path.dirname(os.path.abspath(__file__))
        docx_script = os.path.join(script_dir, "docx-to-md.py")
        if os.path.isfile(docx_script):
            os.execv(sys.executable, [sys.executable, "-B", docx_script, "--input", input_file, "--notes-dir", notes_dir, "--mode", args.mode])
        else:
            sys.stderr.write("Error: docx-to-md.py no encontrado\n")
            sys.exit(1)
    else:
        sys.stderr.write(f"Error: formato no soportado .{ext}\n")
        sys.exit(1)

    report_progress(0.92, "Estructurando archivo Markdown...")

    has_images = len(extracted_images) > 0
    frontmatter = make_frontmatter(raw_title, ext)
    full_content = frontmatter + body_md.strip() + "\n"

    if has_images:
        # Nota carpeta: el directorio cand_folder ya contiene assets/
        os.makedirs(cand_folder, exist_ok=True)
        md_file_path = os.path.join(cand_folder, f"{raw_title}.md")
    else:
        # Nota simple plana sin carpeta
        if os.path.isdir(cand_assets) and not os.listdir(cand_assets):
            try:
                os.rmdir(cand_assets)
                os.rmdir(cand_folder)
            except Exception:
                pass
        cand_md = os.path.join(notes_dir, f"{raw_title}.md")
        n = 2
        while os.path.exists(cand_md):
            cand_md = os.path.join(notes_dir, f"{raw_title} ({n}).md")
            n += 1
        md_file_path = cand_md

    with open(md_file_path, 'w', encoding='utf-8') as f:
        f.write(full_content)

    # Si se solicitó mover origen a papelera
    if args.mode == "move":
        try:
            ret = subprocess.run(["gio", "trash", input_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if ret.returncode != 0:
                os.remove(input_file)
        except Exception as e:
            sys.stderr.write(f"Aviso al quitar origen: {e}\n")

    report_progress(1.00, "¡Conversión completada con éxito!")
    sys.stdout.write(f"RESULT:{md_file_path}\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
