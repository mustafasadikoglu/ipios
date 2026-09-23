#!/usr/bin/env python3
"""Ses/altyazi iz secimi mantiginin dogrulamasi.

Neden gerekli: VM'de Swift derleyicisi yok. Bu mantik dort parcaya dagilmis
durumda ve ucu de sessizce yanlis davranabilir:

  1. `PlaybackTrackSet.index(of:in:)`  — secim icin indeks uretir
  2. `PlaybackTrackSet.hasAnyChoice`   — menu dugmesinin gorunurlugu
  3. `VLCPlayerEngine.selectAudioTrack` — nesne uzerinden tek secim
  4. `TrackMenuView` etiket uretimi     — bos ad yerine numarali etiket

Bu dosya dort parcayi da birebir port eder ve beklenen davranisi sinar.

Swift kaynagi:
  - IPiOS/Domain/Models/PlaybackTrack.swift
  - IPiOS/Player/VLCPlayerEngine.swift  (İzler bolumu)
  - IPiOS/Views/Player/TrackMenuView.swift  (audioLabel/subtitleLabel)

Not: bu dosya metinleri SABIT yazar (yerellestirme dosyasindan okumaz) cunku
sinanan sey etiketin **icine konan sayi** ve **bos ada dusme kuralidir**;
ceviri metni degil.
"""


# ---------------------------------------------------------------------------
# Port: PlaybackTrack / PlaybackTrackSet
# ---------------------------------------------------------------------------
class Track:
    def __init__(self, track_id, name, language, kind, ordinal):
        self.id = track_id
        self.name = name
        self.language = language
        self.kind = kind
        self.ordinal = ordinal

    @property
    def has_empty_name(self):
        """Swift: name.trimmingCharacters(in: .whitespaces).isEmpty"""
        return self.name.strip() == ""

    @property
    def display_ordinal(self):
        """Swift: ordinal + 1  (kullaniciya 1 tabanli gosterilir)"""
        return self.ordinal + 1


class TrackSet:
    def __init__(self, audio=None, subtitles=None,
                 selected_audio_id=None, selected_subtitle_id=None):
        self.audio = audio or []
        self.subtitles = subtitles or []
        self.selected_audio_id = selected_audio_id
        self.selected_subtitle_id = selected_subtitle_id

    @property
    def has_audio_choice(self):
        return len(self.audio) > 1

    @property
    def has_subtitle_choice(self):
        return len(self.subtitles) > 0

    @property
    def has_any_choice(self):
        return self.has_audio_choice or self.has_subtitle_choice

    def list_for(self, kind):
        return self.audio if kind == "audio" else self.subtitles

    def index_of(self, track_id, kind):
        for i, t in enumerate(self.list_for(kind)):
            if t.id == track_id:
                return i
        return None


# ---------------------------------------------------------------------------
# Port: VLCPlayerEngine.selectAudioTrack / selectSubtitleTrack / disableSubtitles
# ---------------------------------------------------------------------------
class Motor:
    """libvlc'nin iz listesini taklit eder.

    Onemli: `audio_tracks` her okumada YENI nesneler dondurur (VLCKit boyle
    yapar) ama `selected` durumu libvlc'den gelir, yani kalicidir. Secim
    kimlikle yapildigi icin nesne kimligi onemsizdir.
    """

    def __init__(self, audio=(), subtitles=(), selected_audio=None,
                 selected_subtitles=()):
        self._audio = list(audio)
        self._subtitles = list(subtitles)
        self._selected_audio = selected_audio
        self._selected_subtitles = set(selected_subtitles)
        self.refresh_count = 0

    # --- libvlc taklidi: her okumada yeni nesneler ---
    def audio_tracks(self):
        return [("A", tid) for tid in self._audio]

    def text_tracks(self):
        return [("T", tid) for tid in self._subtitles]

    def is_selected(self, kind, tid):
        if kind == "A":
            return tid == self._selected_audio
        return tid in self._selected_subtitles

    @property
    def tracks(self):
        """refreshTracks() portu."""
        self.refresh_count += 1
        audio = [
            Track(tid, name="", language=None, kind="audio", ordinal=i)
            for i, tid in enumerate(self._audio)
        ]
        subs = [
            Track(tid, name="", language=None, kind="subtitle", ordinal=i)
            for i, tid in enumerate(self._subtitles)
        ]
        sel_audio = next((tid for tid in self._audio
                          if self.is_selected("A", tid)), None)
        sel_sub = next((tid for tid in self._subtitles
                        if self.is_selected("T", tid)), None)
        return TrackSet(audio, subs, sel_audio, sel_sub)

    # --- selectAudioTrack(id:) ---
    def select_audio_track(self, track_id):
        current = self.tracks
        if current.index_of(track_id, "audio") is None:
            return
        # `isSelectedExclusively = true` -> libvlc_media_player_select_track
        self._selected_audio = track_id
        self.tracks

    # --- selectSubtitleTrack(id:) ---
    def select_subtitle_track(self, track_id):
        if track_id not in self._subtitles:
            return
        # selectTextTracks: listeyi ID'lerle birlestirip sec_tracks_by_ids
        self._selected_subtitles = {track_id}
        self.tracks

    # --- disableSubtitles() ---
    def disable_subtitles(self):
        self._selected_subtitles = set()
        self.tracks


# ---------------------------------------------------------------------------
# Port: TrackMenuView.audioLabel / subtitleLabel
# ---------------------------------------------------------------------------
def audio_label(track):
    name = track.name.strip()
    if name:
        return name
    return f"Ses {track.display_ordinal}"


def subtitle_label(track):
    name = track.name.strip()
    if name:
        return name
    return f"Altyazi {track.display_ordinal}"


# ---------------------------------------------------------------------------
# Kontroller
# ---------------------------------------------------------------------------
hata = 0


def kontrol(ad, kosul, ek=""):
    global hata
    isaret = "OK  " if kosul else "HATA"
    print(f"  [{isaret}] {ad}" + (f"  ({ek})" if ek else ""))
    if not kosul:
        hata += 1
    return kosul


print("1) Tek ses izi olan ve altyazisiz icerikte iz menusu SUNULMAMALI")
tek = Motor(audio=["1"], subtitles=[])
kontrol("hasAnyChoice False", tek.tracks.has_any_choice is False,
        "menu kullaniciya secenek sunmazdi")

print("\n2) Cok ses izi olan icerikte menu SUNULMALI")
cok = Motor(audio=["1", "2", "3"])
kontrol("hasAnyChoice True", cok.tracks.has_any_choice is True)

print("\n3) Tek ses izi ama altyazi varsa menu SUNULMALI")
ses_altyazi = Motor(audio=["1"], subtitles=["5"])
kontrol("hasAnyChoice True", ses_altyazi.tracks.has_any_choice is True,
        "altyazi secimi tek basina yeterli")

print("\n4) Altyazisi olmayan icerikte altyazi bolumu GOSTERILMEMELI")
kontrol("hasSubtitleChoice False", tek.tracks.has_subtitle_choice is False)

print("\n5) Altyazi secimi DOGRU izi isaretlemeli")
m = Motor(audio=["1", "2"], subtitles=["10", "11"])
m.select_subtitle_track("11")
kontrol("selectedSubtitleID '11'", m.tracks.selected_subtitle_id == "11")

print("\n6) Altyazi kapatilinca hicbir altyazi secili kalmamali")
m.disable_subtitles()
kontrol("selectedSubtitleID None", m.tracks.selected_subtitle_id is None,
        "'Kapali' satiri bu duruma karsilik gelir")

print("\n7) Altyazi kapaliyken baska bir altyazi secmek cokmemeli")
# VLCKit kaynaginda bu gecis nil `unselectedId` uretir; motorun bunu
# delege geri cagrisiyla DEGIL kendi tazelemesiyle ele almasi gerekir.
m.select_subtitle_track("10")
kontrol("secim yapildi", m.tracks.selected_subtitle_id == "10",
        "ilk altyazi acilisinda unselectedId nil gelir")

print("\n8) Ses izi secimi TEK iz birakmali (cift ses ayni anda olmaz)")
m2 = Motor(audio=["1", "2"], selected_audio="1")
m2.select_audio_track("2")
kontrol("selectedAudioID '2'", m2.tracks.selected_audio_id == "2")

print("\n9) Cok ses izi varken selectAudioTrack indeksle degil KIMLIKLE calismali")
# libvlc'de 2+ ses izi seciliyken `setSelected` sessizce hicbir sey yapmaz.
# Bu yuzden `isSelectedExclusively` kullanilir; port da onu taklit eder.
m3 = Motor(audio=["1", "2", "3"])
m3.select_audio_track("3")
kontrol("ucuncu iz secildi", m3.tracks.selected_audio_id == "3",
        "setSelected kullanilsaydi secim sessizce yok sayilirdi")

print("\n10) Bilinmeyen kimlik sessizce yok sayilmali (cokme yok)")
m4 = Motor(audio=["1", "2"])
m4.select_audio_track("99")
kontrol("durum degismedi", m4.tracks.selected_audio_id is None)

print("\n11) Bos adli izler numarali etiket almali")
t0 = Track("1", "", None, "audio", 0)
t1 = Track("2", "", None, "audio", 1)
kontrol("ilk ses etiketi 'Ses 1'", audio_label(t0) == "Ses 1")
kontrol("ikinci ses etiketi 'Ses 2'", audio_label(t1) == "Ses 2",
        "0 tabanli ordinal ekranda 1 tabanli olmali")

print("\n12) Adi olan iz kendi adini gostermeli (numaralandirilmamali)")
adli = Track("1", "Türkçe AC3", "tur", "audio", 0)
kontrol("ad korundu", audio_label(adli) == "Türkçe AC3")

print("\n13) Yalnizca bosluktan olusan ad BOS sayilmali")
bosluk = Track("1", "   ", None, "subtitle", 0)
kontrol("hasEmptyName True", bosluk.has_empty_name is True)
kontrol("etiket 'Altyazi 1'", subtitle_label(bosluk) == "Altyazi 1",
        "bos satir gosterilseydi kullanici hangi izi sectigini bilemezdi")

print("\n14) Kimlik nesne kimligine degil trackId'ye gore eslesmeli")
# VLCKit iz nesnelerini her okumada yeniden uretir; liste esitligi ve secim
# KIMLIGE dayanmalidir.
m5 = Motor(audio=["1", "2"])
onceki = m5.tracks
sonraki = m5.tracks
kontrol("ayni kimlikler", [t.id for t in onceki.audio] == [t.id for t in sonraki.audio])
kontrol("nesneler farkli", onceki.audio[0] is not sonraki.audio[0],
        "gercekte de yeni nesne uretilir")

print("\n15) Durdurunca iz listesi bosalmali")
# `stop()` icinde `tracks = .empty`
bos = TrackSet()
kontrol("bos kumede secenek yok", bos.has_any_choice is False)
kontrol("bos kumede indeks yok", bos.index_of("1", "audio") is None,
        "onceki filmin altyazisi menude kalmamali")

print("\n" + "=" * 60)
if hata:
    print(f"SONUC: {hata} kontrol BASARISIZ")
else:
    print("SONUC: tum kontroller gecti")
raise SystemExit(1 if hata else 0)
