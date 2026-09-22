#!/usr/bin/env python3
"""VLCPlayerEngine'deki tampon gostergesi mantiginin dogrulamasi.

Neden gerekli: VM'de Swift derleyicisi yok. Bu mantik, "ileri sarinca
yuklenmiyor" kusurunun duzeltmesidir ve yanlis yazilirsa kullanici yine
donmus kareye bakar. Swift'teki karar akisinin birebir portu asagida
calistirilir ve beklenen davranis sinanir.

Swift kaynagi: IPiOS/Player/VLCPlayerEngine.swift
  - updateBufferingIndicator(progress:)
  - handle(time:)
  - beginSeeking(target:) / finishSeeking()
"""


class Motor:
    """updateBufferingIndicator + handle(time:) portu."""

    def __init__(self):
        self.has_started_playing = False
        self.is_buffering = False
        self.is_seeking = False
        self.seeking_target = 0.0
        self.seek_arrival_tolerance = 3.0
        # Sarmadan bu yana gecen sure (saniye). Swift'te `Date()` farki;
        # testte elle ilerletilir ki zaman bagimliligi deterministik olsun.
        self.seek_elapsed = 0.0
        self.seek_playback_grace = 1.5

    # --- updateBufferingIndicator(progress:) ---
    def tampon_bildir(self, progress):
        doluyor = progress < 1.0

        if not self.has_started_playing:
            self.is_buffering = doluyor
            return
        if self.is_seeking:
            self.is_buffering = True
            return
        self.is_buffering = False

    # --- handle(time:) ---
    def zaman_bildir(self, seconds):
        if self.is_seeking and abs(seconds - self.seeking_target) <= self.seek_arrival_tolerance:
            self.finish_seeking()

    # --- beginSeeking / finishSeeking ---
    def begin_seeking(self, target):
        self.is_seeking = True
        self.seeking_target = target
        self.seek_elapsed = 0.0
        self.is_buffering = True

    def finish_seeking(self):
        if not self.is_seeking:
            return
        self.is_seeking = False
        self.seek_elapsed = 0.0
        self.is_buffering = False

    @property
    def should_playback_end_seek(self):
        return self.is_seeking and self.seek_elapsed >= self.seek_playback_grace

    def oynatma_basladi(self):
        self.has_started_playing = True
        if self.should_playback_end_seek:
            self.finish_seeking()
        elif not self.is_seeking:
            self.is_buffering = False


def kontrol(ad, kosul, ek=""):
    isaret = "OK  " if kosul else "HATA"
    print(f"  [{isaret}] {ad}" + (f"  ({ek})" if ek else ""))
    return kosul


hata = 0

print("1) Oynatma akarken kisa tamponlama gosterge ACMAMALI")
m = Motor()
m.oynatma_basladi()
m.tampon_bildir(0.5)
hata += not kontrol("akis sirasinda isBuffering False", m.is_buffering is False)

print("\n2) Sarma baslarken gosterge ACMALI")
m = Motor()
m.oynatma_basladi()
m.begin_seeking(600)
hata += not kontrol("sarma basinda isBuffering True", m.is_buffering is True)

print("\n3) libvlc sarma sirasinda progress=1.0 bildirse bile gosterge ACIK kalmali")
m.tampon_bildir(1.0)
hata += not kontrol(
    "progress=1.0 gostergeyi kapatmadi",
    m.is_buffering is True,
    "eski kod tam burada kapatip donmus kare birakiyordu",
)

print("\n4) libvlc eski konumdan bildirmeye devam ederken gosterge kapanMAMALI")
m = Motor()
m.oynatma_basladi()
m.begin_seeking(600)
m.zaman_bildir(120)          # hala eski konum
hata += not kontrol("eski konum gostergeyi kapatmadi", m.is_buffering is True)
m.zaman_bildir(599)          # hedefe yaklasti (tolerans 3 sn)
hata += not kontrol("hedefe ulasinca gosterge kapandi", m.is_buffering is False)

print("\n5) Hedefe tam oturmayan arama (anahtar kare hizasi) da kapatmali")
m = Motor()
m.oynatma_basladi()
m.begin_seeking(600)
m.zaman_bildir(597.5)
hata += not kontrol("tolerans icinde kapaniyor", m.is_buffering is False)

print("\n6) Tolerans disinda kalan konum gostergeyi kapatMAMALI")
m = Motor()
m.oynatma_basladi()
m.begin_seeking(600)
m.zaman_bildir(580)
hata += not kontrol("uzak konum gostergeyi acik tutuyor", m.is_buffering is True)

print("\n7) Sarmadan HEMEN sonra gelen .playing gostergeyi kapatMAMALI")
m = Motor()
m.oynatma_basladi()
m.begin_seeking(600)
m.seek_elapsed = 0.2         # libvlc henuz yeni kareyi cizmedi
m.oynatma_basladi()
hata += not kontrol(
    "erken .playing gostergeyi kapatmadi",
    m.is_buffering is True,
    "kapatilsaydi kullanici donmus kareye bakardi",
)

print("\n8) Sarmadan sonra sure gecince .playing gostergesi kapanmali")
m.seek_elapsed = 2.0         # asgari sureden fazla gecti
m.oynatma_basladi()
hata += not kontrol("gec .playing gostergesi kapatti", m.is_buffering is False)

print("\n9) Sarma yokken .playing gostergesi kapatmali")
m = Motor()
m.oynatma_basladi()
m.is_buffering = True        # .stopping'den kalma
m.oynatma_basladi()
hata += not kontrol("sarma yokken kapandi", m.is_buffering is False)

print("\n10) finishSeeking iki kez cagrilirsa zararsiz olmali")
m = Motor()
m.begin_seeking(600)
m.finish_seeking()
m.finish_seeking()
hata += not kontrol("ikinci cagri durumu bozmadi", m.is_buffering is False)

print("\n" + "=" * 60)
if hata:
    print(f"SONUC: {hata} kontrol BASARISIZ")
else:
    print("SONUC: tum kontroller gecti")
raise SystemExit(1 if hata else 0)
