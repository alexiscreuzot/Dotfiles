#!/usr/bin/env python3
"""Fill the Word invoice template and export a matching Letter PDF."""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
import zipfile
from datetime import date
from pathlib import Path

STEM = "[invoice] Alexis Creuzot Consulting"
NAME_RE = re.compile(rf"^(\d{{4}})-(\d{{3}}) {re.escape(STEM)}\.(docx|pdf)$")
WEEK_ROW_RE = re.compile(
    r"<w:tr\b(?:(?!</w:tr>).)*Week#\d+(?:(?!</w:tr>).)*</w:tr>",
    re.S,
)
T_RE = re.compile(r"(<w:t[^>]*>)([^<]*)(</w:t>)")


def next_number(output_dir: Path, year: int) -> tuple[int, int]:
    seq = 0
    for p in output_dir.iterdir():
        m = NAME_RE.match(p.name)
        if m and int(m.group(1)) == year:
            seq = max(seq, int(m.group(2)))
    return year, seq + 1


def file_stem(year: int, seq: int) -> str:
    return f"{year}-{seq:03d} {STEM}"


def notes_ooo(ooo: list[dict]) -> str:
    if not ooo:
        return ""
    parts = []
    for row in ooo:
        d = date.fromisoformat(row["date"])
        parts.append(f"{d.strftime('%B')} {d.day}")
    return "OOO " + ", ".join(parts)


def _set_run(xml: str, old: str, new: str, count: int = 1) -> str:
    return xml.replace(f">{old}<", f">{new}<", count)


def _fresh_para_ids(xml: str, seed: int) -> str:
    n = {"i": seed}

    def repl(m):
        n["i"] += 1
        return f'{m.group(1)}{n["i"]:08X}{m.group(3)}'

    return re.sub(r'(paraId=")([0-9A-Fa-f]+)(")', repl, xml)


def _row_for_line(template_row: str, desc: str, price: str, qty: str, amount: str, seed: int) -> str:
    texts = [m.group(2) for m in T_RE.finditer(template_row)]
    old_desc = next(t for t in texts if t.startswith("Week#"))
    old_price = next(t for t in texts if t.startswith("$") and t.count(",") == 0)
    old_qty = next(t for t in texts if t.isdigit())
    old_amount = next(t for t in texts if t.startswith("$") and t != old_price)
    row = template_row
    row = _set_run(row, old_desc, desc)
    row = _set_run(row, old_price, price)
    row = _set_run(row, old_qty, qty)
    row = _set_run(row, old_amount, amount)
    return _fresh_para_ids(row, seed)


def fill_docx(
    template: Path,
    dest: Path,
    invoice_no: str,
    issue_date: date,
    lines: list[tuple[str, str, int, str]],
    total: str,
    ooo_note: str,
) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        with zipfile.ZipFile(template) as zf:
            zf.extractall(tmp_path)

        header_path = tmp_path / "word" / "header1.xml"
        header = header_path.read_text(encoding="utf-8")
        header = re.sub(r"Invoice #\d{4}-\d{3}", f"Invoice #{invoice_no}", header, count=1)
        header2 = re.sub(
            r"(ISSUE DATE : </w:t></w:r><w:r[^>]*>[\s\S]*?<w:t[^>]*>)\d{4}-\d{2}-\d{2}",
            rf"\g<1>{issue_date.isoformat()}",
            header,
            count=1,
        )
        if header2 == header:
            header = re.sub(r">\d{4}-\d{2}-\d{2}<", f">{issue_date.isoformat()}<", header, count=1)
        else:
            header = header2
        header_path.write_text(header, encoding="utf-8")

        body_path = tmp_path / "word" / "document.xml"
        body = body_path.read_text(encoding="utf-8")
        rows = list(WEEK_ROW_RE.finditer(body))
        if not rows:
            raise SystemExit("Invoice template has no Week# table rows.")
        new_rows = []
        for i, (desc, price, hours, amount) in enumerate(lines):
            new_rows.append(
                _row_for_line(rows[0].group(0), desc, price, str(hours), amount, 0xA000 + i * 16)
            )
        body = body[: rows[0].start()] + "".join(new_rows) + body[rows[-1].end() :]

        if re.search(r">OOO [^<]*<", body):
            body = re.sub(r">OOO [^<]*<", f">{ooo_note}<" if ooo_note else "><", body, count=1)

        totals = re.findall(r">(\$\d{1,3}(?:,\d{3})*\.\d{2})<", body)
        if totals:
            body = _set_run(body, totals[-1], total, count=1)
        body_path.write_text(body, encoding="utf-8")

        dest.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in tmp_path.rglob("*"):
                if p.is_file():
                    zf.write(p, p.relative_to(tmp_path).as_posix())


def export_pdf(pdf: Path, payload: dict) -> None:
    pdf.parent.mkdir(parents=True, exist_ok=True)
    venv_py = Path(__file__).resolve().parent / ".venv" / "bin" / "python"
    script = Path(__file__).resolve().parent / "pdf_invoice.py"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(payload, fh)
        json_path = fh.name
    try:
        r = subprocess.run(
            [str(venv_py), str(script), str(pdf), "--json", json_path],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0 or not pdf.exists():
            raise SystemExit("PDF export failed.\n" + (r.stderr or r.stdout or ""))
    finally:
        Path(json_path).unlink(missing_ok=True)

