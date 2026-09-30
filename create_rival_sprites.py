#!/usr/bin/env python3
"""Generate pixel-art sprites for the Songhai rival faction of the Age of Gold
Godot project (Pillow). Deterministic (seeded).

Writes to "assets/rival/":
  war_camp.png (96x80)       Sahelian war camp: palisade, hide tents, banner
  gao_palace.png (144x128)   Songhai palace at Gao (Rival Wonder)

Reuses the 3/4-view helpers of create_building_sprites.py, but with a darker,
redder mud palette, square crenellated towers (no conical minarets or ostrich
eggs) and dark red / indigo banners, so rival buildings never read as the
player's mosques.
"""
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import create_building_sprites as cb  # noqa: E402

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(ROOT, "assets", "rival")

OUT = cb.OUT
DOOR = cb.DOOR
# Dark Gao mud: (top face, front face light, front face, front shadow)
GAO = ((150, 88, 60, 255), (132, 72, 48, 255), (112, 58, 40, 255), (80, 40, 30, 255))
RED = (140, 22, 26, 255)
RED_DK = (96, 14, 18, 255)
INDIGO = (48, 44, 120, 255)
INDIGO_DK = (30, 26, 80, 255)
STAKE = (112, 78, 44, 255)
STAKE_DK = (74, 50, 28, 255)
HIDE = (188, 150, 104, 255)
HIDE_DK = (140, 104, 66, 255)


def banner(d, x, top, length, colors, flag_w=9, flag_h=6):
	"""Pole from (x, top) down `length` px with a two-striped swallow-tail flag."""
	d.line([(x, top), (x, top + length)], fill=OUT, width=1)
	c1, c2 = colors
	half = flag_h // 2
	d.polygon([(x + 1, top + 1), (x + flag_w, top + 1), (x + flag_w - 2, top + half), (x + 1, top + half)], fill=c1)
	d.polygon([(x + 1, top + half), (x + flag_w - 2, top + half), (x + flag_w, top + flag_h), (x + 1, top + flag_h)], fill=c2)
	d.line([(x + 1, top + 1), (x + flag_w, top + 1)], fill=OUT)
	d.line([(x + 1, top + flag_h), (x + flag_w, top + flag_h)], fill=OUT)
	d.point([(x, top - 1)], fill=cb.GOLD)


def palisade(d, x0, x1, base, height, step=4):
	"""Row of sharpened timber stakes standing on `base`."""
	for x in range(x0, x1 + 1, step):
		h = height + (x * 7 % 3)
		d.polygon([(x, base), (x, base - h + 2), (x + 1, base - h), (x + 2, base - h + 2), (x + 2, base)],
			fill=STAKE, outline=OUT)
		d.line([(x + 2, base - h + 3), (x + 2, base - 1)], fill=STAKE_DK)
	d.line([(x0, base - height // 2), (x1 + 2, base - height // 2)], fill=STAKE_DK)  # lashing


def tent(d, cx, base, w, h, stripe):
	"""Conical hide tent with a coloured band and a dark door flap."""
	hw = w // 2
	d.polygon([(cx - hw, base), (cx, base - h), (cx + hw, base)], fill=HIDE, outline=OUT)
	d.polygon([(cx, base - h), (cx + hw, base), (cx + hw // 3, base)], fill=HIDE_DK)
	band = base - h // 3
	t = (base - band) / h
	d.line([(cx - hw + int(hw * t) - 1, band), (cx + hw - int(hw * t) + 1, band)], fill=stripe, width=2)
	d.polygon([(cx - 2, base), (cx, base - 7), (cx + 2, base)], fill=DOOR, outline=OUT)
	d.line([(cx, base - h - 3), (cx, base - h + 1)], fill=STAKE_DK)  # pole tips
	d.line([(cx - 2, base - h - 2), (cx, base - h)], fill=STAKE_DK)


def draw_war_camp(rng):
	im = cb.new(96, 80)
	d = ImageDraw.Draw(im)
	cb.shadow(d, 48, 72, 44, 7)
	# trampled ground inside the stockade
	d.ellipse([8, 38, 88, 76], fill=(170, 128, 80, 255))
	# back palisade
	palisade(d, 8, 86, 44, 13)
	# tents
	tent(d, 30, 60, 26, 26, RED)
	tent(d, 64, 58, 24, 24, INDIGO)
	tent(d, 47, 52, 18, 18, RED_DK)
	# campfire
	d.ellipse([44, 62, 52, 66], fill=(70, 50, 36, 255), outline=OUT)
	d.polygon([(46, 63), (48, 57), (50, 63)], fill=(250, 160, 40, 255))
	d.point([(48, 60)], fill=(255, 235, 120, 255))
	# spear rack
	for i in range(3):
		x = 76 + i * 3
		d.line([(x, 66), (x + 2, 50)], fill=STAKE_DK)
		d.point([(x + 2, 49)], fill=(210, 210, 220, 255))
	# front palisade with an open gate in the middle
	palisade(d, 4, 38, 76, 11)
	palisade(d, 58, 90, 76, 11)
	d.line([(40, 66), (40, 76)], fill=OUT, width=2)
	d.line([(56, 66), (56, 76)], fill=OUT, width=2)
	# war banner on a tall pole
	banner(d, 16, 6, 38, (RED, INDIGO), flag_w=14, flag_h=10)
	banner(d, 82, 22, 22, (INDIGO, RED), flag_w=8, flag_h=6)
	cb.speckle(im, rng, (0, 0, 95, 79), [HIDE, STAKE, (170, 128, 80, 255)], amount=0.1, amp=10)
	return im


def square_tower(d, x0, x1, top, bottom, pal):
	"""Square battlemented bastion (the Songhai look: no cone, no egg)."""
	roof, light, face, dark = pal
	d.rectangle([x0, top, x1, top + 5], fill=roof, outline=OUT)
	d.rectangle([x0, top + 5, x1, bottom], fill=face, outline=OUT)
	d.line([(x0 + 1, top + 6), (x0 + 1, bottom - 1)], fill=light)
	d.line([(x1 - 1, top + 6), (x1 - 1, bottom - 1)], fill=dark)
	# stepped crenellations
	for x in range(x0, x1 - 1, 4):
		d.rectangle([x, top - 3, x + 2, top], fill=roof, outline=OUT)
	# arrow slits
	for y in range(top + 12, bottom - 8, 10):
		d.rectangle([(x0 + x1) // 2, y, (x0 + x1) // 2, y + 3], fill=DOOR)


def draw_gao_palace(rng):
	im = cb.new(144, 128)
	d = ImageDraw.Draw(im)
	cb.shadow(d, 72, 119, 68, 8)
	pal = GAO
	# outer wall and forecourt
	cb.block(d, 4, 139, 70, 80, 119, pal, merlons=True)
	# inner palace, two storeys
	cb.block(d, 22, 121, 40, 52, 96, pal, merlons=True)
	cb.block(d, 44, 99, 20, 30, 56, pal, merlons=True)
	# timber rows
	for row in (60, 70, 86):
		for x in range(26, 118, 6):
			d.point([(x, row)], fill=cb.TIMBER)
			d.point([(x + 1, row)], fill=cb.TIMBER_HI)
	for x in range(48, 96, 6):
		d.point([(x, 40)], fill=cb.TIMBER)
	# windows of the upper hall
	for x in (52, 64, 78, 90):
		cb.window(d, x, 36, 3, 5)
	for x in (32, 46, 96, 110):
		cb.window(d, x, 64, 3, 5)
	# corner bastions of the outer wall
	square_tower(d, 2, 18, 56, 119, pal)
	square_tower(d, 125, 141, 56, 119, pal)
	# gatehouse with twin towers
	square_tower(d, 54, 64, 66, 119, pal)
	square_tower(d, 80, 90, 66, 119, pal)
	d.rectangle([64, 90, 80, 119], fill=pal[2], outline=OUT)
	cb.door(d, 72, 118, 12, 18)
	d.line([(66, 104), (78, 104)], fill=RED_DK)
	# red and indigo hangings on the wall
	for x, c in ((30, RED), (42, INDIGO), (100, INDIGO), (112, RED)):
		d.rectangle([x, 84, x + 4, 100], fill=c, outline=OUT)
		d.polygon([(x, 100), (x + 2, 103), (x + 4, 100)], fill=c, outline=OUT)
	# banners
	banner(d, 10, 36, 20, (RED, INDIGO), flag_w=12, flag_h=8)
	banner(d, 133, 36, 20, (INDIGO, RED), flag_w=10, flag_h=8)
	banner(d, 71, 2, 18, (RED, INDIGO), flag_w=16, flag_h=10)
	banner(d, 58, 50, 16, (INDIGO, RED_DK), flag_w=8, flag_h=6)
	banner(d, 84, 50, 16, (RED, INDIGO_DK), flag_w=8, flag_h=6)
	cb.speckle(im, rng, (0, 0, 143, 127), [pal[0], pal[2], pal[3]])
	return im


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	builders = {
		"war_camp.png": draw_war_camp,
		"gao_palace.png": draw_gao_palace,
	}
	for i, (name, fn) in enumerate(builders.items()):
		rng = random.Random(4417 + i)
		fn(rng).save(os.path.join(OUT_DIR, name))
	print("wrote %d rival sprites to %s" % (len(builders), OUT_DIR))


if __name__ == "__main__":
	main()
