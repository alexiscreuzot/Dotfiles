#!/usr/bin/env python3
"""Draw the Forum invoice PDF to match the Word/PDF styling (Letter, one page)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from reportlab.lib.colors import HexColor, white, black
from reportlab.lib.pagesizes import letter
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

BLUE = HexColor("#4a86e8")
GRAY = HexColor("#f3f3f3")
LINE = HexColor("#e6e6e6")
FONT_DIR = Path("/System/Library/Fonts/Supplemental")


def twip(n: float) -> float:
    return n / 20.0


def _font(name: str, filename: str) -> None:
    path = FONT_DIR / filename
    if path.exists():
        pdfmetrics.registerFont(TTFont(name, str(path)))


def _register() -> dict[str, str]:
    _font("InvArial", "Arial.ttf")
    _font("InvArial-Bold", "Arial Bold.ttf")
    _font("InvCourier", "Courier New.ttf")
    _font("InvCourier-Bold", "Courier New Bold.ttf")
    registered = set(pdfmetrics.getRegisteredFontNames())
    return {
        "sans": "InvArial" if "InvArial" in registered else "Helvetica",
        "sansBold": "InvArial-Bold" if "InvArial-Bold" in registered else "Helvetica-Bold",
        "mono": "InvCourier" if "InvCourier" in registered else "Courier",
        "monoBold": "InvCourier-Bold" if "InvCourier-Bold" in registered else "Courier-Bold",
    }


def draw(path: Path, data: dict) -> None:
    fonts = _register()
    sans, sans_b = fonts["sans"], fonts["sansBold"]
    mono, mono_b = fonts["mono"], fonts["monoBold"]

    c = canvas.Canvas(str(path), pagesize=letter)
    page_w, page_h = letter
    invoice_no = data["invoice_no"]
    issue = data["issue_date"]
    lines = data["lines"]
    total = data["total"]
    ooo_note = data.get("ooo_note") or ""

    gutter = twip(450)
    vendor_w = twip(5775)
    bill_w = twip(6000)
    header_h = twip(5340)
    issue_h = twip(795)
    bill_x = gutter + vendor_w

    # Tall BILL TO panel — full header-row height, top-right.
    c.setFillColor(BLUE)
    c.rect(bill_x, page_h - header_h, bill_w, header_h, fill=1, stroke=0)

    # Vendor block, vertically centered in the left header cell.
    vendor_lines = [
        (sans_b, 24, black, f"Invoice #{invoice_no}", 28),
        (sans_b, 9, black, "VENDOR", 14),
        (sans_b, 12, BLUE, "Alexis CREUZOT", 15),
        (sans_b, 10, black, "Sendero del Misterio #83, Int.33", 13),
        (sans_b, 10, black, "Milenio 3", 13),
        (sans_b, 10, black, "76060 Querétaro, Qro, MÉXICO", 13),
        (sans, 10, black, "+52 999 424 2862", 22),
        (sans, 10, black, "RFC : CEAL8709273S4", 13),
        (sans, 10, black, "Régimen Fiscal : RESICO", 13),
    ]
    vendor_h = sum(gap for *_rest, gap in vendor_lines)
    y = page_h - (header_h - vendor_h) / 2 - 18
    vx = gutter + 8
    for face, size, color, text, gap in vendor_lines:
        c.setFillColor(color)
        c.setFont(face, size)
        c.drawString(vx, y, text)
        y -= gap

    # BILL TO text inside the blue panel (left indent ~36pt / 720 twips).
    bx = bill_x + twip(720)
    bill_lines = [
        (sans_b, 9, "BILL TO", 16),
        (sans_b, 12, "Sorenson Communication", 16),
        (sans_b, 10, "4192 S, Riverboat Rd", 13),
        (sans_b, 10, "Taylorsville, UT 84123, UNITED STATES", 13),
        (sans, 10, "+1 801-386-8500", 22),
        (sans, 10, "RFC : XEXX010101000", 13),
        (sans, 10, "CFDI : P01", 13),
    ]
    bill_h = sum(gap for *_r, gap in bill_lines)
    y = page_h - (header_h - bill_h) / 2 - 10
    c.setFillColor(white)
    for face, size, text, gap in bill_lines:
        c.setFont(face, size)
        c.drawString(bx, y, text)
        y -= gap

    # Issue date row under the header.
    y = page_h - header_h - issue_h / 2 - 3
    c.setFillColor(black)
    c.setFont(sans_b, 9)
    c.drawString(vx, y, "ISSUE DATE : ")
    label_w = c.stringWidth("ISSUE DATE : ", sans_b, 9)
    c.setFont(sans, 10)
    c.drawString(vx + label_w, y, issue)
    c.setFont(sans_b, 9)
    c.drawRightString(page_w - gutter, y, "DUE ON RECEPTION")

    # Line-item columns (twips from the Word table).
    x0 = twip(240)
    desc_x = x0
    price_r = twip(240 + 8475 + 930)
    qty_r = twip(240 + 8475 + 930 + 780)
    amt_r = twip(240 + 8475 + 930 + 780 + 1515)
    bar_right = page_w - twip(240)

    items_top = page_h - header_h - issue_h - 8
    row_h = twip(555)
    n = max(1, len(lines))

    # Footer is pinned to the bottom so the page always stays one sheet.
    footer_bottom = 28
    bank_h = 108
    notes_h = 58
    footer_top = footer_bottom + bank_h + notes_h
    items_budget = items_top - footer_top - 24
    need = (n + 1) * row_h
    if need > items_budget:
        row_h = max(16, items_budget / (n + 1))

    # Gray header bar.
    header_y = items_top - row_h
    c.setFillColor(GRAY)
    c.rect(x0, header_y, bar_right - x0, row_h, fill=1, stroke=0)
    c.setFillColor(black)
    c.setFont(sans_b, 10)
    text_y = header_y + row_h / 2 - 4
    c.drawString(desc_x + 6, text_y, "DESCRIPTION")
    c.drawRightString(price_r - 4, text_y, "PRICE")
    c.drawRightString(qty_r - 4, text_y, "QTY")
    c.drawRightString(amt_r - 4, text_y, "LINE TOTAL")

    y = header_y
    for desc, price, hours, amount in lines:
        y -= row_h
        text_y = y + row_h / 2 - 4
        c.setFillColor(black)
        c.setFont(mono, 10)
        c.drawString(desc_x + 6, text_y, desc)
        c.drawRightString(price_r - 4, text_y, price)
        c.drawRightString(qty_r - 4, text_y, str(hours))
        c.setFont(mono_b, 10)
        c.drawRightString(amt_r - 4, text_y, amount)

    # NOTES + total, then bank details — bottom of the page.
    notes_y = footer_bottom + bank_h + notes_h - 14
    c.setFillColor(black)
    c.setFont(sans_b, 10)
    c.drawString(desc_x + 6, notes_y, "NOTES")
    c.drawRightString(amt_r - 4, notes_y, "TOTAL AMOUNT DUE")
    ny = notes_y - 16
    c.setFont(sans, 9)
    if ooo_note:
        c.drawString(desc_x + 6, ny, ooo_note)
        ny -= 13
    c.drawString(desc_x + 6, ny, "IVA no aplicable")
    c.setFillColor(BLUE)
    c.setFont(sans_b, 19)
    c.drawRightString(amt_r - 4, notes_y - 22, total)

    by = footer_bottom + bank_h - 18
    c.setFillColor(black)
    c.setFont(sans_b, 10)
    c.drawString(desc_x + 6, by, "BANK DETAILS")
    by -= 16
    bank = data.get("bank") or {}
    rows = (
        ("BENEFICIARY", bank.get("beneficiary") or ""),
        ("IBAN", bank.get("iban") or ""),
        ("BIC", bank.get("bic") or ""),
        ("BANK", bank.get("name") or ""),
    )
    label_x = desc_x + 6
    value_x = label_x + 92
    for label, value in rows:
        c.setFont(sans_b, 10)
        c.drawString(label_x, by, label)
        c.setFont(sans, 10)
        c.drawString(value_x, by, value)
        by -= 13
    c.setFont(sans, 10)
    for line in bank.get("address") or []:
        c.drawString(value_x, by, line)
        by -= 12

    c.showPage()
    c.save()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf")
    parser.add_argument("--json", required=True)
    args = parser.parse_args()
    data = json.loads(Path(args.json).read_text())
    out = Path(args.pdf)
    out.parent.mkdir(parents=True, exist_ok=True)
    draw(out, data)
    print(f"PDF {out}", flush=True)


if __name__ == "__main__":
    main()
