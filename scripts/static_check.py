#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""IPiOS statik tutarlılık denetimi.

Bu betik Swift derleyicisi olmadan da çalışır ve CI'da hem hızlı geri bildirim
için (Ubuntu job'ı) hem de yerelde kullanılabilir. Denetledikleri:

  Yerelleştirme
    1. tr/en anahtar kümeleri eşit mi?
    2. Aynı dosyada yinelenen anahtar var mı?
    3. Biçim yer tutucuları (%d / %@ / %f) iki dilde aynı mı?
       (uyuşmazlık derlemede değil ÇALIŞMA ANINDA çöker)
    4. Boş değer var mı?
    5. Kodda kullanılan ama tanımsız anahtar var mı?

  Kaynak yapısı
    6. Süslü parantez dengesi
    7. Kapanmamış çok satırlı dizge
    8. Eksik `import`

  Varlıklar
    9. Info.plist geçerli mi, `InfoPlist.strings` anahtarlarıyla hizalı mı?
   10. docs/MIMARI.md klasör ağacı gerçek dosya listesiyle eşleşiyor mu?

  Proje tanımı
   11. project.yml içinde `projectFormat: xcode15_3` sabit mi?
       (sabit değilse XcodeGen objectVersion 77 üretir ve Xcode 15.x
       projeyi açamaz — bkz. README, "GitHub üzerinden derleme")

Çıkış kodu 0 ise sorun yok, 1 ise en az bir HATA var. Uyarılar (ör. kullanılmayan
anahtar) çıkış kodunu değiştirmez.
"""

from __future__ import annotations

import os
import plistlib
import re
import sys
from collections import Counter
from pathlib import Path

KOK = Path(__file__).resolve().parent.parent

TR = KOK / "IPiOS/Resources/tr.lproj/Localizable.strings"
EN = KOK / "IPiOS/Resources/en.lproj/Localizable.strings"
INFO_PLIST = KOK / "IPiOS/Resources/Info.plist"

ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ #0]*[\d*]*(?:\.[\d*]+)?[@dfs]")

hatalar: list[str] = []
uyarilar: list[str] = []
cikti: list[str] = []


def yaz(s: str = "") -> None:
    cikti.append(s)


def hata(s: str) -> None:
    hatalar.append(s)
    yaz(f"  HATA  {s}")


def uyari(s: str) -> None:
    uyarilar.append(s)
    yaz(f"  uyarı {s}")


def strip_comments(text: str) -> str:
    """`/* ... */` yorumlarını satır numarasını koruyarak boşluğa çevirir."""
    parcalar: list[str] = []
    i = 0
    while i < len(text):
        if text.startswith("/*", i):
            son = text.find("*/", i + 2)
            son = len(text) if son == -1 else son + 2
            parcalar.append("".join("\n" if c == "\n" else " " for c in text[i:son]))
            i = son
        else:
            parcalar.append(text[i])
            i += 1
    return "".join(parcalar)


def strip_yaml_comments(text: str) -> str:
    """YAML `#` yorumlarını satır numarasını koruyarak boşluğa çevirir.

    Çift tırnak içindeki `#` (ör. bir dize değerinin parçası) korunur.
    Amaç: açıklama satırında geçen bir anahtar adının, gerçek ayar sanılıp
    yanlış pozitif üretmesini engellemek.
    """
    satirlar: list[str] = []
    for satir in text.split("\n"):
        tirnak = False
        kesim = len(satir)
        for i, c in enumerate(satir):
            if c == '"':
                tirnak = not tirnak
            elif c == "#" and not tirnak:
                kesim = i
                break
        satirlar.append(satir[:kesim])
    return "\n".join(satirlar)


def strings_yukle(path: Path) -> list[tuple[str, str, int]]:
    """(anahtar, değer, satır) üçlülerini döndürür."""
    ham = path.read_text(encoding="utf-8")
    temiz = strip_comments(ham)
    return [
        (m.group(1), m.group(2), temiz.count("\n", 0, m.start()) + 1)
        for m in ENTRY.finditer(temiz)
    ]


#: Yapı denetiminin kapsadığı hedefler. Test hedefi de aynı kurallara tabidir.
HEDEFLER = ("IPiOS", "IPiosTests")


def swift_dosyalari(alt: str = "IPiOS") -> list[Path]:
    return sorted((KOK / alt).rglob("*.swift"))


def tum_swift_dosyalari() -> list[Path]:
    """Her iki hedefteki tüm Swift dosyaları."""
    return [p for hedef in HEDEFLER for p in swift_dosyalari(hedef)]


# --------------------------------------------------------------------------
# 1-5: Yerelleştirme
# --------------------------------------------------------------------------
def yerelleştirme() -> tuple[dict[str, str], dict[str, str]]:
    yaz("=== YERELLEŞTİRME ===")

    tr = strings_yukle(TR)
    en = strings_yukle(EN)
    tr_map = {k: v for k, v, _ in tr}
    en_map = {k: v for k, v, _ in en}

    # 1. yinelenen
    for dil, kayitlar in (("tr", tr), ("en", en)):
        tekrar = sorted(k for k, c in Counter(k for k, _, _ in kayitlar).items() if c > 1)
        if tekrar:
            hata(f"{dil}: yinelenen anahtar: {', '.join(tekrar)}")

    # 2. sayı
    yaz(f"  anahtar sayısı: tr={len(tr_map)} en={len(en_map)}")
    if len(tr_map) != len(en_map):
        hata("tr ve en anahtar sayısı farklı")

    # 3. eksik / fazla
    yalniz_tr = sorted(set(tr_map) - set(en_map))
    yalniz_en = sorted(set(en_map) - set(tr_map))
    for ad, liste in (("yalnız tr", yalniz_tr), ("yalnız en", yalniz_en)):
        if liste:
            hata(f"{ad}: {', '.join(liste)}")

    # 4. yer tutucu uyuşmazlığı
    for anahtar in sorted(set(tr_map) & set(en_map)):
        a = Counter(PLACEHOLDER.findall(tr_map[anahtar]))
        b = Counter(PLACEHOLDER.findall(en_map[anahtar]))
        if a != b:
            hata(
                f"yer tutucu uyuşmazlığı {anahtar}: "
                f"tr={dict(a)} en={dict(b)}"
            )

    # 5. boş değer
    for ad, m in (("tr", tr_map), ("en", en_map)):
        bos = sorted(k for k, v in m.items() if not v.strip())
        if bos:
            hata(f"{ad}: boş değerli anahtar: {', '.join(bos)}")

    # 6. kodda kullanılan ama tanımsız
    kullanilan: dict[str, str] = {}
    cagri = re.compile(r'L\.(?:t|f)\(\s*"([^"]+)"')
    ucgen = re.compile(r'L\.(?:t|f)\(\s*[^()]*?\?\s*"([^"]+)"\s*:\s*"([^"]+)"')
    for path in swift_dosyalari():
        src = path.read_text(encoding="utf-8")
        rel = path.relative_to(KOK).as_posix()
        for m in ucgen.finditer(src):
            for g in (m.group(1), m.group(2)):
                kullanilan.setdefault(g, f"{rel}:{src.count(chr(10), 0, m.start()) + 1}")
        for m in cagri.finditer(src):
            kullanilan.setdefault(m.group(1), f"{rel}:{src.count(chr(10), 0, m.start()) + 1}")

    tanimsiz = sorted(k for k in kullanilan if k not in tr_map or k not in en_map)
    if tanimsiz:
        hata(f"tanımsız anahtar: {', '.join(tanimsiz)}")
        for k in tanimsiz[:10]:
            yaz(f"         {k}  <- {kullanilan[k]}")

    olu = sorted(set(tr_map) - set(kullanilan))
    if olu:
        uyari(f"kullanılmayan anahtar ({len(olu)}): {', '.join(olu[:10])}")

    return tr_map, en_map


# --------------------------------------------------------------------------
# 7-8: Kaynak yapısı
# --------------------------------------------------------------------------
def kaynak_yapisi() -> None:
    yaz()
    yaz("=== KAYNAK YAPISI ===")
    dosyalar = tum_swift_dosyalari()
    yaz(f"  taranan dosya: {len(dosyalar)} ({' + '.join(HEDEFLER)})")

    for path in dosyalar:
        src = path.read_text(encoding="utf-8")
        rel = path.relative_to(KOK).as_posix()

        if not re.search(r"^\s*import\s+\w+", src, re.M):
            hata(f"{rel}: hiç import yok")

        if src.count("{") != src.count("}"):
            hata(f"{rel}: süslü parantez dengesiz ({src.count('{')}/{src.count('}')})")

        # Çok satırlı dizge """ ... """ çift sayıda olmalı.
        if src.count('"""') % 2 != 0:
            hata(f"{rel}: kapanmamış çok satırlı dizge")


# --------------------------------------------------------------------------
# 9: Info.plist
# --------------------------------------------------------------------------
def info_plist() -> None:
    yaz()
    yaz("=== INFO.PLIST ===")
    try:
        veri = plistlib.loads(INFO_PLIST.read_bytes())
    except Exception as exc:  # noqa: BLE001
        hata(f"Info.plist okunamadı: {exc}")
        return

    yaz(f"  geçerli, {len(veri)} anahtar")
    if not veri.get("CFBundleIdentifier"):
        hata("CFBundleIdentifier yok")

    # InfoPlist.strings anahtarları Info.plist'te karşılık bulmalı.
    for dil in ("tr", "en"):
        p = KOK / f"IPiOS/Resources/{dil}.lproj/InfoPlist.strings"
        if not p.exists():
            hata(f"{dil}.lproj/InfoPlist.strings yok")
            continue
        for anahtar, _, _ in strings_yukle(p):
            if anahtar not in veri:
                hata(f"{dil}/InfoPlist.strings: '{anahtar}' Info.plist'te yok")


# --------------------------------------------------------------------------
# 10: Doküman ağacı
# --------------------------------------------------------------------------
def dokuman_agaci() -> None:
    yaz()
    yaz("=== MIMARI.md KLASÖR AĞACI ===")
    mimari = (KOK / "docs/MIMARI.md").read_text(encoding="utf-8")
    blok = re.search(r"```\nipios/\n(.*?)```", mimari, re.S)
    if not blok:
        uyari("MIMARI.md içinde klasör ağacı bloğu bulunamadı")
        return

    iddia = set(re.findall(r"([A-Za-z0-9_]+\.swift)", blok.group(1)))
    gercek = {p.name for p in swift_dosyalari()}
    gercek |= {p.name for p in swift_dosyalari("IPiosTests")}

    yaz(f"  ağaçta: {len(iddia)} | gerçekte: {len(gercek)}")
    eksik = sorted(iddia - gercek)
    fazla = sorted(gercek - iddia)
    if eksik:
        hata(f"ağaçta var, gerçekte yok: {', '.join(eksik)}")
    if fazla:
        hata(f"gerçekte var, ağaçta yok: {', '.join(fazla)}")


# --------------------------------------------------------------------------
# 11: project.yml — proje biçimi sabitlemesi
# --------------------------------------------------------------------------
def proje_tanimi() -> None:
    yaz()
    yaz("=== PROJECT.YML ===")
    yol = KOK / "project.yml"
    if not yol.exists():
        hata("project.yml yok")
        return

    icerik = yol.read_text(encoding="utf-8")

    # Yorumları ayıkla: açıklama satırında geçen anahtar adı yanlış pozitif
    # üretmesin (bkz. .strings blok yorumu vakası).
    govde = strip_yaml_comments(strip_comments(icerik))

    if not re.search(r"^\s*projectFormat:\s*xcode15_3\s*$", govde, re.M):
        hata(
            "project.yml: 'projectFormat: xcode15_3' yok. XcodeGen varsayılanı "
            "xcode16_0 (objectVersion 77) üretir; macOS runner'daki Xcode 15.x "
            "bu projeyi açamaz."
        )
    else:
        yaz("  projectFormat: xcode15_3 (objectVersion 63)")

    # İş akışındaki doğrulama adımı bu sabitlemeye dayanır; ikisi birlikte
    # tutarlı olmalı.
    akis = KOK / ".github/workflows/ci.yml"
    if akis.exists() and "objectVersion = 63" not in akis.read_text(encoding="utf-8"):
        uyari("ci.yml içinde objectVersion denetimi bulunamadı")


def main() -> int:
    yerelleştirme()
    kaynak_yapisi()
    info_plist()
    dokuman_agaci()
    proje_tanimi()

    yaz()
    yaz("=== SONUÇ ===")
    if uyarilar:
        yaz(f"  {len(uyarilar)} uyarı")
    if hatalar:
        yaz(f"  {len(hatalar)} HATA")
    else:
        yaz("  hata yok")

    metin = "\n".join(cikti)
    print(metin)
    rapor = os.environ.get("CHECK_REPORT")
    if rapor:
        Path(rapor).write_text(metin + "\n", encoding="utf-8")

    return 1 if hatalar else 0


if __name__ == "__main__":
    sys.exit(main())
