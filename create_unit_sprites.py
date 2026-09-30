#!/usr/bin/env python3
"""Generate sprites for the Phase 4 units of Age of Gold (Pillow), in the style
of create_sprites.py: Desert Scout, Gold Gilder, Donson Ton (32x32) and the
Golden Mansa hero (48x48). Output: Age of Gold Game/assets/units/. Deterministic."""
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Age of Gold Game")
OUT_DIR = os.path.join(ROOT, "assets", "units")

OUT = (30, 20, 12, 255)  # dark outline
SKIN = (110, 70, 40, 255)
GOLD = (255, 205, 30, 255)
GOLD_LIGHT = (255, 235, 120, 255)
GOLD_DARK = (190, 130, 20, 255)


def new_sprite(size=32):
	return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def shadow(d, cx=16, cy=28, rx=10, ry=3):
	d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, 70))


def draw_scout():
	"""Lean camel rider in indigo, leaning forward, no lance."""
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d, cy=29, rx=12)
	tan = (190, 150, 95, 255)
	dtan = (145, 105, 60, 255)
	# Long thin legs (galloping stance)
	d.line([(8, 22), (5, 29)], fill=dtan, width=2)
	d.line([(11, 22), (12, 29)], fill=dtan, width=2)
	d.line([(20, 22), (18, 29)], fill=dtan, width=2)
	d.line([(23, 22), (26, 29)], fill=dtan, width=2)
	# Slim body + hump
	d.ellipse([6, 16, 25, 23], fill=tan, outline=OUT)
	d.ellipse([10, 12, 18, 19], fill=tan, outline=OUT)
	# Neck + head stretched forward
	d.polygon([(23, 18), (28, 12), (30, 13), (26, 20)], fill=tan, outline=OUT)
	d.ellipse([26, 9, 31, 14], fill=tan, outline=OUT)
	d.point([(29, 11)], fill=OUT)
	# Indigo saddle cloth
	d.rectangle([11, 15, 18, 18], fill=(50, 40, 120, 255), outline=OUT)
	# Rider: indigo robe, leaning forward
	d.polygon([(12, 14), (13, 6), (18, 5), (18, 14)], fill=(45, 45, 140, 255), outline=OUT)
	# Indigo veiled head (tagelmust) with eye slit
	d.ellipse([15, 0, 21, 6], fill=(35, 30, 110, 255), outline=OUT)
	d.line([(17, 3), (20, 3)], fill=SKIN)
	# Flowing scarf tail behind
	d.line([(15, 3), (9, 5), (6, 4)], fill=(80, 80, 200, 255), width=1)
	# Spyglass / short staff pointing ahead
	d.line([(18, 8), (25, 6)], fill=(200, 170, 60, 255), width=1)
	return im


def draw_gilder():
	"""Robed craftsman holding a glowing crucible."""
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d)
	# Brown work robe with leather apron
	d.polygon([(16, 10), (24, 28), (8, 28)], fill=(90, 130, 175, 255), outline=OUT)
	d.polygon([(14, 17), (18, 17), (19, 27), (13, 27)], fill=(110, 70, 40, 255), outline=OUT)
	d.line([(9, 27), (23, 27)], fill=GOLD_DARK)
	# Arms forward
	d.rectangle([10, 14, 22, 16], fill=(70, 105, 150, 255), outline=OUT)
	# Head + white cap
	d.ellipse([11, 4, 20, 13], fill=SKIN, outline=OUT)
	d.pieslice([11, 2, 20, 10], 180, 360, fill=(235, 230, 215, 255), outline=OUT)
	d.point([(14, 9), (17, 9)], fill=(20, 10, 5, 255))
	# Tongs + crucible with molten gold (front right)
	d.line([(22, 16), (25, 20)], fill=(70, 70, 75, 255), width=1)
	d.polygon([(22, 19), (30, 19), (28, 26), (24, 26)], fill=(90, 80, 75, 255), outline=OUT)
	d.ellipse([22, 17, 30, 21], fill=GOLD, outline=OUT)
	d.point([(25, 18), (27, 19)], fill=GOLD_LIGHT)
	# Sparks
	d.point([(24, 14), (28, 13), (30, 16)], fill=GOLD_LIGHT)
	# Small ingot at feet
	d.polygon([(3, 26), (8, 26), (9, 28), (2, 28)], fill=GOLD, outline=OUT)
	return im


def draw_donson_ton():
	"""Hunter-guard with a long spear and amulets, ochre/brown."""
	im = new_sprite()
	d = ImageDraw.Draw(im)
	shadow(d)
	# Spear (vertical, right) with green-tipped poisoned blade
	d.line([(25, 4), (25, 29)], fill=(100, 65, 30, 255), width=1)
	d.polygon([(25, 0), (27, 4), (25, 7), (23, 4)], fill=(200, 200, 210, 255), outline=OUT)
	d.point([(25, 5)], fill=(60, 200, 60, 255))
	# Ochre hunter's tunic (bogolan-like mud cloth)
	d.polygon([(16, 10), (23, 28), (9, 28)], fill=(190, 130, 50, 255), outline=OUT)
	for y in (18, 22, 26):
		d.line([(12, y), (20, y)], fill=(90, 55, 25, 255))
	d.point([(14, 20), (18, 20), (16, 24)], fill=(90, 55, 25, 255))
	# Shoulders
	d.rectangle([9, 13, 23, 16], fill=(150, 95, 40, 255), outline=OUT)
	# Amulets (gris-gris) hanging across the chest
	for x in (11, 14, 17, 20):
		d.rectangle([x, 16, x + 1, 18], fill=(230, 215, 170, 255), outline=OUT)
	d.line([(10, 16), (22, 16)], fill=(60, 35, 15, 255))
	# Head with brown hunter's cap and horns
	d.ellipse([11, 4, 20, 13], fill=SKIN, outline=OUT)
	d.pieslice([10, 2, 21, 11], 180, 360, fill=(120, 75, 35, 255), outline=OUT)
	d.line([(11, 5), (9, 1)], fill=(235, 225, 200, 255))
	d.line([(20, 5), (22, 1)], fill=(235, 225, 200, 255))
	d.point([(14, 9), (17, 9)], fill=(20, 10, 5, 255))
	# Hand on spear
	d.ellipse([22, 14, 26, 18], fill=SKIN, outline=OUT)
	return im


def draw_golden_mansa():
	"""48x48 Mansa enthroned in gold robes, with parasol and sceptre."""
	im = new_sprite(48)
	d = ImageDraw.Draw(im)
	shadow(d, cx=24, cy=44, rx=18, ry=4)
	# Throne: dark wood with gold edge
	d.rectangle([9, 14, 39, 42], fill=(90, 50, 25, 255), outline=OUT)
	d.rectangle([11, 16, 37, 40], outline=GOLD_DARK)
	d.rectangle([6, 28, 12, 43], fill=(110, 65, 30, 255), outline=OUT)
	d.rectangle([36, 28, 42, 43], fill=(110, 65, 30, 255), outline=OUT)
	d.ellipse([7, 25, 11, 29], fill=GOLD, outline=OUT)
	d.ellipse([37, 25, 41, 29], fill=GOLD, outline=OUT)
	# Gold robe (wide boubou)
	d.polygon([(24, 16), (36, 43), (12, 43)], fill=GOLD, outline=OUT)
	d.polygon([(24, 22), (30, 43), (18, 43)], fill=GOLD_DARK)
	d.line([(14, 40), (34, 40)], fill=GOLD_LIGHT)
	d.line([(24, 20), (24, 42)], fill=GOLD_LIGHT)
	# Arms / sash
	d.rectangle([13, 23, 35, 27], fill=(230, 180, 30, 255), outline=OUT)
	d.point([(20, 25), (24, 25), (28, 25)], fill=(200, 30, 30, 255))
	# Sceptre with gold orb
	d.line([(38, 8), (38, 34)], fill=(120, 80, 20, 255), width=2)
	d.ellipse([35, 3, 41, 9], fill=GOLD, outline=OUT)
	d.point([(37, 5)], fill=GOLD_LIGHT)
	# Gold nugget in the other hand
	d.ellipse([8, 20, 14, 26], fill=GOLD, outline=OUT)
	d.point([(10, 22)], fill=GOLD_LIGHT)
	# Head
	d.ellipse([18, 8, 30, 20], fill=SKIN, outline=OUT)
	d.point([(21, 14), (26, 14)], fill=(20, 10, 5, 255))
	d.line([(22, 17), (26, 17)], fill=(70, 40, 20, 255))
	# Tall gold crown
	d.polygon([(17, 10), (17, 3), (20, 6), (24, 1), (28, 6), (31, 3), (31, 10)], fill=GOLD, outline=OUT)
	d.point([(24, 6)], fill=(200, 30, 30, 255))
	d.point([(20, 8), (28, 8)], fill=(40, 120, 200, 255))
	return im


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	for name, fn in {
		"desert_scout": draw_scout,
		"gold_gilder": draw_gilder,
		"donson_ton": draw_donson_ton,
		"golden_mansa": draw_golden_mansa,
	}.items():
		path = os.path.join(OUT_DIR, name + ".png")
		fn().save(path)
		print("wrote", path)


if __name__ == "__main__":
	main()
