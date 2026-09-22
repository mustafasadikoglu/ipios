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


# IPiOS'un gonderdigi User-Agent. `AVPlayerEngine.startItem` ile ayni olmali.
IPIOS_UA = "IPiOS/1.0 (iOS)"

# Karsilastirma icin yaygin bir oynatici adi. Bazi saglayicilar bilmedikleri
# UA'lari engeller; fark cikarsa sorun uygulamada degil sunucu tarafindadir.
VLC_UA = "VLC/3.0.20 LibVLC/3.0.20"


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
    """Adres oynatilabilir mi? Sunucuya yalnizca ilk birkac bayti sorar.

    Donen demet `probe` ile aynidir: (durum, icerik_turu, boyut, sinif, imza).
    """
    return probe(url, ua=IPIOS_UA, timeout=timeout)


def probe(url, ua, timeout=12):
    """Adresi verilen User-Agent ile dener.

    Iki farkli UA ile denenmesinin nedeni: bazi saglayicilar bilmedikleri
    uygulama adlarini engeller ve 403 doner. IPiOS kendi UA'sini gonderir
    ('IPiOS/1.0 (iOS)'); baska bir oynatici (VLC gibi) kendi adini gonderir
    ve gecer. Bu tam olarak 'baska uygulamada calisiyor, bunda calismiyor'
    tablosunu uretir. Bu yuzden her adres iki kez denenir.

    Donen demet: (durum, icerik_turu, boyut, sinif, imza).

    **Yalnizca durum koduna bakmak yetmez.** Xtream panelleri var olmayan bir
    icin adresine HTTP 200 dondurup govdeye sifir baytlik (ya da bir HTML hata
    sayfasi) koyar. Yalnizca `st == 200` kontrol edilirse o adres "calisiyor"
    sanilir ve teshis tam tersine doner: gercekte oynatilamayan bir adres
    "IPiOS bulamiyor" diye raporlanir. Bu yuzden govdenin ilk baytlari da
    okunur ve gercek veri gelip gelmedigi imzadan anlasilir.

    `sinif` degerleri: 'hls', 'mkv', 'mp4', 'ts', 'audio', 'html', 'bos',
    'bilinmeyen', 'hata'.
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, method="GET", headers={
        "User-Agent": ua,
        "Range": "bytes=0-4095",  # tum dosyayi indirmemek icin
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            ctype = r.headers.get("Content-Type", "?")
            body = r.read()
            return r.status, ctype, len(body), *classify_body(body, ctype)
    except urllib.error.HTTPError as e:
        return e.code, "-", 0, "hata", ""
    except Exception as e:
        return None, str(e)[:60], 0, "hata", ""


# Konteyner imzalari. Sira onemli: TS imzasi MP4'ten once denenmezse
# yanlis eslesme olabilir, ama TS'in senkron bayti (0x47) cok zayif bir
# imzadir ve yanlis pozitif uretir; bu yuzden yalnizca acik imzalar kullanilir.
def classify_body(body, ctype=""):
    """Govdenin ilk baytlarindan gercek icerigi siniflandirir."""
    if not body:
        return "bos", ""
    head = body[:16]
    if head[:4] == b"\x1a\x45\xdf\xa3":
        return "mkv", head[:4].hex()
    if b"ftyp" in body[:64]:
        return "mp4", head[:16].hex()
    low = body[:1024].lower()
    if b"<html" in low or b"<!doctype" in low or b"<?xml" in low:
        return "html", ""
    if b"#EXTM3U" in body[:2048]:
        return "hls", ""
    # MPEG-TS: 188 baytlik paketler 0x47 ile baslar; en az uc paket aranir.
    if len(body) >= 376 and body[0] == 0x47 and body[188] == 0x47 and body[376] == 0x47:
        return "ts", "47.."
    if "mpegurl" in (ctype or "").lower():
        return "hls", ""
    return "bilinmeyen", head.hex()



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
    out("  Ayni filmin adresi farkli uzantilarla denenir. **Durum kodu tek")
    out("  basina yetmez**: panel 200 dondurup govdeye 0 bayt ya da HTML hata")
    out("  sayfasi koyabilir. Bu yuzden govdenin ilk baytlari da okunur ve")
    out("  yalnizca GERCEK VIDEO VERISI donduren adres 'calisiyor' sayilir.")
    base = args.url.rstrip("/")
    cand_exts = ["m3u8", "mp4", "mkv", "avi", "ts"]
    # AVPlayer'in cozebildigi tasiyicilar. MKV/AVI/WebM cozulemez.
    AVPLAYER_OK = {"hls", "mp4", "ts"}
    for it in vod_items[: args.sample]:
        sid = it.get("stream_id") or it.get("id")
        if sid is None:
            continue
        name = (it.get("name") or "?")[:40]
        declared = it.get("container_extension")
        out(f"\n  --- {name}  (id={sid}, bildirilen={declared}) ---")
        working = []       # gercek veri donen uzantilar
        playable = []      # gercek veri donen VE AVPlayer'in cozdugu uzantilar
        for ext in cand_exts:
            u = f"{base}/movie/{args.user}/{args.password}/{sid}.{ext}"
            st, ctype, size, sinif, sig = probe(u, ua=IPIOS_UA)
            if st != 200:
                out(f"       {ext:6} -> {st}  ({sinif})")
                continue
            if sinif in ("bos", "html"):
                # En yaniltici durum: 200 ama video yok.
                out(f"       {ext:6} -> 200  AMA GOVDE YOK ({sinif}) "
                    f"<-- 'calisiyor' SAYILMAZ")
                continue
            working.append(ext)
            if sinif in AVPLAYER_OK:
                playable.append(ext)
                out(f"    OK {ext:6} -> 200  [{sinif}] {size} bayt  AVPlayer cozer")
            else:
                out(f"    !! {ext:6} -> 200  [{sinif}] {size} bayt  "
                    f"AVPlayer BU KONTEYNERI COZEMEZ")
        if playable:
            out(f"    => AVPlayer'in OYNATABILECEGI UZANTILAR: {', '.join(playable)}")
            if declared and str(declared).lower() not in [w.lower() for w in playable]:
                notes.append(f"film id={sid}: sunucu '{declared}' bildiriyor "
                             f"ama AVPlayer icin calisan '{playable[0]}'")
        elif working:
            # Asil tuzak burada: bir uzanti veri donduruyor ama AVPlayer
            # o konteyneri cozemez (ornegin yalnizca MKV veriyor).
            out(f"    => YALNIZCA SU KONTEYNERLER VERI DONUYOR: "
                f"{', '.join(working)} — AVPlayer bunlari COZEMEZ.")
            out("       Eksik olan sey yedek adres degil, DEMUXER'dir;")
            out("       uzantiyi degistirmek de kurtarmaz.")
            problems.append(
                f"film id={sid}: saglayici yalnizca "
                f"{', '.join(working)} sunuyor ve AVPlayer bu konteyneri "
                f"cozemez -> IPiOS'ta oynatmak icin FFmpeg tabanli bir "
                f"oynatici cekirdegi gerekir (VLCKit)")
        else:
            out("    => Hicbir uzanti gercek video dondurmedi. "
                "Bu icerik bu hesapla oynatilamiyor.")
            problems.append(f"film id={sid} icin hicbir uzanti gercek veri "
                            f"dondurmedi -> saglayici bu icerigi sunmuyor")

    # --- 5b. User-Agent karsilastirmasi ------------------------------------
    out("\n[5b] USER-AGENT KARSILASTIRMASI (baska uygulamada calisiyor, bunda calismiyorsa)")
    out("  Ayni adres iki farkli uygulama adiyla denenir. Bazi saglayicilar")
    out("  bilmedikleri uygulamayi engeller ve 403 doner; baska bir oynatici")
    out("  kendi adini gonderdigi icin gecer. Fark cikarsa sorun adres")
    out("  uretiminde degil, gonderilen uygulama adindadir.")
    ua_mismatch = False
    for it in vod_items[: args.sample]:
        sid = it.get("stream_id") or it.get("id")
        if sid is None:
            continue
        ext = (it.get("container_extension") or "mp4").strip() or "mp4"
        u = f"{base}/movie/{args.user}/{args.password}/{sid}.{ext}"
        st_ipios = probe(u, ua=IPIOS_UA)[0]
        st_vlc = probe(u, ua=VLC_UA)[0]
        verdict = ""
        if st_ipios != 200 and st_vlc == 200:
            verdict = "  <-- IPiOS'un adi ENGELLENIYOR"
            ua_mismatch = True
        out(f"  film id={sid} ({ext}): IPiOS->{st_ipios}  diger oynatici->{st_vlc}{verdict}")
    if ua_mismatch:
        problems.append("Sunucu IPiOS'un User-Agent'ini engelliyor "
                        "(baska oynatici adiyla ayni adres 200 donuyor)")

    # --- 5c. Kodek denetimi ------------------------------------------------
    out("\n[5c] KODEK DENETIMI (AVPlayer'in cozemedigi kodekler)")
    out("  Dosyanin ilk baytlari indirilip icindeki kodek imzalari aranir.")
    out("  AVPlayer bazi ses kodeklerini (AC3/EAC3/DTS) COZEMEZ; baska bir")
    out("  oynatici (VLC gibi, FFmpeg tabanli) bunlari sorunsuz oynatir.")
    out("  'Baska uygulamada calisiyor ama bunda acilmiyor' tablosunun en")
    out("  yaygin nedeni budur.")

    VIDEO_CODECS = {
        "avc1": "H.264 (destekli)", "avc3": "H.264 (destekli)",
        "hvc1": "HEVC (destekli)", "hev1": "HEVC (destekli)",
        "vp09": "VP9 (AVPlayer COZEMEZ)", "av01": "AV1 (AVPlayer COZEMEZ)",
    }
    AUDIO_CODECS = {
        "mp4a": "AAC (destekli)", "ac-3": "AC3 (AVPlayer COZEMEZ)",
        "ec-3": "EAC3 (AVPlayer COZEMEZ)", "dtsc": "DTS (AVPlayer COZEMEZ)",
        "dtsh": "DTS-HD (AVPlayer COZEMEZ)", "dtsl": "DTS (AVPlayer COZEMEZ)",
        "opus": "Opus (MP4 icinde AVPlayer COZEMEZ)",
        "twos": "PCM (destekli)", "sowt": "PCM (destekli)",
    }
    BAD = ("COZEMEZ",)

    def sniff(url, label):
        ctx2 = ssl.create_default_context()
        ctx2.check_hostname = False
        ctx2.verify_mode = ssl.CERT_NONE
        req2 = urllib.request.Request(url, method="GET", headers={
            "User-Agent": IPIOS_UA,
            "Range": "bytes=0-524287",
        })
        try:
            with urllib.request.urlopen(req2, timeout=25, context=ctx2) as r:
                head = r.read()
                ctype = r.headers.get("Content-Type", "?")
                clen = r.headers.get("Content-Length", "?")
                crange = r.headers.get("Content-Range", "-")
                accepts_ranges = r.headers.get("Accept-Ranges", "?")
        except Exception as e:
            out(f"  {label}: indirilemedi ({str(e)[:50]})")
            return

        out(f"  {label}")
        out(f"     Content-Type   : {ctype}")
        out(f"     Content-Length  : {clen}   Content-Range: {crange}")
        out(f"     Accept-Ranges   : {accepts_ranges}")
        out(f"     indirilen       : {len(head)} bayt")

        magic = head[:12]
        if magic[4:8] == b"ftyp":
            brand = magic[8:12].decode("ascii", "replace")
            out(f"     konteyner      : MP4 (marka: {brand})")
        elif magic[0:1] == b"\x1a\x45\xdf\xa3"[:1] or head[:4] == b"\x1a\x45\xdf\xa3":
            out("     konteyner      : Matroska/WebM (AVPlayer COZEMEZ)")
            problems.append(f"{label}: dosya MKV/WebM — AVPlayer bu konteyneri cozemez")
        elif magic[:3] == b"ID3" or magic[0] == 0xFF:
            out("     konteyner      : MPEG audio")
        elif b"ftyp" in head[:200]:
            out("     konteyner      : MP4 (ftyp ileride)")
        else:
            out(f"     konteyner      : taninmadi (ilk baytlar: {magic.hex()})")
            if b"<html" in head[:1024].lower() or b"<!doctype" in head[:1024].lower():
                out("     !! Sunucu VIDEO yerine HTML SAYFASI donduruyor.")
                problems.append(f"{label}: sunucu video yerine HTML sayfasi donduruyor")
            return

        low = head.lower()
        found_v = [k for k in VIDEO_CODECS if k.encode() in low]
        found_a = [k for k in AUDIO_CODECS if k.encode() in low]

        if found_v:
            out("     goruntu kodegi : " + ", ".join(
                f"{k} [{VIDEO_CODECS[k]}]" for k in found_v))
        else:
            out("     goruntu kodegi : bulunamadi (moov sonda olabilir)")
        if found_a:
            out("     ses kodegi     : " + ", ".join(
                f"{k} [{AUDIO_CODECS[k]}]" for k in found_a))
        else:
            out("     ses kodegi     : bulunamadi (moov sonda olabilir)")

        bad_v = [k for k in found_v if k in ("vp09", "av01")]
        bad_a = [k for k in found_a if AUDIO_CODECS.get(k, "").endswith("COZEMEZ)")]
        if bad_v:
            problems.append(f"{label}: goruntu kodegi {', '.join(bad_v)} — "
                            f"AVPlayer cozemez, bu yuzden 'Oynatma baslatilamadi' cikar")
        if bad_a:
            problems.append(f"{label}: ses kodegi {', '.join(bad_a)} — "
                            f"AVPlayer cozemez (goruntulu dosyalarda ses sarttir)")
        if not bad_v and not bad_a and (found_v or found_a):
            out("     => AVPlayer bu dosyayi cozebilmeli. Sorun kodekte degil.")

    # Yalnizca 200 donen ilk adres uzerinde denenir.
    sniffed = False
    for it in vod_items[: args.sample]:
        sid = it.get("stream_id") or it.get("id")
        if sid is None:
            continue
        ext = (it.get("container_extension") or "mp4").strip() or "mp4"
        u = f"{base}/movie/{args.user}/{args.password}/{sid}.{ext}"
        st, _, _, sinif, _ = probe(u, ua=IPIOS_UA)
        # 200 dondurup govdesi bos olan adres uzerinde kodek aranmaz.
        if st == 200 and sinif not in ("bos", "html"):
            sniff(u, f"film id={sid} (.{ext})")
            sniffed = True
            break
    if not sniffed:
        out("  Denenecek acik adres bulunamadi.")

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
