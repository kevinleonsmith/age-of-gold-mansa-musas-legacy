#!/usr/bin/env python3
"""Generate the main-menu title art for Age of Gold (Pillow, deterministic).

assets/menu/title_bg.png  1152x648: dusk over the Niger, a golden sun, sand
                          dunes and the silhouette of the Great Mosque of Djenne.
assets/menu/emblem.png    96x96 gold sun / crown emblem for the title and screens.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Age of Gold Game")
OUT_DIR = os.path.join(ROOT, "assets", "menu")

W, H = 1152, 648
HORIZON = 430

INDIGO = (22, 16, 48)
PURPLE = (74, 34, 78)
LATERITE = (170, 72, 36)
GOLD = (255, 200, 70)
SILHOUETTE = (34, 16, 20)
SILHOUETTE_LIGHT = (58, 28, 26)


def lerp(a, b, t):
	return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def sky_color(y):
	t = y / HORIZON
	stops = [(0.0, INDIGO), (0.45, PURPLE), (0.78, LATERITE), (1.0, GOLD)]
	for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
		if t <= t1:
			return lerp(c0, c1, (t - t0) / (t1 - t0))
	return stops[-1][1]


def draw_sky(im):
	d = ImageDraw.Draw(im)
	for y in range(HORIZON + 40):
		d.line([(0, y), (W, y)], fill=sky_color(min(y, HORIZON)))
	rng = random.Random(7)
	for _ in range(140):
		x, y = rng.randrange(W), rng.randrange(0, 200)
		b = rng.randrange(150, 255)
		alpha_t = 1.0 - y / 220
		c = lerp(sky_color(y), (b, b, int(b * 0.9)), alpha_t)
		d.point((x, y), fill=c)
		if rng.random() < 0.12:
			d.point((x + 1, y), fill=c)


def draw_sun(im):
	cx, cy, r = 830, HORIZON - 40, 95
	glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	g = ImageDraw.Draw(glow)
	for i in range(10, 0, -1):
		rr = r + i * 22
		g.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 190, 60, 10))
	glow = glow.filter(ImageFilter.GaussianBlur(18))
	im.alpha_composite(glow)
	d = ImageDraw.Draw(im)
	d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 214, 96, 255))
	d.ellipse([cx - r + 12, cy - r + 12, cx + r - 12, cy + r - 12], fill=(255, 228, 130, 255))
	# horizontal haze bands across the sun
	for i, y in enumerate(range(cy + 20, cy + r, 14)):
		d.line([(cx - r, y), (cx + r, y)], fill=sky_color(min(y, HORIZON)) + (255,), width=3 + i)


def dune(d, base, amp, freq, phase, color):
	pts = [(0, H)]
	for x in range(0, W + 8, 8):
		y = base + amp * math.sin(x * freq + phase) + amp * 0.4 * math.sin(x * freq * 2.3 + phase * 1.7)
		pts.append((x, y))
	pts.append((W, H))
	d.polygon(pts, fill=color)


def draw_ground(im):
	d = ImageDraw.Draw(im)
	dune(d, HORIZON + 6, 6, 0.006, 0.5, (150, 78, 44, 255))
	# river Niger: a gold reflecting band
	d.polygon([(0, HORIZON + 40), (W, HORIZON + 22), (W, HORIZON + 44), (0, HORIZON + 66)], fill=(220, 150, 70, 255))
	for i in range(8):
		y = HORIZON + 34 + i * 3
		d.line([(760 - i * 20, y), (900 + i * 20, y - 2)], fill=(255, 215, 110, 255), width=1)
	dune(d, HORIZON + 90, 16, 0.004, 2.1, (120, 54, 34, 255))
	dune(d, HORIZON + 150, 22, 0.0035, 4.0, (84, 36, 30, 255))
	dune(d, HORIZON + 200, 14, 0.005, 1.0, (52, 24, 26, 255))


def tower(d, x, top, bottom, width, color):
	"""A tapered Djenne tower with a rounded cap and toron beams."""
	half_b = width / 2
	half_t = width / 2 - 4
	d.polygon([(x - half_b, bottom), (x - half_t, top + 8), (x + half_t, top + 8), (x + half_b, bottom)], fill=color)
	d.ellipse([x - half_t, top, x + half_t, top + 16], fill=color)
	d.polygon([(x - 3, top + 2), (x, top - 10), (x + 3, top + 2)], fill=color)  # finial
	d.ellipse([x - 3, top - 16, x + 3, top - 10], fill=color)
	for y in range(int(top + 22), int(bottom - 10), 18):
		t = (y - top) / (bottom - top)
		hw = half_t + (half_b - half_t) * t
		d.line([(x - hw - 7, y), (x + hw + 7, y)], fill=color, width=3)


def draw_mosque(im):
	d = ImageDraw.Draw(im)
	base = HORIZON + 50
	left, right = 150, 610
	c = SILHOUETTE + (255,)
	# platform
	d.rectangle([left - 30, base - 18, right + 30, base + 6], fill=c)
	# main wall with buttresses
	d.rectangle([left, base - 130, right, base - 18], fill=c)
	for x in range(left, right + 1, 30):
		tower(d, x, base - 160, base - 18, 14, c)
	# three great towers on the qibla wall
	tower(d, left + 110, base - 245, base - 20, 46, c)
	tower(d, (left + right) // 2, base - 280, base - 20, 58, c)
	tower(d, right - 110, base - 245, base - 20, 46, c)
	# corner towers
	tower(d, left, base - 200, base - 18, 30, c)
	tower(d, right, base - 200, base - 18, 30, c)
	# doorway glow
	glow = SILHOUETTE_LIGHT + (255,)
	cx = (left + right) // 2
	d.rectangle([cx - 14, base - 60, cx + 14, base - 18], fill=glow)
	d.ellipse([cx - 14, base - 74, cx + 14, base - 46], fill=glow)
	d.rectangle([cx - 8, base - 50, cx + 8, base - 18], fill=(240, 170, 70, 255))
	d.ellipse([cx - 8, base - 60, cx + 8, base - 42], fill=(240, 170, 70, 255))
	# palms
	for px, h in [(70, 120), (690, 100), (730, 130)]:
		palm(d, px, base + 8, h, c)


def palm(d, x, ground, height, color):
	top = ground - height
	d.line([(x, ground), (x + 6, top)], fill=color, width=6)
	for ang in range(-160, 30, 32):
		a = math.radians(ang)
		ex, ey = x + 6 + 46 * math.cos(a), top + 26 * math.sin(a) + 14
		mx, my = x + 6 + 24 * math.cos(a), top + 18 * math.sin(a) - 4
		d.line([(x + 6, top), (mx, my), (ex, ey)], fill=color, width=4)


def draw_caravan(im):
	d = ImageDraw.Draw(im)
	c = (46, 20, 22, 255)
	y = HORIZON + 138
	for i, x in enumerate(range(820, 1110, 70)):
		yy = y + i * 3
		d.ellipse([x, yy - 20, x + 34, yy], fill=c)       # body
		d.ellipse([x + 10, yy - 30, x + 26, yy - 14], fill=c)  # hump
		d.line([(x + 32, yy - 14), (x + 42, yy - 30)], fill=c, width=5)  # neck
		d.ellipse([x + 38, yy - 36, x + 50, yy - 28], fill=c)  # head
		for lx in (x + 4, x + 12, x + 22, x + 30):
			d.line([(lx, yy - 4), (lx, yy + 16)], fill=c, width=3)
		d.polygon([(x + 12, yy - 30), (x + 18, yy - 46), (x + 24, yy - 30)], fill=c)  # rider


def vignette(im):
	v = Image.new("RGBA", (W, H), (0, 0, 0, 0))
	d = ImageDraw.Draw(v)
	for i in range(40):
		a = int(3 * i)
		d.rectangle([i * 4, i * 3, W - i * 4, H - i * 3], outline=(10, 6, 20, max(0, 120 - a)), width=4)
	v = v.filter(ImageFilter.GaussianBlur(20))
	im.alpha_composite(v)


def make_title_bg():
	im = Image.new("RGBA", (W, H), INDIGO + (255,))
	draw_sky(im)
	draw_sun(im)
	draw_ground(im)
	draw_mosque(im)
	draw_caravan(im)
	vignette(im)
	return im.convert("RGB")


def make_emblem():
	s = 96
	im = Image.new("RGBA", (s * 4, s * 4), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	c = s * 2
	for i in range(16):
		a = i * math.tau / 16
		r0, r1 = s * 1.1, s * (1.8 if i % 2 == 0 else 1.55)
		w = 0.13
		d.polygon([
			(c + r0 * math.cos(a - w), c + r0 * math.sin(a - w)),
			(c + r1 * math.cos(a), c + r1 * math.sin(a)),
			(c + r0 * math.cos(a + w), c + r0 * math.sin(a + w)),
		], fill=(255, 196, 60, 255))
	d.ellipse([c - s * 1.2, c - s * 1.2, c + s * 1.2, c + s * 1.2], fill=(120, 60, 20, 255))
	d.ellipse([c - s * 1.08, c - s * 1.08, c + s * 1.08, c + s * 1.08], fill=(255, 208, 80, 255))
	d.ellipse([c - s * 0.8, c - s * 0.8, c + s * 0.8, c + s * 0.8], fill=(236, 170, 44, 255))
	# small crown in the centre
	k = (110, 50, 18, 255)
	d.polygon([(c - 50, c + 30), (c - 56, c - 30), (c - 26, c), (c, c - 44), (c + 26, c), (c + 56, c - 30), (c + 50, c + 30)], fill=k)
	d.rectangle([c - 50, c + 30, c + 50, c + 44], fill=k)
	return im.resize((s, s), Image.LANCZOS)


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	make_title_bg().save(os.path.join(OUT_DIR, "title_bg.png"))
	make_emblem().save(os.path.join(OUT_DIR, "emblem.png"))
	print("wrote", OUT_DIR)


if __name__ == "__main__":
	main()
