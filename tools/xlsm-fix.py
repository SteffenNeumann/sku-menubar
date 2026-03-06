#!/usr/bin/env python3
"""
xlsm-fix.py — XLSM Korruptions-Bereinigung
============================================
Behebt alle bekannten Excel 16.106.3 / Tahoe Beta Korruptionen:
  - calcChain.xml entfernen
  - _xleta/_xlpm Names entfernen  
  - CF sqrefs mit :1048576 trimmen
  - FILTER CSE-Marker entfernen
  - table array="1" + xmlns:xlrd2 entfernen

Verwendung:
  python3 xlsm-fix.py datei.xlsm              # überschreibt Originaldatei
  python3 xlsm-fix.py datei.xlsm output.xlsm  # schreibt in neue Datei
  python3 xlsm-fix.py --check datei.xlsm      # nur prüfen, nicht ändern
"""
import zipfile
import re
import os
import sys
import shutil
from datetime import datetime


def fix_xlsm(src_path, dst_path=None, check_only=False):
    name = os.path.basename(src_path)
    size = round(os.path.getsize(src_path) / 1024)

    if not os.path.exists(src_path):
        print("FEHLER: Datei nicht gefunden: " + src_path)
        return False

    # Dateien aus ZIP einlesen
    files = {}
    try:
        with zipfile.ZipFile(src_path, "r") as z:
            orig_infos = {item.filename: item for item in z.infolist()}
            for fname in orig_infos:
                files[fname] = z.read(fname)
    except Exception as e:
        print("FEHLER beim Lesen: " + str(e))
        return False

    changes = []

    # ── FIX 1: calcChain.xml entfernen ──────────────────────────────────
    if "xl/calcChain.xml" in files:
        if not check_only:
            del files["xl/calcChain.xml"]
            ct = files["[Content_Types].xml"].decode("utf-8")
            ct = re.sub(r'\s*<Override[^>]*calcChain[^>]*/>', "", ct)
            files["[Content_Types].xml"] = ct.encode("utf-8")
            rels_key = "xl/_rels/workbook.xml.rels"
            if rels_key in files:
                rels = files[rels_key].decode("utf-8")
                rels = re.sub(r'\s*<Relationship[^>]*calcChain[^>]*/>', "", rels)
                files[rels_key] = rels.encode("utf-8")
        changes.append("calcChain entfernt")

    # ── FIX 2: _xleta/_xlpm definedNames entfernen ──────────────────────
    wb = files["xl/workbook.xml"].decode("utf-8")
    xleta_count = len(re.findall(r"_xleta|_xlpm", wb))
    if xleta_count > 0:
        if not check_only:
            wb_new = re.sub(
                r'\s*<definedName name="(?:_xleta|_xlpm)\.[^"]*"[^>]*>[^<]*</definedName>',
                "", wb
            )
            files["xl/workbook.xml"] = wb_new.encode("utf-8")
        changes.append(str(xleta_count) + "x _xleta/_xlpm entfernt")

    # ── FIX 3: CF sqrefs mit 1048576 bereinigen ─────────────────────────
    for fname in list(files.keys()):
        if fname.startswith("xl/worksheets/") and fname.endswith(".xml"):
            s = files[fname].decode("utf-8")
            if "1048576" in s:
                if not check_only:
                    s_new = re.sub(r'\s+\w+\d+:\w+1048576', "", s)
                    files[fname] = s_new.encode("utf-8")
                changes.append("CF:1048576 in " + fname.split("/")[-1])

    # ── FIX 4: FILTER CSE-Marker entfernen ──────────────────────────────
    s5_key = "xl/worksheets/sheet5.xml"
    if s5_key in files:
        s5 = files[s5_key].decode("utf-8")
        if 't="array" ref=' in s5 and "FILTER" in s5:
            if not check_only:
                s5_new = re.sub(
                    r'<f t="array" ref="[^"]+">((_xlfn\._xlws\.FILTER|_xlfn\.FILTER))',
                    r"<f>\1", s5
                )
                files[s5_key] = s5_new.encode("utf-8")
            changes.append("FILTER CSE-Marker entfernt")

    # ── FIX 5: table array="1" + xmlns:xlrd2 entfernen ──────────────────
    for fname in list(files.keys()):
        if fname.startswith("xl/tables/") and fname.endswith(".xml"):
            t = files[fname].decode("utf-8")
            has_array = 'array="1"' in t
            has_xmlns = "xmlns:xlrd2" in t
            if has_array or has_xmlns:
                if not check_only:
                    t_new = t.replace(' array="1"', "")
                    t_new = re.sub(r'\s+xmlns:xlrd2="[^"]*"', "", t_new)
                    files[fname] = t_new.encode("utf-8")
                changes.append("table fixes in " + fname.split("/")[-1])

    # ── Ergebnis ─────────────────────────────────────────────────────────
    if check_only:
        if changes:
            print(name + " (" + str(size) + "KB): " + str(len(changes)) + " Probleme gefunden")
            for c in changes:
                print("  - " + c)
            return False
        else:
            print(name + " (" + str(size) + "KB): SAUBER — keine Probleme")
            return True

    if not changes:
        print(name + ": bereits sauber — keine Änderungen nötig")
        return True

    # ── ZIP neu packen ────────────────────────────────────────────────────
    if dst_path is None:
        # Backup erstellen, Original überschreiben
        backup = src_path.replace(".xlsm", "_pre_fix_" + datetime.now().strftime("%H%M%S") + ".xlsm")
        shutil.copy2(src_path, backup)
        dst_path = src_path

    tmp_path = dst_path + ".tmp"
    with zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as dst_zip:
        for fname, data in files.items():
            if fname in orig_infos:
                orig = orig_infos[fname]
                info = zipfile.ZipInfo(fname)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.date_time = orig.date_time
                info.create_system = 0
                info.create_version = orig.create_version
                info.extract_version = orig.extract_version
                info.flag_bits = orig.flag_bits & ~0x0800
                info.external_attr = 0
                info.internal_attr = 0
                info.extra = b""
            else:
                info = zipfile.ZipInfo(fname)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 0
            dst_zip.writestr(info, data)

    os.replace(tmp_path, dst_path)

    # Quarantine entfernen
    os.system('xattr -cr "' + dst_path + '" 2>/dev/null')

    new_size = round(os.path.getsize(dst_path) / 1024)
    print(name + ": " + str(len(changes)) + " Fixes angewendet (" + str(size) + "→" + str(new_size) + " KB)")
    for c in changes:
        print("  ✓ " + c)
    return True


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    check_only = "--check" in args
    args = [a for a in args if not a.startswith("-")]

    if len(args) == 0:
        print("Verwendung: python3 xlsm-fix.py [--check] datei.xlsm [output.xlsm]")
        sys.exit(1)

    src = args[0]
    dst = args[1] if len(args) > 1 else None
    fix_xlsm(src, dst, check_only=check_only)
