#!/usr/bin/env python3
"""IPiOS icin Xtream teshis araci.

Ne yapar: verilen Xtream hesabiyla konusup IPiOS'un film/dizi oynatamama
nedenini SOMUT olarak gosterir. Tahmin yurutmez; sunucudan gelen gercek
yanitlara bakar.

Uc soruyu yanitlar:
  1. Kimlik calisiyor mu? (canli liste geliyordu, demek ki calisiyor)
  2. Film/dizi listeleri IPiOS'un bekledigi sekilde cozulebiliyor mu?
     (cast/genre dizi olarak mi geliyor, container_extension bos mu?)
  3. Bir film adresi HANGI uzantiyla gercekten oynuyor? Sunucuya tek tek
     denetip hangisinin 200 dondurdugunu soyler.

Kullanim:
    python3 xtream_teshis.py --url http://sunucu:8080 --user KULLANICI --pass SIFRE

Gizlilik: parola yalnizca HTTP isteginde kullanilir, hicbir yere yazilmaz.
Cikti ekrandadir; paylasmadan once isterseniz `--redact` ile sunucu/kullanici
isimleri maskelenir.

Bu betik **kimlik bilgisi içermez**; yalnızca komut satırından aldığı
değerlerle çalışır ve hiçbir dosyaya yazmaz. Bu yüzden depoda tutulabilir.
Sağlayıcı adresinizi veya parolanızı betiğin içine **yazmayın**.
"""

import argparse
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


def mask(text, enabled):
    if not enabled:
        return text
    return re.sub(r"https?://[^\s\"']+", "<sunucu>", str(text))


def build_url(base, action=None, extra=None, user=None, password=None):
    params = {}
    if user is not None:
        params["username"] = user
    if password is not None:
        params["password"] = password
    if action:
        params["action"] = action
    if extra:
        params.update(extra)
    return f"{base.rstrip('/')}/player_api.php?" + urllib.parse.urlencode(params)


def fetch(url, timeout=25):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "IPiOS/1.0 (teshis)"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:  # ag hatasi, zaman asimi, TLS...
        return None, str(e)


def head_status(url, timeout=12):
    """Adres oynatilabilir mi? Sunucuya yalnizca basliklari sorar."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, method="GET", headers={
        "User-Agent": "IPiOS/1.0 (teshis)",
        "Range": "bytes=0-2047",  # tum dosyayi indirmemek icin
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            ctype = r.headers.get("Content-Type", "?")
            return r.status, ctype
    except urllib.error.HTTPError as e:
        return e.code, "-"
    except Exception as e:
        return None, str(e)[:60]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="Xtream sunucu adresi")
    ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="password", required=True)
    ap.add_argument("--redact", action="store_true",
                    help="Ciktida sunucu adresini maskele")
    ap.add_argument("--sample", type=int, default=3,
                    help="Kac film uzerinde adres denemesi yapilsin")
    args = ap.parse_args()

    R = args.redact
    problems = []   # IPiOS'un su anki surumunu GERCEKTEN engelleyen seyler
    notes = []      # sunucudaki tuhafliklar; IPiOS bunlari tolere ediyor

    def out(line=""):
        print(mask(line, R))

    out("=" * 66)
    out("IPiOS XTREAM TESHIS RAPORU")
    out("=" * 66)

    # --- 1. Kimlik ---------------------------------------------------------
    out("\n[1] KIMLIK VE SUNUCU")
    status, body = fetch(build_url(args.url, user=args.user, password=args.password))
    if status != 200:
        out(f"  HATA: sunucuya ulasilamadi (durum={status})")
        out(f"  ayrinti: {body[:200]}")
        return 2
    try:
        auth = json.loads(body)
    except json.JSONDecodeError:
        out("  HATA: yanit JSON degil. Sunucu adresi dogru mu?")
        out(f"  ilk 200 karakter: {body[:200]}")
        return 2

    info = auth.get("user_info") or {}
    srv = auth.get("server_info") or {}
    out(f"  durum        : {info.get('status')}")
    out(f"  bitis        : {info.get('exp_date')}")
    out(f"  max baglanti : {info.get('max_connections')}")
    out(f"  aktif baglanti: {info.get('active_cons')}")
    out(f"  sunucu yazilimi: {srv.get('server_software')}")
    out(f"  protokol     : {srv.get('server_protocol')} / port {srv.get('port')}")
    if auth.get("error"):
        out(f"  !! sunucu hata dondurdu: {auth['error']}")
        problems.append("kimlik hatasi")
    if (info.get("status") or "").lower() != "active":
        problems.append("hesap aktif degil")

    # --- 2. Liste uçlari ---------------------------------------------------
    out("\n[2] LISTELER VE ALAN TIPLERI")
    lists = {
        "canli (get_live_streams)": "get_live_streams",
        "film (get_vod_streams)": "get_vod_streams",
        "dizi (get_series)": "get_series",
    }
    vod_items = []
    for label, action in lists.items():
        st, bd = fetch(build_url(args.url, action=action, user=args.user, password=args.password))
        if st != 200:
            out(f"  {label:28} -> HTTP {st} (ULASILAMADI)")
            problems.append(f"{label} alinamadi")
            continue
        try:
            data = json.loads(bd)
        except json.JSONDecodeError:
            out(f"  {label:28} -> JSON COZULEMEDI")
            out(f"       ilk 200: {bd[:200]}")
            problems.append(f"{label} JSON cozulemedi (IPiOS'ta 'sunucu yaniti okunamadi' demek)")
            continue
        n = len(data) if isinstance(data, list) else 0
        out(f"  {label:28} -> {n} kayit")
        if n == 0:
            problems.append(f"{label} BOS donuyor")
        if action == "get_vod_streams":
            vod_items = data

    if not vod_items:
        out("\n  Film listesi bos oldugu icin adres denemesi yapilamiyor.")
        out("  Bu durumda sorun oynatma degil, sunucunun VOD icerigi.")
        return 1

    # --- 3. Alan tipi tutarliligi -----------------------------------------
    out("\n[3] FILM KAYITLARINDA ALAN TIPLERI (IPiOS'u bozan asil nokta)")
    def type_name(v):
        if v is None:
            return "yok"
        if isinstance(v, str):
            return "metin"
        if isinstance(v, bool):
            return "bool"
        if isinstance(v, (int, float)):
            return "sayi"
        if isinstance(v, list):
            return "LISTE(dizi)"
        if isinstance(v, dict):
            return "nesne"
        return type(v).__name__

    for field in ("cast", "director", "genre", "youtube_trailer", "plot", "container_extension"):
        counts = {}
        examples = {}
        for it in vod_items:
            tn = type_name(it.get(field))
            counts[tn] = counts.get(tn, 0) + 1
            if tn not in examples and it.get(field) not in (None, "", []):
                val = it.get(field)
                examples[tn] = (val[:60] if isinstance(val, str) else str(val)[:60])
        summary = ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
        out(f"  {field:22} {summary}")
        if counts.get("LISTE(dizi)"):
            out(f"       ornek: {examples.get('LISTE(dizi)')}")
            notes.append(f"'{field}' DIZI olarak geliyor (IPiOS artik tolere ediyor)")

    # container_extension dagilimi
    out("\n[4] BILDIRILEN KONTEYNER UZANTILARI")
    exts = {}
    empty = 0
    for it in vod_items:
        e = it.get("container_extension")
        if e is None or (isinstance(e, str) and not e.strip()):
            empty += 1
        else:
            exts[str(e).strip().lower()] = exts.get(str(e).strip().lower(), 0) + 1
    for e, c in sorted(exts.items(), key=lambda kv: -kv[1]):
        out(f"  {e:12} {c}")
    if empty:
        out(f"  (bos/yok)    {empty}   <- eski surumde bu adresler .m3u8 olurdu")
        notes.append(f"{empty} filmde container_extension BOS (IPiOS artik mp4'e ceviriyor)")
    unplayable = [e for e in exts if e in ("mkv", "avi", "webm", "flv", "wmv")]
    if unplayable:
        out(f"  AVPlayer'in cozemedigi konteynerler: {', '.join(unplayable)}")
        notes.append("bazi filmler cozulemeyen konteynerde (mkv/avi/...) "
                     "-> IPiOS mp4 yedegine duser")

    # --- 5. GERCEK ADRES DENEMESI -----------------------------------------
    out("\n[5] GERCEK ADRES DENEMESI (asil kanit)")
    out("  Ayni filmin adresi farkli uzantilarla denenir; hangisi 200 donerse")
    out("  oynatilabilir olan odur.")
    base = args.url.rstrip("/")
    cand_exts = ["m3u8", "mp4", "mkv", "avi", "ts"]
    for it in vod_items[: args.sample]:
        sid = it.get("stream_id") or it.get("id")
        if sid is None:
            continue
        name = (it.get("name") or "?")[:40]
        declared = it.get("container_extension")
        out(f"\n  --- {name}  (id={sid}, bildirilen={declared}) ---")
        working = []
        for ext in cand_exts:
            u = f"{base}/movie/{args.user}/{args.password}/{sid}.{ext}"
            st, ctype = head_status(u)
            mark = "OK " if st == 200 else "   "
            out(f"    {mark}{ext:6} -> {st}  {ctype}")
            if st == 200:
                working.append(ext)
        if working:
            out(f"    => CALISAN UZANTILAR: {', '.join(working)}")
            if declared and str(declared).lower() not in [w.lower() for w in working]:
                notes.append(f"film id={sid}: sunucu '{declared}' bildiriyor "
                             f"ama calisan '{working[0]}' -> IPiOS yedekle bulur")
            if str(declared).lower() not in [w.lower() for w in working] \
                    and "mp4" not in [w.lower() for w in working]:
                problems.append(f"film id={sid}: calisan uzanti mp4 DEGIL "
                                f"({', '.join(working)}) -> IPiOS yedegi yetmez")
        else:
            out("    => Hicbiri 200 donmedi. Bu icerik bu hesapla oynatilamiyor.")
            problems.append(f"film id={sid} icin hicbir uzanti calismadi "
                            f"-> saglayici bu icerigi sunmuyor")

    # --- 6. Dizi ornegi ----------------------------------------------------
    out("\n[6] DIZI BOLUM ADRESI DENEMESI")
    st, bd = fetch(build_url(args.url, action="get_series", user=args.user, password=args.password))
    if st == 200:
        try:
            series = json.loads(bd)
        except json.JSONDecodeError:
            series = []
        if series:
            sid = series[0].get("series_id")
            out(f"  ornek dizi: {(series[0].get('name') or '?')[:40]} (id={sid})")
            st2, bd2 = fetch(build_url(
                args.url, action="get_series_info",
                extra={"series_id": str(sid)},
                user=args.user, password=args.password))
            if st2 == 200:
                try:
                    detail = json.loads(bd2)
                except json.JSONDecodeError:
                    detail = {}
                eps = detail.get("episodes") or {}
                first = None
                for k in sorted(eps.keys(), key=lambda x: int(x) if x.isdigit() else 0):
                    if eps[k]:
                        first = eps[k][0]
                        break
                if first:
                    eid = first.get("id")
                    eext = first.get("container_extension")
                    out(f"  ilk bolum: id={eid}, bildirilen={eext}")
                    working = []
                    for ext in cand_exts:
                        u = f"{base}/series/{args.user}/{args.password}/{eid}.{ext}"
                        s3, ct = head_status(u)
                        out(f"    {'OK ' if s3 == 200 else '   '}{ext:6} -> {s3}  {ct}")
                        if s3 == 200:
                            working.append(ext)
                    if working:
                        out(f"    => CALISAN UZANTILAR: {', '.join(working)}")
                    else:
                        out("    => Hicbir uzanti 200 donmedi. Bolum oynatilamiyor.")
                        problems.append(f"dizi bolumu id={eid} hicbir uzantiyla calismadi")
                else:
                    out("  !! Bu dizinin bolum listesi bos.")
                    problems.append("dizi bolumleri bos donuyor")
    else:
        out(f"  dizi listesi alinamadi (HTTP {st})")

    # --- Ozet --------------------------------------------------------------
    out("\n" + "=" * 66)
    out("OZET")
    out("=" * 66)

    def dedupe(items):
        seen = []
        for x in items:
            if x not in seen:
                seen.append(x)
        return seen

    problems = dedupe(problems)
    notes = dedupe(notes)

    if problems:
        out("  GERCEK ENGEL(LER) — bunlar oynatmayi durdurur:")
        for i, p in enumerate(problems, 1):
            out(f"    {i}. {p}")
    else:
        out("  GERCEK ENGEL YOK — sunucu tarafinda oynatmayi durduran bir sey")
        out("  gorunmuyor. Adresler 200 donuyor, yani saglayici icerigi veriyor.")

    if notes:
        out("")
        out("  BILGI (IPiOS bunlari zaten tolere ediyor, endiselenmeyin):")
        for i, n in enumerate(notes, 1):
            out(f"    {i}. {n}")

    out("")
    if problems:
        out("  -> Sorun saglayicida ya da onun bildirdigi adreslerde.")
        out("     Bu raporu paylasin, IPiOS'ta ilgili kurali duzeltelim.")
    else:
        out("  -> Sunucu saglam. Oynatma hala calismiyorsa sorun IPiOS")
        out("     tarafindadir. Bu raporu paylasin.")
    out("")
    out("  NOT: Bu betik parolayi hicbir yere YAZMAZ. Yine de ciktiyi")
    out("  paylasirken sunucu adresini ve kullanici adini gizlemek icin")
    out("  --redact kullanin.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
