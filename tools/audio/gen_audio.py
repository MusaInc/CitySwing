"""Synthesises every sound in City Swing from code (no samples, no licences).

    python3 tools/audio/gen_audio.py assets/audio

Writes 16-bit mono WAVs at 44.1 kHz (music/ambience stereo). Loops are made
seamless by crossfading the tail into the head.
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1207)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def env(n, a, d, s_level=0.0, curve=4.0):
    """Attack/decay envelope over n samples (a, d in seconds)."""
    e = np.zeros(n)
    na = max(1, int(a * SR))
    nd = max(1, int(d * SR))
    e[:na] = np.linspace(0, 1, na)
    end = min(n, na + nd)
    e[na:end] = s_level + (1 - s_level) * np.exp(-curve * np.linspace(0, 1, end - na))
    e[end:] = s_level * np.exp(-curve * np.linspace(0, 1, n - end)) if n > end else 0
    return e


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be an array (time-varying)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * c / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def lp_fast(x, cutoff):
    """Fixed-cutoff one-pole via scipy-free IIR (vectorised with cumulative trick)."""
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    b = 1 - a
    for i, v in enumerate(x):
        acc = acc * b + a * v
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    return lp_fast(x, hi) - lp_fast(x, lo)


def loopify(x, fade=0.5):
    n = int(fade * SR)
    if x.ndim == 1:
        head = x[:n].copy()
        tail = x[-n:]
        w = np.linspace(0, 1, n)
        x = x[: -n].copy()
        x[:n] = head * w + tail * (1 - w)
    else:
        x = np.stack([loopify(x[:, c], fade) for c in range(x.shape[1])], axis=1)
    return x


def write(name, x, stereo=False):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"AUDIO {name} {len(x) / SR:.2f}s")


def noise(sec):
    return rng.standard_normal(int(sec * SR))


# ------------------------------------------------------------------ loops
def wind_loop():
    """Broadband rushing air with slow gusts; pitch/volume driven at runtime."""
    n = noise(8.0)
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t(8.0) * 0.25) * np.sin(2 * np.pi * t(8.0) * 0.11 + 1)
    x = bandpass(n, 120, 1800) * gust + 0.3 * bandpass(n, 1500, 5000) * gust ** 2
    write("wind_loop.wav", norm(loopify(x, 1.0), 0.8))


def rope_tension_loop():
    """Taut-line hum + creak grain: plays louder under rope load."""
    tt = t(4.0)
    hum = 0.5 * np.sin(2 * np.pi * 92 * tt) + 0.25 * np.sin(2 * np.pi * 184.7 * tt) + 0.1 * np.sin(2 * np.pi * 277 * tt)
    hum *= 0.7 + 0.3 * np.sin(2 * np.pi * 3.1 * tt)
    creak = np.zeros_like(tt)
    for c in rng.uniform(0, 3.8, 9):
        i = int(c * SR)
        ln = int(0.09 * SR)
        g = np.sin(2 * np.pi * rng.uniform(300, 600) * t(0.09)) * env(ln, 0.005, 0.08) * (rng.random(ln) > 0.6)
        creak[i:i + ln] += g[: len(creak[i:i + ln])]
    x = lp_fast(hum + 0.4 * creak, 1500)
    write("rope_tension_loop.wav", norm(loopify(x, 0.4), 0.6))


def city_ambience():
    """Distant city: low traffic rumble, occasional horn/siren far away, birds."""
    sec = 20.0
    tt = t(sec)
    rumble = lp_fast(noise(sec), 220) * (0.8 + 0.2 * np.sin(2 * np.pi * tt * 0.07))
    hiss = bandpass(noise(sec), 400, 2500) * 0.15
    x = rumble * 1.5 + hiss
    for start in (3.2, 11.7, 16.4):  # far horns
        i = int(start * SR)
        d = 0.45
        h = (np.sin(2 * np.pi * 415 * t(d)) + 0.6 * np.sin(2 * np.pi * 523 * t(d))) * env(int(d * SR), 0.02, 0.4, 0.6)
        x[i:i + len(h)] += lp_fast(h, 1200) * 0.08
    for start in rng.uniform(0, sec - 1, 14):  # gull-ish chirps
        i = int(start * SR)
        d = 0.25
        f = np.linspace(1800, 1200, int(d * SR))
        c = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(int(d * SR), 0.01, 0.2)
        x[i:i + len(c)] += c * 0.03
    x = norm(loopify(x, 2.0), 0.6)
    st = np.stack([x, np.roll(x, 2200)], axis=1)
    write("city_ambience.wav", st, stereo=True)


def music_loop():
    """Calm, forward-moving ambient pad (Am – F – C – G), soft pluck arpeggio.
    64 bars of 4/4 at 92 bpm would be large; 8 bars loop (~21 s)."""
    bpm = 92
    beat = 60 / bpm
    bars = 8
    sec = bars * 4 * beat
    tt = t(sec)
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # MIDI notes
    pad = np.zeros_like(tt)
    arp = np.zeros_like(tt)
    for bar in range(bars):
        ch = chords[bar % 4]
        s = int(bar * 4 * beat * SR)
        e = int((bar + 1) * 4 * beat * SR)
        seg = tt[: e - s]
        for note in ch:
            f = 440 * 2 ** ((note - 69) / 12)
            # Detuned saw-ish pad via a few harmonics, slow swell.
            v = sum(np.sin(2 * np.pi * f * k * seg * (1 + 0.002 * (k % 2))) / k for k in range(1, 6))
            pad[s:e] += v * (0.5 - 0.5 * np.cos(2 * np.pi * np.clip(seg / (4 * beat), 0, 1)))
        for step in range(8):  # eighth-note pluck arpeggio
            note = ch[[0, 1, 2, 1, 0, 2, 1, 2][step]] + 12
            f = 440 * 2 ** ((note - 69) / 12)
            i = s + int(step * beat / 2 * SR)
            d = int(beat * 0.9 * SR)
            p = np.sin(2 * np.pi * f * t(beat * 0.9)) * env(d, 0.004, beat * 0.8, 0.0, 6)
            arp[i:i + d] += p[: len(arp[i:i + d])] * (0.6 if step % 2 == 0 else 0.4)
    bass = np.zeros_like(tt)
    for bar in range(bars):
        f = 440 * 2 ** ((chords[bar % 4][0] - 24 - 69) / 12)
        s = int(bar * 4 * beat * SR)
        d = int(4 * beat * SR)
        bass[s:s + d] += np.sin(2 * np.pi * f * t(4 * beat))[: len(bass[s:s + d])] * env(d, 0.05, 3.5, 0.3, 2)
    pad = lp_fast(pad, 900)
    left = pad * 0.5 + arp * 0.35 + bass * 0.6
    right = pad * 0.5 + np.roll(arp, int(0.18 * SR)) * 0.3 + bass * 0.6
    st = np.stack([left, right], axis=1)
    st = st / np.max(np.abs(st)) * 0.7
    write("music_loop.wav", st, stereo=True)


# ---------------------------------------------------------------- one-shots
def grapple_fire():
    d = 0.32
    n = int(d * SR)
    f = np.linspace(2400, 700, n)
    zip_ = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.25)
    hiss = bandpass(noise(d), 2000, 7000) * env(n, 0.001, 0.2)
    pop = lp_fast(noise(d), 300) * env(n, 0.001, 0.04) * 3
    write("grapple_fire.wav", norm(zip_ * 0.5 + hiss * 0.6 + pop, 0.8))


def grapple_attach():
    d = 0.28
    n = int(d * SR)
    thunk = np.sin(2 * np.pi * 110 * t(d) * (1 - 0.3 * t(d))) * env(n, 0.001, 0.12)
    clank = sum(np.sin(2 * np.pi * f * t(d)) for f in (1430, 2210, 3170)) * env(n, 0.001, 0.08) * 0.3
    write("grapple_attach.wav", norm(thunk + clank + lp_fast(noise(d), 900) * env(n, 0.001, 0.03), 0.85))


def grapple_miss():
    d = 0.4
    n = int(d * SR)
    f = np.linspace(900, 200, n)
    write("grapple_miss.wav", norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.005, 0.35) * 0.4
                                   + bandpass(noise(d), 500, 3000) * env(n, 0.01, 0.3) * 0.3, 0.5))


def release():
    d = 0.45
    n = int(d * SR)
    sweep = np.linspace(400, 2600, n)
    x = bandpass(noise(d), 300, 3500)
    x = lowpass(x, sweep) * env(n, 0.05, 0.38)
    write("release_whoosh.wav", norm(x, 0.7))


def rope_snap():
    d = 0.2
    n = int(d * SR)
    twang = sum(np.sin(2 * np.pi * f * t(d)) * a for f, a in ((180, 1), (362, 0.5), (545, 0.25)))
    write("rope_snap.wav", norm(twang * env(n, 0.001, 0.17) + lp_fast(noise(d), 1500) * env(n, 0.001, 0.02), 0.7))


def landing():
    d = 0.35
    n = int(d * SR)
    thud = np.sin(2 * np.pi * 70 * t(d)) * env(n, 0.001, 0.15) + lp_fast(noise(d), 500) * env(n, 0.001, 0.08)
    scuff = bandpass(noise(d), 1000, 5000) * env(n, 0.01, 0.2) * 0.4
    write("land.wav", norm(thud + scuff, 0.85))


def roll():
    d = 0.6
    n = int(d * SR)
    x = bandpass(noise(d), 300, 3000) * (env(n, 0.02, 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t(d))))
    x += np.sin(2 * np.pi * 60 * t(d)) * env(n, 0.001, 0.1)
    write("roll.wav", norm(x, 0.7))


def impact():
    d = 0.5
    n = int(d * SR)
    body = np.sin(2 * np.pi * 55 * t(d)) * env(n, 0.001, 0.3) + lp_fast(noise(d), 700) * env(n, 0.001, 0.12) * 1.5
    glassy = sum(np.sin(2 * np.pi * f * t(d)) for f in (2300, 3410, 4720)) * env(n, 0.001, 0.15) * 0.15
    write("impact.wav", norm(body + glassy, 0.95))


def splash():
    d = 1.0
    n = int(d * SR)
    x = bandpass(noise(d), 200, 6000) * env(n, 0.005, 0.8) + lp_fast(noise(d), 300) * env(n, 0.001, 0.2)
    write("splash.wav", norm(x, 0.8))


def checkpoint():
    d = 0.7
    n = int(d * SR)
    x = np.zeros(n)
    for k, note in enumerate((76, 81, 88)):
        f = 440 * 2 ** ((note - 69) / 12)
        i = int(k * 0.06 * SR)
        s = np.sin(2 * np.pi * f * np.arange(n - i) / SR) * env(n - i, 0.003, 0.5)
        x[i:] += s * (0.8 - k * 0.15)
    write("checkpoint.wav", norm(x, 0.6))


def finish():
    d = 1.6
    n = int(d * SR)
    x = np.zeros(n)
    for k, note in enumerate((69, 73, 76, 81, 85)):
        f = 440 * 2 ** ((note - 69) / 12)
        i = int(k * 0.09 * SR)
        x[i:] += np.sin(2 * np.pi * f * np.arange(n - i) / SR) * env(n - i, 0.004, 1.2) * 0.7
    write("finish.wav", norm(x, 0.65))


def fail():
    d = 0.9
    n = int(d * SR)
    f = np.linspace(330, 160, n)
    write("fail.wav", norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.01, 0.8), 0.5))


def ui_click():
    d = 0.06
    n = int(d * SR)
    write("ui_click.wav", norm(np.sin(2 * np.pi * 1800 * t(d)) * env(n, 0.001, 0.04), 0.4))


def wall_kick():
    d = 0.25
    n = int(d * SR)
    write("wall_kick.wav", norm(np.sin(2 * np.pi * 95 * t(d)) * env(n, 0.001, 0.1)
                                + bandpass(noise(d), 800, 4000) * env(n, 0.002, 0.15) * 0.5, 0.8))


def knockout():
    # Wall knockout: a deep body slam with a falling pitch, a crunchy burst,
    # then a soft ringing-ears tone that fades out.
    d = 1.8
    n = int(d * SR)
    f = np.linspace(75, 38, n)
    slam = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.45) * 1.4
    crunch = bandpass(noise(d), 400, 2600) * env(n, 0.001, 0.09) * 1.2 + lp_fast(noise(d), 900) * env(n, 0.001, 0.2)
    ring = (np.sin(2 * np.pi * 3150 * t(d)) + 0.5 * np.sin(2 * np.pi * 3190 * t(d))) * env(n, 0.08, 1.6) * 0.06
    write("knockout.wav", norm(slam + crunch + ring, 0.95))


ALL = (wind_loop, rope_tension_loop, city_ambience, music_loop, grapple_fire, grapple_attach, grapple_miss,
       release, rope_snap, landing, roll, impact, splash, checkpoint, finish, fail, ui_click, wall_kick, knockout)

if __name__ == "__main__":
    # gen_audio.py <outdir> [name ...]: only the named generators (default all).
    only = set(sys.argv[2:])
    for fn in ALL:
        if not only or fn.__name__ in only:
            fn()
    print("AUDIO DONE")
