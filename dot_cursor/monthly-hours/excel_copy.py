#!/usr/bin/env python3
"""Write an HTML + CSV table pair for pasting into Excel."""
from __future__ import annotations

import subprocess
from pathlib import Path


def write(stem: Path, rows: list[list[str]], hint: str, open_html: bool = False) -> Path:
    html_path = stem.parent / f"{stem.name}.html"
    csv_path = stem.parent / f"{stem.name}.csv"
    body = "\n".join(
        "<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>"
        for row in rows
    )
    html_path.write_text(
        '<!DOCTYPE html>\n<html><head><meta charset="utf-8"></head><body>\n'
        '<table border="1" cellpadding="6" cellspacing="0">\n'
        + body
        + f"\n</table>\n<p>{hint}</p>\n</body></html>\n"
    )
    # commas would split a cell, and amounts carry thousands separators
    csv_path.write_text(
        "\n".join(",".join(cell.replace(",", " ") for cell in row) for row in rows) + "\n"
    )
    if open_html:
        subprocess.Popen(
            ["open", str(html_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    print(f"EXCEL_COPY {html_path}", flush=True)
    return html_path
