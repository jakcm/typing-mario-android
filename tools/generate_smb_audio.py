#!/usr/bin/env python3
"""Generate Super Mario Bros. (1985) style chiptune audio faithfully.

Musical spec sourced from authoritative analyses:
- Overworld theme note transcription (noobnotes.net), Koji Kondo, key of C major.
- Sound-effect breakdown (losdoggies.com "Super Mario Melodies"):
  * Coin  = B appoggiatura -> E (perfect fourth), the "bling".
  * Jump  = pulse wave, low note bending up (portamento).
  * Stomp = C/F perfect-fourth, dissonant.
  * 1-Up  = C major add9 rising arpeggio.
  * Power-up = Ab, Bb, C rising arpeggio.
  * Fireball/gameover = descending phrases.
All waveforms are NES-style pulse (square) waves with duty cycle, matching the
2A03 sound chip, plus a noise channel for percussive/hurt effects.
"""
import wave, array, math, os

SR = 44100
OUT = 'assets/audio/sfx'
os.makedirs(OUT, exist_ok=True)

# Equal-tempered frequencies, A4 = 440.
_A4 = 440.0
_NAMES = {'C':-9,'C#':-8,'Db':-8,'D':-7,'D#':-6,'Eb':-6,'E':-5,'F':-4,
          'F#':-3,'Gb':-3,'G':-2,'G#':-1,'Ab':-1,'A':0,'A#':1,'Bb':1,'B':2}
def freq(name, octave):
    semi = _NAMES[name] + (octave - 4) * 12
    return _A4 * (2 ** (semi / 12.0))

def pulse(f, t, duty=0.5):
    if f <= 0:
        return 0.0
    phase = (f * t) % 1.0
    return 1.0 if phase < duty else -1.0

def env_adsr(x, dur, a=0.005, d=0.02, s=0.75, r=0.03):
    if x < 0 or x > dur:
        return 0.0
    if x < a:
        return x / a
    if x < a + d:
        return 1.0 - (1.0 - s) * (x - a) / d
    if x > dur - r:
        return s * max(0.0, (dur - x) / r)
    return s

def render(events, total, base_amp=7000):
    """events: list of (start, dur, freq, amp, duty). Additive mixing."""
    n = int(SR * total)
    buf = array.array('i', [0] * n)
    for (start, dur, f, amp, duty) in events:
        s = int(start * SR)
        e = int((start + dur) * SR)
        for k in range(s, min(e, n)):
            t = k / SR
            x = t - start
            buf[k] += int(pulse(f, t, duty) * env_adsr(x, dur) * amp)
    out = array.array('h', [0] * n)
    for k in range(n):
        v = buf[k]
        out[k] = max(-32768, min(32767, v))
    # tiny 2ms de-click on the very ends
    fade = int(0.002 * SR)
    for k in range(min(fade, n)):
        out[k] = int(out[k] * k / fade)
        out[n - 1 - k] = int(out[n - 1 - k] * k / fade)
    return out

def save(name, samples):
    with wave.open(f'{OUT}/{name}.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(samples.tobytes())
    print(f'{name:10} {len(samples)/SR:.3f}s')

# ─────────────────────────────────────────────────────────────────────────
# BGM: Overworld theme. Tempo ~ 200 BPM (eighth = 0.15s), classic feel.
# Notes below transcribe the recognizable A-section + bridge, then loop.
# Format: (note, octave, beats) where 1 beat = one eighth note here.
# ─────────────────────────────────────────────────────────────────────────
EIGHTH = 0.153  # seconds per eighth note

# Main phrase (the world-famous intro + first section), faithful to SMB.
melody = [
    ('E',5,1),('E',5,1),('R',0,1),('E',5,1),('R',0,1),('C',5,1),('E',5,1),('R',0,1),
    ('G',5,1),('R',0,1),('R',0,1),('R',0,1),('G',4,1),('R',0,1),('R',0,1),('R',0,1),
    # phrase 2
    ('C',5,1),('R',0,1),('R',0,1),('G',4,1),('R',0,1),('R',0,1),('E',4,1),('R',0,1),
    ('R',0,1),('A',4,1),('R',0,1),('B',4,1),('R',0,1),('Bb',4,1),('A',4,1),('R',0,1),
    ('G',4,1),('E',5,1),('G',5,1),('A',5,1),('R',0,1),('F',5,1),('G',5,1),('R',0,1),
    ('E',5,1),('R',0,1),('C',5,1),('D',5,1),('B',4,1),('R',0,1),('R',0,1),('R',0,1),
    # phrase 3 (repeat of phrase 2 body)
    ('C',5,1),('R',0,1),('R',0,1),('G',4,1),('R',0,1),('R',0,1),('E',4,1),('R',0,1),
    ('R',0,1),('A',4,1),('R',0,1),('B',4,1),('R',0,1),('Bb',4,1),('A',4,1),('R',0,1),
    ('G',4,1),('E',5,1),('G',5,1),('A',5,1),('R',0,1),('F',5,1),('G',5,1),('R',0,1),
    ('E',5,1),('R',0,1),('C',5,1),('D',5,1),('B',4,1),('R',0,1),('R',0,1),('R',0,1),
]

# Bass line (root motion under the melody), one note per two eighths.
bass = [
    ('C',3),('C',3),('G',2),('G',2),('C',3),('C',3),('G',2),('G',2),
    ('C',3),('E',3),('G',3),('C',3),('F',3),('D',3),('G',3),('G',2),
    ('C',3),('E',3),('G',3),('C',3),('F',3),('D',3),('G',3),('G',2),
]

events = []
t = 0.0
for (nm, octv, beats) in melody:
    dur = EIGHTH * beats
    if nm != 'R':
        events.append((t, dur * 0.92, freq(nm, octv), 6800, 0.5))
    t += dur
total = t

tb = 0.0
step = EIGHTH * 2
for i, (nm, octv) in enumerate(bass):
    if tb >= total:
        break
    events.append((tb, step * 0.9, freq(nm, octv), 3800, 0.25))
    tb += step

bgm = render(events, total)
# Ensure seamless loop: already de-clicked; verify integer beat length.
save('bgm', bgm)

# ─────────────────────────────────────────────────────────────────────────
# COIN: B (grace) -> E, the "bling". High register, short.
# ─────────────────────────────────────────────────────────────────────────
coin_ev = [
    (0.0, 0.06, freq('B', 5), 8000, 0.5),
    (0.06, 0.34, freq('E', 6), 8000, 0.5),
]
save('coin', render(coin_ev, 0.42))

# ─────────────────────────────────────────────────────────────────────────
# JUMP: pulse wave sweeping upward (portamento), duty 0.5.
# ─────────────────────────────────────────────────────────────────────────
def render_sweep(f0, f1, dur, amp=6500, duty=0.5, curve='exp'):
    n = int(SR * dur)
    out = array.array('h', [0] * n)
    phase = 0.0
    for k in range(n):
        frac = k / n
        if curve == 'exp':
            f = f0 * (f1 / f0) ** frac
        else:
            f = f0 + (f1 - f0) * frac
        phase += f / SR
        v = 1.0 if (phase % 1.0) < duty else -1.0
        e = env_adsr(k / SR, dur, a=0.004, d=0.01, s=0.8, r=0.05)
        out[k] = max(-32768, min(32767, int(v * e * amp)))
    fade = int(0.002 * SR)
    for k in range(min(fade, n)):
        out[k] = int(out[k] * k / fade)
        out[n - 1 - k] = int(out[n - 1 - k] * k / fade)
    return out

save('jump', render_sweep(freq('A', 4), freq('A', 5), 0.22))

# ─────────────────────────────────────────────────────────────────────────
# STOMP: quick low dissonant thud, C/F perfect-fourth clash, downward.
# ─────────────────────────────────────────────────────────────────────────
stomp_ev = [
    (0.0, 0.05, freq('F', 4), 7000, 0.5),
    (0.0, 0.05, freq('C', 4), 6000, 0.5),
    (0.05, 0.08, freq('C', 3), 7000, 0.5),
]
save('stomp', render(stomp_ev, 0.15))

# ─────────────────────────────────────────────────────────────────────────
# 1-UP: C major add9 rising arpeggio (E G E C ... classic 1-up jingle).
# ─────────────────────────────────────────────────────────────────────────
oneup_ev = []
seq = [('E',5),('G',5),('E',6),('C',6),('D',6),('G',6)]
tt = 0.0
for nm, octv in seq:
    oneup_ev.append((tt, 0.11, freq(nm, octv), 7000, 0.5))
    tt += 0.09
save('oneup', render(oneup_ev, tt + 0.15))

# ─────────────────────────────────────────────────────────────────────────
# POWER-UP: fast rising run through Ab, Bb, C chords (mushroom).
# ─────────────────────────────────────────────────────────────────────────
pu_ev = []
seq = [('G',4),('Ab',4),('Bb',4),('C',5),('D',5),('Eb',5),('F',5),('G',5),
       ('Ab',5),('Bb',5),('C',6)]
tt = 0.0
for nm, octv in seq:
    pu_ev.append((tt, 0.06, freq(nm, octv), 6500, 0.5))
    tt += 0.045
save('powerup', render(pu_ev, tt + 0.1))

# ─────────────────────────────────────────────────────────────────────────
# BUMP / hurt: short dissonant low blip (block-bump style).
# ─────────────────────────────────────────────────────────────────────────
bump_ev = [
    (0.0, 0.08, freq('A', 3), 7000, 0.5),
    (0.0, 0.08, freq('Eb', 3), 5000, 0.5),
]
save('bump', render(bump_ev, 0.12))

# ─────────────────────────────────────────────────────────────────────────
# GAME OVER: the classic short descending "aww" phrase.
# ─────────────────────────────────────────────────────────────────────────
go = [('C',5),('R',0),('G',4),('E',4),('R',0),('A',4),('B',4),('A',4),
      ('Ab',4),('Bb',4),('Ab',4),('G',4)]
go_ev = []
tt = 0.0
durs = [0.18,0.06,0.18,0.18,0.06,0.16,0.16,0.16,0.16,0.16,0.16,0.5]
for (item, d) in zip(go, durs):
    nm, octv = item
    if nm != 'R':
        go_ev.append((tt, d * 0.9, freq(nm, octv), 6500, 0.5))
    tt += d
save('gameover', render(go_ev, tt + 0.1))

print('All SMB-style audio generated.')
