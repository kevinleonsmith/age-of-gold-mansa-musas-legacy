#!/usr/bin/env python3
"""Synthesizes the music loops and sound effects for Age of Gold.

Everything is generated from scratch with numpy (no samples): Karplus-Strong
kora, modal djembe strokes, balafon mallet tones, shekere noise, an ivory
"siwa" horn and a few metallic sounds. Output: 16-bit mono WAV at 22050 Hz in
"Age of Gold Game/assets/audio/{music,sfx}/". Deterministic (fixed seeds).

Usage: python3 create_audio.py [--preview DIR]
"""
import os
import sys
import wave

import numpy as np

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Age of Gold Game", "assets", "audio")


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def midi_hz(m):
	return 440.0 * 2.0 ** ((m - 69) / 12.0)


def secs(n):
	return int(round(n * SR))


def env_exp(n, tau, attack=0.002):
	"""Exponential decay envelope with a short linear attack (tau in seconds)."""
	t = np.arange(n) / SR
	e = np.exp(-t / max(tau, 1e-4))
	a = max(1, secs(attack))
	e[:a] *= np.linspace(0.0, 1.0, a, endpoint=False) if a > 1 else 1.0
	return e


def fft_filter(x, lo=None, hi=None, slope=0.15):
	"""Band-limits x in the frequency domain with soft (raised-cosine-ish) edges."""
	n = len(x)
	X = np.fft.rfft(x)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	g = np.ones_like(f)
	if lo is not None:
		g *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
	if hi is not None:
		g *= 1.0 / (1.0 + (f / hi) ** 4)
	return np.fft.irfft(X * g, n)


def fft_convolve(x, h):
	n = len(x) + len(h) - 1
	size = 1 << (n - 1).bit_length()
	y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)
	return y[:n]


def resample(x, ratio):
	"""Pitch-shift by `ratio` (>1 = higher) with linear interpolation."""
	if abs(ratio - 1.0) < 1e-6:
		return x
	n_out = int(len(x) / ratio)
	pos = np.arange(n_out) * ratio
	return np.interp(pos, np.arange(len(x)), x)


def add(buf, sig, start, gain=1.0):
	"""Mixes sig into buf at sample `start` (clipped to the buffer)."""
	start = int(start)
	if start >= len(buf):
		return
	end = min(len(buf), start + len(sig))
	buf[start:end] += sig[: end - start] * gain


def fold(buf, length):
	"""Wraps everything past `length` back onto the start: a seamless loop."""
	out = np.zeros(length)
	for i in range(0, len(buf), length):
		chunk = buf[i:i + length]
		out[: len(chunk)] += chunk
	return out


def normalize(x, peak=0.89):
	m = np.max(np.abs(x))
	return x * (peak / m) if m > 0 else x


def fade_out(x, dur=0.01):
	n = min(len(x), secs(dur))
	x = x.copy()
	x[-n:] *= np.linspace(1.0, 0.0, n)
	return x


def write_wav(path, x):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	data = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
	with wave.open(path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(data.tobytes())


def reverb_ir(rng, dur=1.6, tau=0.45, bright=4500.0):
	n = secs(dur)
	noise = rng.standard_normal(n)
	noise = fft_filter(noise, lo=200.0, hi=bright)
	ir = noise * env_exp(n, tau, attack=0.01)
	ir[: secs(0.012)] = 0.0  # pre-delay
	ir /= np.sqrt(np.sum(ir ** 2))
	return ir


def add_reverb(x, rng, wet=0.25, **kw):
	ir = reverb_ir(rng, **kw)
	y = fft_convolve(x, ir) * wet
	y[: len(x)] += x
	return y


# --------------------------------------------------------------------------
# Instruments
# --------------------------------------------------------------------------

_KORA_CACHE = {}


def _karplus(freq, dur, rng, bright, damping):
	"""Karplus-Strong string, vectorized one period at a time. Returns samples
	at the nearest integer delay; the caller resamples to the exact pitch."""
	n_total = secs(dur)
	period = max(2, int(SR / freq))
	# Excitation: noise, softened by brightness, with a pluck-position comb.
	exc = rng.uniform(-1.0, 1.0, period)
	if bright < 1.0:
		k = 1.0 - bright
		for _ in range(2):
			exc = (1 - k) * exc + k * np.roll(exc, 1)
	pp = max(1, int(period * 0.13))
	exc = exc - np.roll(exc, pp) * 0.8
	exc -= exc.mean()
	out = np.zeros(n_total + period + 1)
	out[:period] = exc
	# y[n] = damping * (0.5 * y[n-P] + 0.5 * y[n-P-1])
	pos = period
	while pos < len(out):
		end = min(pos + period, len(out))
		cur = out[pos - period:end - period]
		prev = out[pos - period - 1:end - period - 1] if pos - period - 1 >= 0 else np.concatenate(([0.0], out[:end - period - 1]))
		out[pos:end] = damping * 0.5 * (cur + prev)
		pos = end
	return out[:n_total], SR / (period + 0.5)


def kora_note(midi, dur=2.5, vel=1.0, seed=0, bright=0.85):
	"""Plucked kora string: bright noise attack + KS decay + body resonance."""
	key = (midi, round(dur, 3), seed, round(bright, 2))
	if key not in _KORA_CACHE:
		rng = np.random.default_rng(1000 + midi * 7 + seed)
		f = midi_hz(midi)
		# Higher strings decay faster.
		damping = 0.9985 - 0.0012 * max(0, (midi - 55)) / 24.0
		raw, f_actual = _karplus(f, dur * 1.1 + 0.05, rng, bright, damping)
		note = resample(raw, f / f_actual)[: secs(dur)]
		n = len(note)
		# Bright "tick" of the fingernail on the string.
		tick = rng.standard_normal(secs(0.012))
		tick = fft_filter(tick, lo=2500.0) * env_exp(len(tick), 0.003, attack=0.0005)
		note[: len(tick)] += tick * 0.25
		# Gentle fade to avoid cut-off clicks.
		note = note * np.minimum(1.0, np.linspace(6.0, 0.0, n))
		_KORA_CACHE[key] = note / (np.max(np.abs(note)) + 1e-9)
	return _KORA_CACHE[key] * vel


def kora_body(x, rng):
	"""Calabash body resonance: convolve with a short bank of decaying modes."""
	n = secs(0.12)
	t = np.arange(n) / SR
	ir = np.zeros(n)
	ir[0] = 1.0
	for f, a, tau in ((118.0, 0.020, 0.05), (235.0, 0.016, 0.035), (410.0, 0.010, 0.02), (1250.0, 0.006, 0.008)):
		ir += a * np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
	return fft_convolve(x, ir)


def membrane(freq, dur, ratios, amps, taus, drop=0.0, drop_tau=0.03):
	"""Sum of decaying sine modes with an optional pitch drop at the attack."""
	n = secs(dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for r, a, tau in zip(ratios, amps, taus):
		inst = freq * r * (1.0 + drop * np.exp(-t / drop_tau))
		phase = 2 * np.pi * np.cumsum(inst) / SR
		out += a * np.sin(phase) * np.exp(-t / tau)
	return out


def djembe(stroke, rng, vel=1.0):
	if stroke == "B":  # bass: centre of the head, deep and round
		s = membrane(72.0, 0.45, (1.0, 1.52, 2.1), (1.0, 0.3, 0.12), (0.18, 0.09, 0.05), drop=0.35)
		thump = fft_filter(rng.standard_normal(secs(0.05)), hi=400.0) * env_exp(secs(0.05), 0.012)
		s[: len(thump)] += thump * 0.5
	elif stroke == "T":  # tone: edge, open and ringing
		s = membrane(330.0, 0.3, (1.0, 1.59, 2.14, 2.65), (1.0, 0.45, 0.25, 0.12), (0.12, 0.07, 0.05, 0.03), drop=0.05)
		nz = fft_filter(rng.standard_normal(secs(0.04)), lo=800.0, hi=4000.0) * env_exp(secs(0.04), 0.008)
		s[: len(nz)] += nz * 0.3
	else:  # "S" slap: sharp, crackling
		n = secs(0.18)
		s = membrane(410.0, 0.18, (1.0, 1.7, 2.9), (0.5, 0.3, 0.2), (0.05, 0.03, 0.02))
		nz = fft_filter(rng.standard_normal(n), lo=1400.0, hi=6000.0) * env_exp(n, 0.035, attack=0.0008)
		s += nz * 1.4
	return s / (np.max(np.abs(s)) + 1e-9) * vel


def dundun(rng, freq=58.0, vel=1.0):
	s = membrane(freq, 0.7, (1.0, 1.5, 2.0), (1.0, 0.25, 0.1), (0.3, 0.12, 0.06), drop=0.25)
	stick = fft_filter(rng.standard_normal(secs(0.02)), lo=1000.0) * env_exp(secs(0.02), 0.004)
	s[: len(stick)] += stick * 0.25
	return s / np.max(np.abs(s)) * vel


def balafon(midi, rng, vel=1.0, dur=0.9):
	"""Wooden bar over a gourd: fast-decaying inharmonic partials + a light buzz."""
	f = midi_hz(midi)
	s = membrane(f, dur, (1.0, 3.93, 9.2), (1.0, 0.35, 0.12), (0.22, 0.05, 0.015))
	n = len(s)
	t = np.arange(n) / SR
	# Gourd mirliton buzz: slightly amplitude-modulated noise band.
	buzz = fft_filter(rng.standard_normal(n), lo=f * 2, hi=f * 8) * np.exp(-t / 0.08) * 0.12
	s += buzz * (0.5 + 0.5 * np.sin(2 * np.pi * f * t))
	click = fft_filter(rng.standard_normal(secs(0.006)), lo=2000.0) * env_exp(secs(0.006), 0.0015)
	s[: len(click)] += click * 0.4
	return s / (np.max(np.abs(s)) + 1e-9) * vel


def shekere(rng, vel=1.0, dur=0.09):
	n = secs(dur)
	s = fft_filter(rng.standard_normal(n), lo=3500.0, hi=9000.0)
	e = env_exp(n, dur * 0.3, attack=0.006)
	return s * e / (np.max(np.abs(s * e)) + 1e-9) * vel


def siwa_horn(midi, dur, rng, bend=True, vel=1.0):
	"""Side-blown ivory horn: additive tone with a breathy, swelling attack."""
	n = secs(dur)
	t = np.arange(n) / SR
	f0 = midi_hz(midi)
	inst = f0 * (1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.minimum(1.0, t / 0.5))
	if bend:
		inst *= 1.0 - 0.06 * np.exp(-t / 0.08)  # lip up into the note
	phase = 2 * np.pi * np.cumsum(inst) / SR
	tone = np.zeros(n)
	for k in range(1, 9):
		# Formant around the 2nd-3rd harmonic: warm and hollow.
		amp = (1.0 / k ** 1.3) * (1.4 if k in (2, 3) else 1.0) * (0.5 if k % 2 == 0 and k > 4 else 1.0)
		tone += amp * np.sin(k * phase)
	breath = fft_filter(rng.standard_normal(n), lo=f0 * 1.5, hi=f0 * 6) * 0.08
	env = np.minimum(1.0, t / 0.18) ** 1.5
	rel = secs(0.35)
	env[-rel:] *= np.linspace(1.0, 0.0, rel) ** 1.5
	s = (tone + breath) * env
	s = fft_filter(s, hi=2600.0)
	return s / (np.max(np.abs(s)) + 1e-9) * vel


def bell(freq, dur, ratios=(1.0, 2.4, 4.1, 5.43, 6.8), taus=(0.9, 0.5, 0.25, 0.15, 0.08)):
	n = secs(dur)
	t = np.arange(n) / SR
	s = np.zeros(n)
	for i, (r, tau) in enumerate(zip(ratios, taus)):
		s += (1.0 / (i + 1)) * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / tau)
	a = secs(0.002)
	s[:a] *= np.linspace(0, 1, a)
	return s / np.max(np.abs(s))


def clink(rng, base=2300.0, dur=0.35):
	n = secs(dur)
	t = np.arange(n) / SR
	s = np.zeros(n)
	for r, a, tau in ((1.0, 1.0, 0.09), (1.52, 0.7, 0.07), (2.31, 0.5, 0.05), (2.97, 0.35, 0.04), (4.1, 0.2, 0.025)):
		f = base * r * (1.0 + rng.uniform(-0.01, 0.01))
		s += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
	hit = fft_filter(rng.standard_normal(secs(0.004)), lo=3000.0) * 0.5
	s[: len(hit)] += hit
	a = secs(0.0008)
	s[:a] *= np.linspace(0, 1, a)
	return s / np.max(np.abs(s))


# --------------------------------------------------------------------------
# Music
# --------------------------------------------------------------------------

# Kora-flavoured modes (MIDI offsets from the tonic). Sauta ~ Lydian,
# Hardino ~ major, Silaba ~ Mixolydian-ish, Sahel pentatonic ~ minor pentatonic.
SCALES = {
	"sauta": [0, 2, 4, 6, 7, 9, 11],
	"hardino": [0, 2, 4, 5, 7, 9, 11],
	"silaba": [0, 2, 4, 5, 7, 9, 10],
	"sahel_penta": [0, 3, 5, 7, 10],
}


def degree(tonic, scale, d):
	"""MIDI note of scale degree d (0-based, may be negative or > len)."""
	sc = SCALES[scale]
	octave, idx = divmod(d, len(sc))
	return tonic + 12 * octave + sc[idx]


class Track:
	def __init__(self, bpm, bars, pulses_per_bar=12, seed=0):
		# bpm counts dotted-quarter beats; a 12-pulse bar = 4 beats of 3 pulses.
		self.pulse = 60.0 / bpm / 3.0
		self.bars = bars
		self.ppb = pulses_per_bar
		self.length = secs(self.pulse * pulses_per_bar * bars)
		self.tail = secs(5.0)
		self.kora = np.zeros(self.length + self.tail)
		self.perc = np.zeros(self.length + self.tail)
		self.other = np.zeros(self.length + self.tail)
		self.rng = np.random.default_rng(seed)

	def at(self, bar, pulse):
		"""Sample index of (bar, pulse), with a tiny humanizing jitter."""
		# 60 ms offset: the loop seam falls between notes, not on an attack.
		t = (bar * self.ppb + pulse) * self.pulse + 0.06
		t += self.rng.normal(0.0, 0.004)
		return max(0, secs(t))

	def pluck(self, bar, pulse, midi, vel=0.7, dur=2.5, bright=0.85):
		add(self.kora, kora_note(midi, dur, vel, seed=int(self.rng.integers(0, 3)), bright=bright), self.at(bar, pulse))

	def drum(self, bar, pulse, stroke, vel=0.7):
		add(self.perc, djembe(stroke, self.rng, vel), self.at(bar, pulse))

	def mix(self, kora_gain=1.0, perc_gain=1.0, other_gain=1.0, wet=0.22, drone=None):
		k = kora_body(self.kora, self.rng) * kora_gain
		dry = np.zeros(len(k) + len(self.perc))
		dry[: len(k)] += k
		dry[: len(self.perc)] += self.perc * perc_gain
		dry[: len(self.other)] += self.other * other_gain
		wetmix = add_reverb(dry, self.rng, wet=wet)
		loop = fold(wetmix, self.length)
		if drone is not None:
			loop += drone
		return loop

	def periodic_drone(self, midis, gain=0.15, swell_cycles=2):
		"""A drone whose frequencies are quantized so that each partial completes
		a whole number of cycles per loop: it is seamless by construction."""
		n = self.length
		L = n / SR
		t = np.arange(n) / SR
		out = np.zeros(n)
		for m in midis:
			f = round(midi_hz(m) * L) / L
			for k, a in ((1, 1.0), (2, 0.45), (3, 0.25), (4, 0.12), (5, 0.06)):
				fk = round(midi_hz(m) * k * L) / L
				out += a * np.sin(2 * np.pi * fk * t)
		swell = 0.7 + 0.3 * np.sin(2 * np.pi * swell_cycles * t / L - np.pi / 2)
		out *= swell
		out = fft_filter(out, hi=1400.0)
		return out / np.max(np.abs(out)) * gain


def music_menu():
	"""Slow, stately kora in Hardino (major-ish) on F; bass alternation + melody."""
	tr = Track(bpm=58, bars=10, seed=11)
	tonic = 53  # F3
	prog = [0, 0, 3, 0, 4, 3, 0, 4, 3, 0]  # scale-degree roots per bar
	melody = [
		[(0, 7), (6, 9), (9, 8)], [(0, 7), (6, 6), (9, 4)],
		[(0, 8), (3, 9), (6, 10), (9, 8)], [(0, 7), (6, 4)],
		[(0, 8), (6, 6), (9, 4)], [(0, 5), (3, 6), (6, 8), (9, 9)],
		[(0, 7), (6, 11), (9, 9)], [(0, 8), (6, 6)],
		[(0, 5), (4, 4), (6, 5), (9, 6)], [(0, 7), (6, 4), (9, 2)],
	]
	for bar in range(tr.bars):
		r = prog[bar]
		tr.pluck(bar, 0, degree(tonic - 12, "hardino", r), 0.85, 3.5, bright=0.7)
		tr.pluck(bar, 6, degree(tonic - 12, "hardino", r + 4), 0.6, 3.0, bright=0.7)
		# Soft broken chord in the middle register (kumbengo-like).
		for p, d in ((3, r + 2), (4, r + 4), (9, r + 2), (10, r + 4)):
			tr.pluck(bar, p, degree(tonic, "hardino", d), 0.32, 2.0, bright=0.75)
		for p, d in melody[bar]:
			tr.pluck(bar, p, degree(tonic, "hardino", d), 0.75, 3.0)
		# A little birimintingo run in bars 3 and 7.
		if bar in (3, 7):
			for i, d in enumerate((11, 10, 9, 8, 7)):
				tr.pluck(bar, 8 + i * 0.5, degree(tonic, "hardino", d), 0.45, 1.5)
	return tr.mix(wet=0.35, drone=tr.periodic_drone([tonic - 12], gain=0.05, swell_cycles=5))


def music_sand():
	"""Sparse kora + light djembe, Sahel pentatonic on A."""
	tr = Track(bpm=84, bars=14, seed=22)
	tonic = 57  # A3
	s = "sahel_penta"
	motifs = [
		[(0, 5), (3, 4), (5, 3), (6, 2)],
		[(0, 3), (2, 2), (3, 1), (6, 0)],
		[(0, 7), (3, 6), (6, 5), (8, 6), (9, 4)],
		[(0, 2), (6, 0)],
	]
	for bar in range(tr.bars):
		# Bass pulse on beats 1 and 3 (open fifths).
		tr.pluck(bar, 0, degree(tonic - 12, s, 0), 0.8, 3.0, bright=0.65)
		if bar % 2 == 1:
			tr.pluck(bar, 6, degree(tonic - 12, s, 3), 0.55, 2.5, bright=0.65)
		# Melodic motif every other bar, with an answer on odd bars.
		if bar % 2 == 0:
			for p, d in motifs[(bar // 2) % len(motifs)]:
				tr.pluck(bar, p, degree(tonic, s, d), 0.7, 2.6)
		else:
			tr.pluck(bar, 3, degree(tonic, s, 2), 0.35, 2.0)
			tr.pluck(bar, 9, degree(tonic, s, 4), 0.35, 2.0)
		# Light djembe: bass on 1, a couple of tones, a slap on the last beat.
		tr.drum(bar, 0, "B", 0.8)
		tr.drum(bar, 4, "T", 0.35)
		tr.drum(bar, 5, "T", 0.4)
		if bar % 2 == 1:
			tr.drum(bar, 9, "S", 0.45)
			tr.drum(bar, 11, "T", 0.3)
		for p in (3, 9):
			add(tr.other, shekere(tr.rng, 0.18), tr.at(bar, p))
	return tr.mix(perc_gain=0.8, other_gain=0.9, wet=0.28)


def music_mali():
	"""Fuller: kora ostinato (kumbengo), balafon melody, full djembe groove. Sauta on F."""
	tr = Track(bpm=100, bars=16, seed=33)
	tonic = 53  # F3
	s = "sauta"
	prog = [0, 0, 4, 3]  # I I V IV cycle of bars
	# Kumbengo: 12-pulse ostinato, relative scale degrees (None = rest).
	ost = [0, 4, 7, 2, 4, 9, 0, 4, 7, 2, 6, 9]
	bassline = {0: 0, 3: 4, 6: -3, 9: 4}
	for bar in range(tr.bars):
		r = prog[bar % 4]
		for p, d in enumerate(ost):
			tr.pluck(bar, p, degree(tonic, s, r + d), 0.42 if p % 3 else 0.55, 1.6)
		for p, d in bassline.items():
			tr.pluck(bar, p, degree(tonic - 12, s, r + d), 0.7, 2.2, bright=0.6)
	# Balafon melody in the second half of the loop.
	mel = [
		(0, 9), (2, 10), (3, 11), (6, 9), (8, 8), (9, 7),
		(0, 8), (3, 9), (5, 8), (6, 7), (9, 4), (11, 5),
	]
	for bar in range(8, 16):
		half = (bar % 2) * 6
		for p, d in mel[half:half + 6]:
			add(tr.other, balafon(degree(tonic + 12, s, d - 7 + prog[bar % 4]), tr.rng, 0.55), tr.at(bar, p))
	# Djembe accompaniment + solo-ish call on the last bar of each 4-bar phrase.
	groove = "B.TT.SB.TS.S"
	call = "SSS.SS.TT.B."
	for bar in range(tr.bars):
		pat = call if bar % 4 == 3 else groove
		for p, st in enumerate(pat):
			if st != ".":
				tr.drum(bar, p, st, 0.75 if st == "B" else 0.5)
		for p in (0, 6):
			add(tr.other, dundun(tr.rng, vel=0.55), tr.at(bar, p))
		for p in range(12):
			add(tr.other, shekere(tr.rng, 0.2 if p % 3 == 0 else 0.1), tr.at(bar, p))
	return tr.mix(kora_gain=0.9, perc_gain=0.85, other_gain=0.85, wet=0.2)


def music_hajj():
	"""Majestic: drone, slow kora chords, balafon theme, siwa horns, djembe march. D Silaba."""
	tr = Track(bpm=76, bars=12, seed=44)
	tonic = 50  # D3
	s = "silaba"
	prog = [0, 0, 6, 3, 0, 4, 6, 0, 3, 4, 6, 0]
	for bar in range(tr.bars):
		r = prog[bar]
		# Broad strummed chord on 1, answered on 3.
		for i, d in enumerate((0, 4, 7, 9)):
			tr.pluck(bar, 0 + i * 0.25, degree(tonic, s, r + d), 0.5, 3.0)
		for i, d in enumerate((2, 4, 7)):
			tr.pluck(bar, 6 + i * 0.25, degree(tonic, s, r + d), 0.35, 2.6)
		tr.pluck(bar, 0, degree(tonic - 12, s, r), 0.8, 3.5, bright=0.6)
		tr.pluck(bar, 6, degree(tonic - 12, s, r + 4), 0.55, 3.0, bright=0.6)
		# Djembe march: strong bass + tone pattern, slaps on the backbeat.
		for p, st in enumerate("B..T.SB.TS.T"):
			if st != ".":
				tr.drum(bar, p, st, 0.8 if st == "B" else 0.5)
		add(tr.other, dundun(tr.rng, 52.0, 0.7), tr.at(bar, 0))
		add(tr.other, dundun(tr.rng, 52.0, 0.45), tr.at(bar, 7))
		for p in (2, 5, 8, 11):
			add(tr.other, shekere(tr.rng, 0.15), tr.at(bar, p))
	theme = [(0, 7), (3, 8), (6, 9), (9, 11), (0, 12), (6, 11), (9, 9), (0, 8), (3, 9), (6, 7)]
	theme_bars = [4, 4, 4, 4, 5, 5, 5, 6, 6, 6]
	for (p, d), bar in zip(theme, theme_bars):
		add(tr.other, balafon(degree(tonic + 12, s, d - 7), tr.rng, 0.6), tr.at(bar, p))
	# Siwa horn calls near the start and at the climax.
	for bar, m in ((0, tonic + 12), (8, tonic + 19), (10, tonic + 12)):
		add(tr.other, siwa_horn(m, tr.pulse * 9, tr.rng, vel=0.55), tr.at(bar, 0))
	drone = tr.periodic_drone([tonic - 12, tonic - 5], gain=0.13, swell_cycles=3)
	return tr.mix(kora_gain=0.9, perc_gain=0.8, other_gain=0.8, wet=0.3, drone=drone)


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------

def buf(dur):
	return np.zeros(secs(dur))


def sfx_hit(rng):
	b = buf(0.22)
	add(b, membrane(140.0, 0.2, (1.0, 1.7), (1.0, 0.4), (0.05, 0.03), drop=0.6, drop_tau=0.01), 0)
	crack = fft_filter(rng.standard_normal(secs(0.08)), lo=1200.0, hi=7000.0) * env_exp(secs(0.08), 0.015, attack=0.0005)
	add(b, crack, 0, 0.9)
	return b


def sfx_death(rng):
	b = buf(0.9)
	n = secs(0.7)
	t = np.arange(n) / SR
	f = 180.0 * np.exp(-t * 1.6)
	groan = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR)
	groan *= np.minimum(1, t / 0.03) * np.exp(-t / 0.3)
	add(b, groan, 0, 0.6)
	add(b, djembe("B", rng, 1.0), secs(0.18))
	add(b, fft_filter(rng.standard_normal(secs(0.3)), hi=900.0) * env_exp(secs(0.3), 0.08), secs(0.18), 0.5)
	return b


def sfx_build_place(rng):
	b = buf(0.6)
	mud = membrane(62.0, 0.4, (1.0, 1.6), (1.0, 0.3), (0.12, 0.05), drop=0.4)
	mud += fft_filter(rng.standard_normal(len(mud)), hi=500.0) * env_exp(len(mud), 0.06) * 0.8
	add(b, mud, 0, 1.0)
	add(b, balafon(79, rng, 0.45, dur=0.3), secs(0.07))
	add(b, balafon(84, rng, 0.35, dur=0.3), secs(0.16))
	return b


def sfx_research_done(rng):
	b = buf(1.8)
	for i, m in enumerate((65, 69, 72, 76, 77)):
		add(b, kora_note(m, 1.4, 0.8), secs(i * 0.09))
	return kora_body(b, rng)[: len(b)]


def sfx_age_up(rng):
	b = buf(3.0)
	# Accelerating djembe roll into a big bass stroke.
	t, gap = 0.0, 0.14
	while t < 0.95:
		add(b, djembe("T" if int(t * 100) % 2 else "S", rng, 0.35 + 0.5 * t), secs(t))
		t += gap
		gap = max(0.045, gap * 0.86)
	add(b, djembe("B", rng, 1.0), secs(1.0))
	add(b, dundun(rng, 55.0, 1.0), secs(1.0))
	add(b, siwa_horn(62, 1.8, rng, vel=0.8), secs(1.0))
	add(b, siwa_horn(69, 1.8, rng, vel=0.45), secs(1.02))
	return b


def sfx_coin(rng):
	b = buf(0.4)
	add(b, clink(rng, 2350.0, 0.3), 0)
	add(b, clink(rng, 2900.0, 0.3), secs(0.06), 0.6)
	return b


def sfx_caravan_deliver(rng):
	b = buf(1.4)
	add(b, bell(620.0, 1.2), 0, 0.8)
	add(b, bell(620.0, 1.0), secs(0.32), 0.55)
	for i in range(4):
		add(b, clink(rng, 2200.0 + 300 * rng.random(), 0.25), secs(0.5 + i * 0.07), 0.4)
	return b


def sfx_dilemma_open(rng):
	b = buf(2.2)
	add(b, dundun(rng, 48.0, 1.0), 0)
	# Minor-ish kora chord, strummed.
	for i, m in enumerate((50, 57, 62, 65, 69)):
		add(b, kora_note(m, 1.8, 0.55), secs(0.08 + i * 0.035))
	return kora_body(b, rng)[: len(b)]


def sfx_convert(rng):
	b = buf(1.5)
	notes = [degree(57, "sahel_penta", d) for d in range(0, 11)]
	for i, m in enumerate(notes):
		add(b, kora_note(m, 1.0, 0.45 + 0.04 * i), secs(i * 0.045))
	return kora_body(b, rng)[: len(b)]


def sfx_click(rng):
	b = buf(0.07)
	s = membrane(1500.0, 0.05, (1.0, 2.7), (1.0, 0.4), (0.008, 0.004))
	s += fft_filter(rng.standard_normal(len(s)), lo=2500.0) * env_exp(len(s), 0.003, attack=0.0003) * 0.3
	add(b, s, 0)
	return b


def sfx_victory(rng):
	b = buf(4.0)
	for i, t in enumerate((0.0, 0.18, 0.36)):
		add(b, djembe("S", rng, 0.6), secs(t))
	add(b, djembe("B", rng, 1.0), secs(0.54))
	add(b, dundun(rng, 55.0, 1.0), secs(0.54))
	for i, m in enumerate((62, 66, 69, 74, 78, 81)):
		add(b, kora_note(m, 2.4, 0.6), secs(0.54 + i * 0.07))
	add(b, siwa_horn(62, 2.6, rng, vel=0.6), secs(0.6))
	add(b, siwa_horn(69, 2.4, rng, vel=0.4), secs(0.8))
	for t in (1.4, 1.6, 1.8):
		add(b, djembe("T", rng, 0.5), secs(t))
	add(b, djembe("B", rng, 0.9), secs(2.0))
	return b


def sfx_defeat(rng):
	b = buf(4.0)
	for i, m in enumerate((69, 65, 62, 60, 57, 53)):
		add(b, kora_note(m, 2.2, 0.55, bright=0.6), secs(i * 0.32))
	add(b, dundun(rng, 45.0, 0.9), 0)
	add(b, dundun(rng, 42.0, 0.8), secs(1.28))
	add(b, siwa_horn(45, 2.2, rng, bend=False, vel=0.4), secs(1.6))
	return b


def sfx_horn(rng):
	b = buf(2.6)
	add(b, siwa_horn(55, 2.4, rng, vel=1.0), 0)
	add(b, siwa_horn(62, 1.4, rng, vel=0.3), secs(0.9))
	return b


def sfx_error(rng):
	b = buf(0.25)
	s = membrane(110.0, 0.2, (1.0, 1.4), (1.0, 0.5), (0.05, 0.03), drop=0.2)
	s += fft_filter(rng.standard_normal(len(s)), hi=700.0) * env_exp(len(s), 0.025) * 0.6
	add(b, s, 0)
	return b


SFX = {
	"hit": sfx_hit, "death": sfx_death, "build_place": sfx_build_place,
	"research_done": sfx_research_done, "age_up": sfx_age_up, "coin": sfx_coin,
	"caravan_deliver": sfx_caravan_deliver, "dilemma_open": sfx_dilemma_open,
	"convert": sfx_convert, "click": sfx_click, "victory": sfx_victory,
	"defeat": sfx_defeat, "horn": sfx_horn, "error": sfx_error,
}

MUSIC = {
	"menu": music_menu, "sand_chiefdoms": music_sand,
	"mali_ascendancy": music_mali, "golden_hajj": music_hajj,
}

# Peak targets: loud, punchy sfx; music a little lower so sfx sit on top.
SFX_PEAK = {"click": 0.6, "coin": 0.75, "hit": 0.85, "horn": 0.6}


def stats(name, x):
	peak = np.max(np.abs(x))
	rms = np.sqrt(np.mean(x ** 2))
	return "%-16s %6.2fs  peak %5.1f dBFS  rms %5.1f dBFS" % (
		name, len(x) / SR, 20 * np.log10(peak + 1e-12), 20 * np.log10(rms + 1e-12))


def boundary_check(x):
	"""Jump across the loop seam compared with typical sample-to-sample steps."""
	d = np.abs(np.diff(x))
	seam = abs(x[0] - x[-1])
	# Second difference at the seam vs. inside (derivative continuity).
	dd_seam = abs((x[0] - x[-1]) - (x[-1] - x[-2]))
	dd = np.abs(np.diff(x, 2))
	return seam, np.percentile(d, 99), dd_seam, np.percentile(dd, 99)


def preview(path, clips):
	from PIL import Image, ImageDraw
	w, h = 1100, 110
	img = Image.new("RGB", (w, h * len(clips)), (18, 16, 14))
	dr = ImageDraw.Draw(img)
	for i, (name, x) in enumerate(clips):
		y0 = i * h
		# Waveform (min/max per column) on the left 700 px.
		cols = 700
		step = max(1, len(x) // cols)
		for c in range(cols):
			seg = x[c * step:(c + 1) * step]
			if len(seg) == 0:
				break
			lo, hi = seg.min(), seg.max()
			dr.line([(c, y0 + h / 2 - hi * h * 0.45), (c, y0 + h / 2 - lo * h * 0.45)], fill=(230, 180, 60))
		dr.line([(0, y0 + h / 2 - 0.89 * h * 0.45), (700, y0 + h / 2 - 0.89 * h * 0.45)], fill=(120, 40, 40))
		# Spectrogram of the first 3 s on the right.
		seg = x[: secs(3.0)]
		win = 512
		hop = max(1, (len(seg) - win) // 380) if len(seg) > win else 1
		frames = [seg[j:j + win] * np.hanning(win) for j in range(0, max(1, len(seg) - win), hop)][:380]
		if frames:
			S = np.abs(np.fft.rfft(np.array(frames), axis=1))[:, :256]
			S = 20 * np.log10(S + 1e-6)
			S = np.clip((S + 30) / 70, 0, 1)
			for fx, col in enumerate(S):
				for fy in range(0, 256, 3):
					v = int(col[fy] * 255)
					dr.point((710 + fx, y0 + h - 5 - fy * (h - 10) // 256), fill=(v, int(v * 0.8), 40))
		dr.text((4, y0 + 2), name, fill=(255, 255, 255))
		dr.line([(0, y0 + h - 1), (w, y0 + h - 1)], fill=(60, 60, 60))
	img.save(path)


def main():
	prev_dir = None
	if "--preview" in sys.argv:
		prev_dir = sys.argv[sys.argv.index("--preview") + 1]
	clips = []
	print("== music ==")
	for name, fn in MUSIC.items():
		x = normalize(fn(), 0.84)
		write_wav(os.path.join(OUT, "music", name + ".wav"), x)
		seam, d99, dd_seam, dd99 = boundary_check(x)
		print(stats(name, x), "| seam jump %.4f (p99 step %.4f), seam curvature %.4f (p99 %.4f)" % (seam, d99, dd_seam, dd99))
		if seam > d99 or dd_seam > dd99:
			print("   WARNING: loop seam of %s may click" % name)
		clips.append((name, x))
	print("== sfx ==")
	for name, fn in SFX.items():
		rng = np.random.default_rng(sum(map(ord, name)))
		x = fn(rng)
		# Trim trailing near-silence, then a short fade.
		nz = np.nonzero(np.abs(x) > 1e-4 * np.max(np.abs(x)))[0]
		x = x[: nz[-1] + 1] if len(nz) else x
		x = fade_out(normalize(x, SFX_PEAK.get(name, 0.89)), 0.02)
		write_wav(os.path.join(OUT, "sfx", name + ".wav"), x)
		print(stats(name, x))
		clips.append((name, x))
	total = 0
	for root, _, files in os.walk(OUT):
		for f in files:
			if f.endswith(".wav"):
				total += os.path.getsize(os.path.join(root, f))
	print("total wav size: %.2f MB" % (total / 1e6))
	if prev_dir:
		os.makedirs(prev_dir, exist_ok=True)
		preview(os.path.join(prev_dir, "music_preview.png"), clips[:4])
		preview(os.path.join(prev_dir, "sfx_preview.png"), clips[4:])
		print("previews in", prev_dir)


if __name__ == "__main__":
	main()
