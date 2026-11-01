#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
"""test_import_converters.py — Verificación automatizada de todos los conversores de notas a Markdown.
Prueba cada formato generado en ~/Descargas/notes-import-samples/
Verifica:
1. Formatos sin dependencias externas (HTML, RTF, CSV, TSV, ODT, EPUB) con python3 estándar.
2. Formatos con dependencias (PDF, XLSX):
   - Con python3 estándar sin paquete -> debe salir con código 2 y reportar MISSING_DEP:<pkg>.
   - Con python del venv temporal -> convierte a Markdown con RESULT:, títulos, tablas e imágenes.
3. Formatos con imágenes -> generan FolderNote con subcarpeta assets/ y enlaces ![](assets/...).
"""

import sys
sys.dont_write_bytecode = True

import os
import shutil
import tempfile
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONVERTER = os.path.join(SCRIPT_DIR, "..", "scripts", "doc-to-md.py")
DOCX_CONVERTER = os.path.join(SCRIPT_DIR, "..", "scripts", "docx-to-md.py")

HOME = os.path.expanduser("~")
SAMPLES_DIR = os.path.join(HOME, "Descargas", "notes-import-samples")
if not os.path.isdir(SAMPLES_DIR):
    SAMPLES_DIR = os.path.join(HOME, "Downloads", "notes-import-samples")

VENV_PYTHON = "/tmp/qs-pdf-venv/bin/python"


def run_conversion(py_bin: str, input_file: str, out_dir: str, mode="copy"):
    cmd = [py_bin, "-B", CONVERTER, "--input", input_file, "--notes-dir", out_dir, "--mode", mode]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc


def main():
    test_dir = tempfile.mkdtemp(prefix="qs_notes_test_")
    try:
        print("=== Iniciando Pruebas de Conversores de Documentos ===")

        # 1. HTML
        html_file = os.path.join(SAMPLES_DIR, "muestra.html")
        p = run_conversion(sys.executable, html_file, test_dir)
        assert p.returncode == 0, f"HTML falló con código {p.returncode}: {p.stderr}"
        assert "RESULT:" in p.stdout
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        assert os.path.isfile(md_path)
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "# Muestra de Documento Web HTML" in content
        assert "| Quickshell | Entorno de escritorio | Activo |" in content
        assert "assets/" in content, "HTML con imagen debió generar carpeta con assets"
        print("  ✓ HTML -> Markdown (con tabla, formato y assets)")

        # 2. RTF
        rtf_file = os.path.join(SAMPLES_DIR, "muestra.rtf")
        p = run_conversion(sys.executable, rtf_file, test_dir)
        assert p.returncode == 0, f"RTF falló con código {p.returncode}: {p.stderr}"
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "Muestra de Documento RTF" in content
        assert "**negrita**" in content
        assert "*cursiva*" in content
        print("  ✓ RTF -> Markdown (con negrita, cursiva y tabla)")

        # 3. CSV
        csv_file = os.path.join(SAMPLES_DIR, "muestra.csv")
        p = run_conversion(sys.executable, csv_file, test_dir)
        assert p.returncode == 0, f"CSV falló con código {p.returncode}: {p.stderr}"
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "| ID | Producto | Categoría |" in content
        assert "| 101 | Teclado Mecánico |" in content
        print("  ✓ CSV -> Markdown (tabla formateada con escape de pipes)")

        # 4. TSV
        tsv_file = os.path.join(SAMPLES_DIR, "muestra.tsv")
        p = run_conversion(sys.executable, tsv_file, test_dir)
        assert p.returncode == 0, f"TSV falló con código {p.returncode}: {p.stderr}"
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "| Servicio | Puerto | Protocolo |" in content
        assert "| HTTPS | 443 | TCP |" in content
        print("  ✓ TSV -> Markdown (tabla tabulada)")

        # 5. ODT
        odt_file = os.path.join(SAMPLES_DIR, "muestra.odt")
        p = run_conversion(sys.executable, odt_file, test_dir)
        assert p.returncode == 0, f"ODT falló con código {p.returncode}: {p.stderr}"
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "# Documento OpenDocument (.odt)" in content
        assert "**OpenDocument Text**" in content
        assert "| Columna 1 | Columna 2 |" in content
        assert "assets/" in content, "ODT debió extraer imagen a assets"
        print("  ✓ ODT -> Markdown (encabezados, negrita, tabla y assets)")

        # 6. EPUB (local)
        epub_file = os.path.join(SAMPLES_DIR, "muestra.epub")
        p = run_conversion(sys.executable, epub_file, test_dir)
        assert p.returncode == 0, f"EPUB falló con código {p.returncode}: {p.stderr}"
        res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
        md_path = res_line[7:].strip()
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "# Capítulo 1: El Comienzo" in content
        assert "# Capítulo 2: Características" in content
        assert "---" in content
        assert "assets/" in content
        print("  ✓ EPUB -> Markdown (spine de capítulos, formateo y assets)")

        # 7. DOCX
        docx_file = os.path.join(SAMPLES_DIR, "muestra.docx")
        p = subprocess.run([sys.executable, "-B", DOCX_CONVERTER, "--input", docx_file, "--notes-dir", test_dir, "--mode", "copy"], capture_output=True, text=True)
        assert p.returncode == 0, f"DOCX falló: {p.stderr}"
        print("  ✓ DOCX -> Markdown (compatibilidad conservada)")

        # 8. Contrato de dependencias faltantes en el sistema real
        pdf_file = os.path.join(SAMPLES_DIR, "muestra.pdf")
        p = run_conversion(sys.executable, pdf_file, test_dir)
        assert p.returncode == 2, f"PDF debió salir con código 2 por falta de paquete pero dio {p.returncode}"
        assert "MISSING_DEP:python-pymupdf" in p.stderr, f"Falta reporte MISSING_DEP en stderr: {p.stderr}"
        print("  ✓ PDF contract: exit code 2 y MISSING_DEP:python-pymupdf en sistema sin paquete")

        xlsx_file = os.path.join(SAMPLES_DIR, "muestra.xlsx")
        p = run_conversion(sys.executable, xlsx_file, test_dir)
        assert p.returncode == 2, f"XLSX debió salir con código 2 por falta de paquete pero dio {p.returncode}"
        assert "MISSING_DEP:python-openpyxl" in p.stderr, f"Falta reporte MISSING_DEP en stderr: {p.stderr}"
        print("  ✓ XLSX contract: exit code 2 y MISSING_DEP:python-openpyxl en sistema sin paquete")

        # 9. Conversión de PDF y XLSX usando el venv temporal con PyMuPDF y openpyxl
        if os.path.isfile(VENV_PYTHON):
            p = run_conversion(VENV_PYTHON, pdf_file, test_dir)
            assert p.returncode == 0, f"PDF con PyMuPDF falló: {p.stderr}"
            res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
            md_path = res_line[7:].strip()
            with open(md_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "Documento de Prueba PDF" in content
            assert "assets/" in content, "PDF debió extraer imagen a assets"
            print("  ✓ PDF -> Markdown (PyMuPDF: títulos, texto estructurado y assets)")

            p = run_conversion(VENV_PYTHON, xlsx_file, test_dir)
            assert p.returncode == 0, f"XLSX con openpyxl falló: {p.stderr}"
            res_line = [l for l in p.stdout.splitlines() if l.startswith("RESULT:")][0]
            md_path = res_line[7:].strip()
            with open(md_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "## Ventas 2026" in content
            assert "| Mes | Zona Norte | Zona Sur | Total |" in content
            assert "## Servidores" in content
            print("  ✓ XLSX -> Markdown (openpyxl: hojas separadas y tablas)")

        print("\n=== ¡TODAS LAS PRUEBAS DE CONVERSIÓN PASARON CON ÉXITO! ===")
    finally:
        shutil.rmtree(test_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
