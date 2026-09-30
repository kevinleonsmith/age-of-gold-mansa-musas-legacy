#!/usr/bin/env python3
"""Generate pixel-art resource art for the Age of Gold Godot project (Pillow).
Deterministic (seeded).

Writes:
  Age of Gold Game/assets/ui/        gold_icon.png, salt_icon.png, manuscript_icon.png (24x24 HUD icons)
  Age of Gold Game/assets/resources/ gold_mine.png, salt_deposit.png, manuscript_cache.png (64x64 map sprites)

The ingot HUD icon reuses assets/economy/ingot_icon.png (create_economy_sprites.py).
Style follows create_sprites.py / create_building_sprites.py: dark outline,
3/4 view with a light top face over a darker front face, soft drop shadow.
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Age of Gold Game")
UI_DIR = os.path.join(ROOT, "assets", "ui")
RES_DIR = os.path.join(ROOT, "assets", "resources")

OUT = (30, 20, 12, 255)  # dark outline (same as create_sprites.py)
GOLD = (255, 205, 40, 255)
GOLD_LIGHT = (255, 238, 130, 255)
GOLD_DARK = (190, 130, 20, 255)
GOLD_DEEP = (140, 90, 16, 255)
SPARK = (255, 255, 235, 255)

SALT_TOP = (248, 246, 238, 255)
SALT_FACE = (226, 224, 216, 255)
SALT_EDGE = (150, 168, 186, 255)  # grey-blue cut edge
SALT_EDGE_DK = (110, 128, 148, 255)
SALT_BAND = (188, 176, 160, 255)  # darker mineral layer in the slab

LEATHER = (132, 74, 36, 255)
LEATHER_DK = (92, 50, 24, 255)
LEATHER_HI = (170, 104, 56, 255)
PAGE = (244, 232, 200, 255)
PAGE_DK = (212, 196, 158, 255)
INK = (60, 40, 30, 255)

ROCK = (150, 76, 44, 255)  # laterite, darker than the terrain tiles
ROCK_HI = (186, 104, 62, 255)
ROCK_DK = (104, 50, 30, 255)
PIT = (26, 16, 10, 255)
WOOD = (110, 72, 36, 255)
WOOD_HI = (150, 104, 56, 255)
ROPE = (206, 180, 130, 255)

MUD_TOP = (222, 172, 100, 255)
MUD = (196, 138, 76, 255)
MUD_DK = (150, 98, 50, 255)
INDIGO = (46, 58, 120, 255)
INDIGO_HI = (80, 96, 170, 255)
CLOTH = (236, 222, 190, 255)


def new(w, h):
	return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def shade(c, v):
	return tuple(max(0, min(255, x + v)) for x in c[:3]) + (c[3],)


def shadow(d, cx, cy, rx, ry, a=70):
	d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, a))


def speckle(im, rng, box, colors, amount=0.15, amp=14):
	px = im.load()
	x0, y0, x1, y1 = box
	cs = set(colors)
	for y in range(max(0, y0), min(im.height, y1 + 1)):
		for x in range(max(0, x0), min(im.width, x1 + 1)):
			if px[x, y] in cs and rng.random() < amount:
				px[x, y] = shade(px[x, y], rng.choice((-amp, -amp, amp // 2)))


def glint(d, x, y, big=False):
	d.point([(x, y)], fill=SPARK)
	if big:
		d.point([(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=GOLD_LIGHT)


def slab(d, x0, y0, w, h, depth, band=True):
	"""Salt slab in 3/4 view: top face (depth px tall) over a front face."""
	d.rectangle([x0, y0, x0 + w, y0 + depth], fill=SALT_TOP, outline=OUT)
	d.rectangle([x0, y0 + depth, x0 + w, y0 + depth + h], fill=SALT_FACE, outline=OUT)
	# grey-blue cut edges
	d.line([(x0 + 1, y0 + depth + h - 1), (x0 + w - 1, y0 + depth + h - 1)], fill=SALT_EDGE)
	d.line([(x0 + w - 1, y0 + depth + 1), (x0 + w - 1, y0 + depth + h - 1)], fill=SALT_EDGE)
	d.line([(x0 + 1, y0 + depth), (x0 + w - 1, y0 + depth)], fill=SALT_EDGE_DK)
	if band and h >= 5:
		by = y0 + depth + h // 2
		for x in range(x0 + 2, x0 + w - 2):
			if (x * 7 + by * 3) % 5 < 2:
				d.point([(x, by)], fill=SALT_BAND)


# --- HUD icons (24x24) ---------------------------------------------------------

def icon_gold():
	im = new(24, 24)
	d = ImageDraw.Draw(im)
	shadow(d, 12, 20, 10, 2, 60)
	# pile of gold dust
	d.polygon([(2, 20), (7, 13), (12, 10), (17, 13), (22, 20)], fill=GOLD_DARK, outline=OUT)
	d.polygon([(5, 18), (9, 13), (12, 11), (15, 13), (19, 18)], fill=GOLD)
	# nuggets on top
	d.ellipse([7, 6, 15, 13], fill=GOLD, outline=OUT)
	d.ellipse([13, 10, 20, 16], fill=GOLD, outline=OUT)
	d.ellipse([3, 12, 9, 17], fill=GOLD, outline=OUT)
	d.point([(9, 8), (10, 8), (9, 9)], fill=GOLD_LIGHT)
	d.point([(15, 12), (16, 12)], fill=GOLD_LIGHT)
	d.point([(5, 14)], fill=GOLD_LIGHT)
	d.point([(12, 11), (18, 14), (7, 16)], fill=GOLD_DARK)
	d.point([(10, 17), (14, 18), (6, 19), (17, 19)], fill=GOLD_LIGHT)
	glint(d, 10, 7)
	glint(d, 20, 5, big=True)
	return im


def icon_salt():
	im = new(24, 24)
	d = ImageDraw.Draw(im)
	shadow(d, 12, 21, 11, 2, 60)
	# two stacked slabs, the top one offset
	slab(d, 1, 11, 21, 7, 4, band=False)
	slab(d, 4, 2, 17, 6, 4, band=False)
	d.point([(6, 5), (7, 5), (3, 13)], fill=(255, 255, 255, 255))
	return im


def icon_manuscript():
	im = new(24, 24)
	d = ImageDraw.Draw(im)
	shadow(d, 12, 21, 10, 2, 60)
	# leather folio seen at 3/4: cream page block + leather cover with flap
	d.polygon([(3, 8), (19, 4), (22, 15), (6, 20)], fill=PAGE, outline=OUT)
	d.line([(6, 19), (21, 15)], fill=PAGE_DK)
	d.line([(5, 17), (20, 13)], fill=PAGE_DK)
	# cover (top face)
	d.polygon([(2, 6), (18, 2), (21, 12), (5, 17)], fill=LEATHER, outline=OUT)
	# tooled border on the cover
	d.polygon([(5, 7), (16, 4), (18, 11), (7, 14)], outline=LEATHER_HI)
	d.point([(11, 9), (12, 9), (11, 8), (12, 10)], fill=GOLD)
	# wrap-around flap (Timbuktu style) and tie
	d.polygon([(18, 2), (21, 12), (23, 11), (20, 2)], fill=LEATHER_DK, outline=OUT)
	d.line([(21, 7), (23, 9)], fill=ROPE)
	return im


# --- World sprites (64x64) -----------------------------------------------------

def gold_mine(rng):
	im = new(64, 64)
	d = ImageDraw.Draw(im)
	shadow(d, 32, 54, 29, 7, 80)
	# laterite outcrop: back boulders, main mound
	d.polygon([(6, 50), (4, 38), (12, 26), (22, 20), (30, 22), (38, 16), (48, 20),
	           (56, 30), (60, 44), (58, 52), (32, 57)], fill=ROCK, outline=OUT)
	# lit top faces
	d.polygon([(12, 27), (22, 21), (30, 23), (26, 30), (14, 32)], fill=ROCK_HI)
	d.polygon([(38, 17), (48, 21), (54, 29), (44, 28), (36, 24)], fill=ROCK_HI)
	# cracks / strata
	for pts in (((8, 42), (16, 40), (20, 44)), ((44, 36), (52, 38), (57, 44)), ((30, 26), (33, 32))):
		d.line(pts, fill=ROCK_DK)
	speckle(im, rng, (4, 16, 60, 57), [ROCK, ROCK_HI], 0.22, 16)
	# gold-bearing quartz veins in the laterite
	for pts in (((7, 36), (12, 34), (16, 35)), ((46, 24), (51, 27), (55, 32)), ((25, 24), (29, 26))):
		d.line(pts, fill=GOLD_DARK, width=2)
		d.line(pts, fill=GOLD)
	# shaft pit (dark ellipse with a rim)
	d.ellipse([19, 34, 43, 50], fill=ROCK_DK, outline=OUT)
	d.ellipse([22, 37, 40, 48], fill=PIT)
	d.arc([22, 37, 40, 48], 200, 340, fill=(60, 34, 20, 255))
	# windlass over the pit: two posts, crossbar with rope drum, crank
	for px in (20, 42):
		d.rectangle([px - 1, 28, px + 1, 44], fill=WOOD, outline=OUT)
		d.point([(px, 29)], fill=WOOD_HI)
	d.rectangle([19, 29, 43, 32], fill=WOOD, outline=OUT)
	d.line([(21, 30), (41, 30)], fill=WOOD_HI)
	d.rectangle([28, 29, 34, 32], fill=ROPE, outline=OUT)
	d.line([(44, 30), (47, 30), (47, 34)], fill=OUT, width=1)
	# rope and hanging calabash bucket
	d.line([(31, 33), (31, 41)], fill=ROPE)
	d.ellipse([28, 40, 34, 45], fill=(176, 120, 56, 255), outline=OUT)
	d.point([(30, 41)], fill=(214, 164, 90, 255))
	# gold ore pile on the rim and glints in the rock
	d.polygon([(41, 55), (46, 45), (52, 42), (58, 46), (61, 55)], fill=GOLD_DARK, outline=OUT)
	d.polygon([(44, 53), (47, 46), (52, 44), (57, 47), (59, 53)], fill=GOLD)
	for (x0, y0) in ((46, 44), (52, 42), (49, 48), (54, 48)):
		d.ellipse([x0, y0, x0 + 5, y0 + 4], fill=GOLD, outline=OUT)
		d.point([(x0 + 1, y0 + 1), (x0 + 2, y0 + 1)], fill=GOLD_LIGHT)
	d.point([(45, 53), (50, 54), (56, 53), (58, 51)], fill=GOLD_LIGHT)
	glint(d, 53, 41, True)
	for (x, y, big) in ((12, 33, True), (27, 25, False), (51, 26, True), (14, 46, False),
	                    (38, 20, False), (55, 38, False), (8, 30, False)):
		d.point([(x, y), (x + 1, y)], fill=GOLD)
		glint(d, x, y - 1 if big else y, big)
	return im


def salt_deposit(rng):
	im = new(64, 64)
	d = ImageDraw.Draw(im)
	shadow(d, 32, 54, 30, 7, 70)
	# white salt crust (irregular flat patch)
	crust = [(3, 48), (8, 40), (20, 36), (34, 38), (48, 35), (60, 42), (61, 50), (50, 57),
	         (30, 59), (12, 57)]
	d.polygon(crust, fill=(236, 234, 226, 255), outline=(150, 150, 150, 255))
	speckle(im, rng, (3, 35, 61, 59), [(236, 234, 226, 255)], 0.25, 14)
	for (x, y) in ((10, 50), (22, 55), (40, 55), (56, 47), (16, 44)):
		d.line([(x, y), (x + 3, y)], fill=(206, 208, 212, 255))
	# stacks of cut slabs (back to front)
	slab(d, 32, 21, 24, 8, 5)
	slab(d, 34, 9, 20, 8, 4)
	slab(d, 6, 25, 26, 9, 5)
	slab(d, 9, 12, 22, 8, 5)
	# a loose slab lying in front
	slab(d, 30, 41, 18, 6, 4)
	# rope lashing on the tall stack
	d.line([(20, 12), (20, 39)], fill=(170, 130, 80, 255))
	d.line([(44, 9), (44, 34)], fill=(170, 130, 80, 255))
	for (x, y) in ((11, 13), (36, 10), (8, 26), (34, 22), (32, 42)):
		d.point([(x, y), (x + 1, y)], fill=(255, 255, 255, 255))
	return im


def manuscript_cache(rng):
	im = new(64, 64)
	d = ImageDraw.Draw(im)
	shadow(d, 32, 55, 29, 6, 75)
	# mud-brick library niche (back wall)
	d.rectangle([10, 10, 54, 14], fill=MUD_TOP, outline=OUT)
	d.rectangle([10, 14, 54, 52], fill=MUD, outline=OUT)
	d.rectangle([47, 14, 53, 51], fill=MUD_DK)
	for x in (14, 24, 34, 44):  # merlons
		d.polygon([(x, 10), (x + 2, 5), (x + 4, 10)], fill=MUD_TOP, outline=OUT)
	# toron timbers
	for (x, y) in ((12, 20), (52, 20), (12, 34), (52, 34)):
		d.line([(x - 3, y), (x, y)], fill=(84, 54, 28, 255), width=2) if x < 30 else \
			d.line([(x, y), (x + 3, y)], fill=(84, 54, 28, 255), width=2)
	speckle(im, rng, (10, 10, 54, 52), [MUD, MUD_TOP, MUD_DK], 0.15, 12)
	# arched niche with shelves of manuscripts
	d.rectangle([19, 24, 45, 50], fill=(70, 42, 22, 255), outline=OUT)
	d.pieslice([19, 15, 45, 33], 180, 360, fill=(70, 42, 22, 255), outline=OUT)
	d.line([(20, 24), (44, 24)], fill=(70, 42, 22, 255))
	for sy in (30, 40):
		d.line([(20, sy), (44, sy)], fill=WOOD_HI)
	for sy in (30, 40):
		x = 21
		while x < 43:
			w = rng.choice((2, 3, 3))
			col = rng.choice((LEATHER, LEATHER_DK, LEATHER_HI, PAGE))
			h = rng.choice((5, 6, 7))
			d.rectangle([x, sy - h, x + w - 1, sy - 1], fill=col)
			x += w + (1 if rng.random() < 0.3 else 0)
	# indigo cloth awning on two poles
	for px in (6, 58):
		d.line([(px, 22), (px, 54)], fill=WOOD, width=2)
		d.point([(px, 22)], fill=OUT)
	d.polygon([(4, 20), (60, 20), (62, 27), (2, 27)], fill=INDIGO, outline=OUT)
	for x in range(6, 60, 8):
		d.line([(x, 21), (x - 1, 26)], fill=INDIGO_HI)
	for x in range(3, 61, 6):  # scalloped fringe
		d.point([(x, 28), (x + 1, 28)], fill=CLOTH)
	# open chest of manuscripts in front
	d.rectangle([18, 44, 46, 56], fill=LEATHER_DK, outline=OUT)
	d.rectangle([18, 44, 46, 47], fill=LEATHER, outline=OUT)
	d.line([(19, 52), (45, 52)], fill=GOLD_DARK)
	d.rectangle([30, 49, 33, 53], fill=GOLD, outline=OUT)
	# lid tipped back
	d.polygon([(18, 44), (46, 44), (44, 38), (20, 38)], fill=LEATHER, outline=OUT)
	d.line([(21, 40), (43, 40)], fill=LEATHER_HI)
	# folios poking out of the chest
	d.rectangle([21, 42, 28, 45], fill=PAGE, outline=OUT)
	d.rectangle([29, 41, 36, 45], fill=LEATHER_HI, outline=OUT)
	d.rectangle([37, 42, 43, 45], fill=PAGE, outline=OUT)
	d.line([(23, 43), (26, 43)], fill=INK)
	d.line([(39, 43), (41, 43)], fill=INK)
	# loose stack beside the chest
	for i, col in enumerate((LEATHER_DK, PAGE, LEATHER, PAGE, LEATHER_HI)):
		y = 55 - i * 2
		d.rectangle([48 + (i % 2), y - 2, 57 + (i % 2), y], fill=col, outline=OUT)
	return im


def main():
	rng = random.Random(1324)
	os.makedirs(UI_DIR, exist_ok=True)
	os.makedirs(RES_DIR, exist_ok=True)
	jobs = (
		(UI_DIR, "gold_icon", lambda: icon_gold()),
		(UI_DIR, "salt_icon", lambda: icon_salt()),
		(UI_DIR, "manuscript_icon", lambda: icon_manuscript()),
		(RES_DIR, "gold_mine", lambda: gold_mine(rng)),
		(RES_DIR, "salt_deposit", lambda: salt_deposit(rng)),
		(RES_DIR, "manuscript_cache", lambda: manuscript_cache(rng)),
	)
	for folder, name, fn in jobs:
		path = os.path.join(folder, name + ".png")
		fn().save(path)
		print("wrote", path)


if __name__ == "__main__":
	main()
