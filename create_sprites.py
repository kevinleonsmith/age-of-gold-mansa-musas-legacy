#!/usr/bin/env python3
"""Generate placeholder pixel-art unit sprites and a terrain tile atlas
for the Age of Gold Godot project (Pillow). Deterministic (seeded)."""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(ROOT, "assets", "sprites")
TILESETS = os.path.join(ROOT, "assets", "tilesets")

OUT = (30, 20, 12, 255)  # dark outline


def new_sprite():
	return Image.new("RGBA", (32, 32), (0, 0, 0, 0))


def shadow(d, cx=16, cy=28, rx=10, ry=3):
	d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, 70))


# --- Units -------------------------------------------------------------------

def draw_player():
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d)
	# White robe (wide boubou) with gold trim
	d.polygon([(16, 9), (25, 28), (7, 28)], fill=(245, 242, 230, 255), outline=OUT)
	d.line([(16, 13), (16, 27)], fill=(218, 165, 32, 255))
	d.line([(8, 27), (24, 27)], fill=(218, 165, 32, 255))
	d.line([(10, 22), (22, 22)], fill=(218, 165, 32, 255))
	# Gold sash/arms
	d.rectangle([9, 15, 23, 17], fill=(230, 180, 30, 255), outline=OUT)
	# Gold staff/sceptre
	d.line([(26, 6), (26, 28)], fill=(120, 80, 20, 255), width=1)
	d.ellipse([24, 3, 28, 7], fill=(255, 215, 0, 255), outline=OUT)
	# Head
	d.ellipse([11, 4, 20, 13], fill=(110, 70, 40, 255), outline=OUT)
	# Gold crown / turban
	d.rectangle([11, 3, 20, 6], fill=(255, 205, 20, 255), outline=OUT)
	d.point([(12, 2), (15, 1), (16, 1), (19, 2)], fill=(255, 225, 60, 255))
	d.point([(15, 4)], fill=(200, 30, 30, 255))
	# eyes
	d.point([(14, 9), (17, 9)], fill=(20, 10, 5, 255))
	return im


def draw_enemy():
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d)
	# Spear (diagonal) behind body
	d.line([(4, 29), (27, 3)], fill=(100, 70, 40, 255), width=1)
	d.polygon([(27, 1), (30, 2), (26, 6)], fill=(200, 200, 210, 255), outline=OUT)
	# Dark red tunic
	d.polygon([(16, 10), (23, 28), (9, 28)], fill=(140, 20, 20, 255), outline=OUT)
	d.rectangle([9, 14, 23, 17], fill=(110, 15, 15, 255), outline=OUT)
	# Black belt
	d.line([(11, 21), (21, 21)], fill=(15, 10, 10, 255))
	# Black veiled head (litham)
	d.ellipse([11, 3, 21, 13], fill=(25, 22, 25, 255), outline=(0, 0, 0, 255))
	d.line([(13, 8), (19, 8)], fill=(150, 100, 70, 255))  # eye slit
	d.point([(14, 8), (18, 8)], fill=(250, 240, 200, 255))
	# Round shield
	d.ellipse([5, 15, 12, 22], fill=(80, 40, 20, 255), outline=OUT)
	d.point([(8, 18)], fill=(180, 30, 30, 255))
	return im


def draw_camel_lancer():
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d, cy=29, rx=13)
	tan = (205, 160, 100, 255)
	dtan = (160, 115, 65, 255)
	# Legs
	for x in (7, 10, 20, 23):
		d.line([(x, 22), (x, 29)], fill=dtan, width=2)
	# Body + hump
	d.ellipse([5, 15, 25, 24], fill=tan, outline=OUT)
	d.ellipse([10, 11, 19, 19], fill=tan, outline=OUT)
	# Neck + head (facing right)
	d.polygon([(23, 18), (27, 10), (29, 11), (26, 20)], fill=tan, outline=OUT)
	d.ellipse([25, 7, 31, 12], fill=tan, outline=OUT)
	d.point([(29, 9)], fill=OUT)
	# Saddle blanket
	d.rectangle([11, 14, 18, 18], fill=(200, 40, 40, 255), outline=OUT)
	# Rider: blue tunic
	d.rectangle([12, 6, 17, 14], fill=(40, 80, 190, 255), outline=OUT)
	d.ellipse([12, 1, 17, 6], fill=(110, 70, 40, 255), outline=OUT)
	d.line([(12, 2), (17, 2)], fill=(240, 240, 240, 255))  # white turban band
	# Lance forward
	d.line([(8, 12), (30, 3)], fill=(110, 75, 35, 255), width=1)
	d.polygon([(29, 2), (31, 2), (31, 4)], fill=(210, 210, 220, 255))
	d.point([(22, 6)], fill=(230, 200, 40, 255))  # pennant
	d.point([(23, 6), (22, 7)], fill=(230, 200, 40, 255))
	return im


def draw_griot():
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d)
	# Green robe with ochre trim
	d.polygon([(16, 10), (24, 28), (8, 28)], fill=(40, 130, 60, 255), outline=OUT)
	d.line([(9, 27), (23, 27)], fill=(200, 140, 40, 255))
	d.line([(12, 20), (20, 20)], fill=(200, 140, 40, 255))
	# Ochre shawl
	d.rectangle([10, 13, 22, 16], fill=(205, 145, 45, 255), outline=OUT)
	# Head + green cap
	d.ellipse([11, 4, 20, 13], fill=(110, 70, 40, 255), outline=OUT)
	d.pieslice([11, 2, 20, 10], 180, 360, fill=(30, 110, 50, 255), outline=OUT)
	d.point([(14, 9), (17, 9)], fill=(20, 10, 5, 255))
	# Kora: big round gourd at front-left, long neck upward
	d.line([(7, 20), (4, 5)], fill=(90, 55, 25, 255), width=2)
	d.ellipse([3, 17, 13, 26], fill=(225, 175, 90, 255), outline=OUT)
	d.ellipse([6, 20, 10, 23], fill=(150, 95, 40, 255))
	# strings
	d.line([(5, 7), (8, 21)], fill=(250, 245, 220, 255))
	return im


# --- Terrain -----------------------------------------------------------------

T = 64


def periodic_noise(rng, cells, amp):
	"""Tileable value noise on a cells x cells lattice, bilinear smooth."""
	g = [[rng.uniform(-1, 1) for _ in range(cells)] for _ in range(cells)]
	out = [[0.0] * T for _ in range(T)]
	step = T / cells
	for y in range(T):
		for x in range(T):
			fx, fy = x / step, y / step
			x0, y0 = int(fx) % cells, int(fy) % cells
			x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
			tx, ty = fx - int(fx), fy - int(fy)
			tx = tx * tx * (3 - 2 * tx)
			ty = ty * ty * (3 - 2 * ty)
			a = g[y0][x0] * (1 - tx) + g[y0][x1] * tx
			b = g[y1][x0] * (1 - tx) + g[y1][x1] * tx
			out[y][x] = (a * (1 - ty) + b * ty) * amp
	return out


def shade(c, v):
	return tuple(max(0, min(255, int(round(ch + v)))) for ch in c)


def tile_base(rng, base, fine_amp=5, coarse_amp=6):
	coarse = periodic_noise(rng, 4, coarse_amp)
	img = Image.new("RGB", (T, T))
	px = img.load()
	for y in range(T):
		for x in range(T):
			v = coarse[y][x] + rng.uniform(-fine_amp, fine_amp)
			px[x, y] = shade(base, v)
	return img


SAND = (222, 190, 132)


def tile_plain(rng):
	return tile_base(rng, SAND)


def tile_ripples(rng):
	img = tile_base(rng, SAND)
	px = img.load()
	warp = periodic_noise(rng, 2, 3.0)
	for y in range(T):
		for x in range(T):
			# 5 ripple bands per tile, gentle slope (x wraps with 1 cycle) -> seamless
			p = (y + warp[y][x]) / T * 5 + x / T * 1
			s = math.sin(p * 2 * math.pi)
			if s > 0.85:
				px[x, y] = shade(px[x, y], -16)
			elif s > 0.6:
				px[x, y] = shade(px[x, y], 9)
	return img


def tile_dune(rng):
	img = tile_base(rng, (226, 186, 120), fine_amp=4)
	px = img.load()
	for y in range(T):
		for x in range(T):
			u, v = x / T * 2 * math.pi, y / T * 2 * math.pi
			h = math.sin(u + v) * 0.6 + math.sin(2 * v - u) * 0.4
			# lit/shadow side from derivative
			dh = math.cos(u + v) * 0.6 - math.cos(2 * v - u) * 0.4
			px[x, y] = shade(px[x, y], h * 10 + dh * 20)
	return img


def tile_laterite(rng):
	img = tile_base(rng, (170, 85, 50), fine_amp=7, coarse_amp=9)
	px = img.load()
	# sparse pebbles
	for _ in range(40):
		x, y = rng.randrange(T), rng.randrange(T)
		px[x, y] = shade(px[x, y], rng.choice([-25, 20]))
	d = ImageDraw.Draw(img)
	# scrub tufts kept away from edges so tile stays seamless
	for (cx, cy) in [(16, 20), (44, 14), (30, 46), (52, 50)]:
		for _ in range(9):
			ang = rng.uniform(math.pi * 1.1, math.pi * 1.9)
			ln = rng.uniform(3, 6)
			ex, ey = cx + math.cos(ang) * ln, cy + math.sin(ang) * ln
			col = rng.choice([(95, 110, 45), (120, 125, 55), (80, 90, 40)])
			d.line([(cx, cy), (ex, ey)], fill=col)
		d.point([(cx, cy + 1), (cx - 1, cy + 1), (cx + 1, cy + 1)], fill=(90, 50, 30))
	return img


def main():
	os.makedirs(SPRITES, exist_ok=True)
	os.makedirs(TILESETS, exist_ok=True)
	sprites = {
		"player.png": draw_player,
		"enemy.png": draw_enemy,
		"camel_lancer.png": draw_camel_lancer,
		"griot_bard.png": draw_griot,
	}
	for name, fn in sprites.items():
		fn().save(os.path.join(SPRITES, name))
	rng = random.Random(1324)
	atlas = Image.new("RGB", (T * 4, T))
	for i, fn in enumerate([tile_plain, tile_ripples, tile_dune, tile_laterite]):
		atlas.paste(fn(rng), (i * T, 0))
	atlas.save(os.path.join(TILESETS, "terrain.png"))
	print("wrote sprites and terrain atlas")


if __name__ == "__main__":
	main()
