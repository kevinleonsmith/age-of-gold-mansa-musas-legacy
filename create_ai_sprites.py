#!/usr/bin/env python3
"""Generate pixel-art sprites for the AI rival empires of the Age of Gold
Godot project (Showdown / Scholars modes). Pillow, deterministic (seeded).

Writes to "assets/ai/":
  banner_songhai.png, banner_mossi.png, banner_tuareg.png (48x80)
      Empire standards planted at each AI capital.
  ai_worker.png (32x32)
      AI porter with a head basket (skin, legs, basket; robe left out).
  ai_worker_robe.png (32x32)
      The porter's robe in pale cloth, drawn over ai_worker.png as its own
      Sprite2D so the empire colour can be applied with `modulate` without
      tinting the skin.
  library.png (80x72)
      Small mud-brick library (AI manuscript source), pale so it tints well.
  flag_neutral.png, flag_player.png, flag_songhai.png, flag_mossi.png,
  flag_tuareg.png (24x32)
      Node-control flags shown on gold / salt nodes.

Usage: python3 create_ai_sprites.py [--preview out.png]
"""
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import create_building_sprites as cb  # noqa: E402

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(ROOT, "assets", "ai")

OUT = cb.OUT
POLE = (96, 64, 34, 255)
POLE_DK = (64, 42, 22, 255)
SKIN = (110, 70, 40, 255)

# Empire colours (must match ai/AIEmpire.gd EMPIRES)
EMPIRES = {
	"songhai": ((204, 52, 46, 255), (130, 26, 24, 255), (250, 220, 120, 255)),
	"mossi": ((58, 164, 78, 255), (30, 104, 48, 255), (245, 235, 200, 255)),
	"tuareg": ((70, 104, 222, 255), (36, 52, 140, 255), (235, 235, 245, 255)),
	"player": ((255, 205, 40, 255), (190, 130, 20, 255), (250, 250, 240, 255)),
	"neutral": ((214, 206, 190, 255), (150, 142, 130, 255), (110, 100, 90, 255)),
}


def shade(c, v):
	return tuple(max(0, min(255, x + v)) for x in c[:3]) + (255,)


def emblem(d, kind, cx, cy, col):
	"""Small device on a banner: Songhai sun, Mossi horse head, Tuareg cross."""
	if kind == "songhai":
		d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=col, outline=OUT)
		for dx, dy in ((0, -7), (0, 7), (-7, 0), (7, 0), (-5, -5), (5, 5), (-5, 5), (5, -5)):
			d.point([(cx + dx, cy + dy)], fill=col)
	elif kind == "mossi":
		d.polygon([(cx - 4, cy + 5), (cx - 3, cy - 2), (cx + 1, cy - 6), (cx + 5, cy - 3),
			(cx + 2, cy - 1), (cx + 1, cy + 5)], fill=col, outline=OUT)
		d.point([(cx + 1, cy - 4)], fill=OUT)
	else:  # Tuareg cross of Agadez
		d.ellipse([cx - 3, cy - 8, cx + 3, cy - 3], outline=col, width=2)
		d.rectangle([cx - 1, cy - 3, cx + 1, cy + 7], fill=col)
		d.rectangle([cx - 6, cy - 1, cx + 6, cy + 1], fill=col)
		d.polygon([(cx - 3, cy + 7), (cx + 3, cy + 7), (cx, cy + 3)], fill=col)


def draw_banner(kind, rng):
	main, dark, device = EMPIRES[kind]
	im = cb.new(48, 80)
	d = ImageDraw.Draw(im)
	cb.shadow(d, 24, 75, 14, 4)
	# mud base with stones
	d.ellipse([12, 66, 36, 78], fill=(150, 104, 62, 255), outline=OUT)
	d.ellipse([15, 67, 33, 74], fill=(178, 128, 80, 255))
	# pole
	d.rectangle([22, 6, 25, 72], fill=POLE, outline=OUT)
	d.line([(24, 8), (24, 70)], fill=POLE_DK)
	d.ellipse([20, 1, 27, 8], fill=cb.GOLD, outline=OUT)
	# cross bar and hanging banner with a swallow tail
	d.rectangle([8, 10, 40, 12], fill=POLE, outline=OUT)
	d.polygon([(10, 13), (38, 13), (38, 50), (24, 44), (10, 50)], fill=main, outline=OUT)
	d.polygon([(34, 13), (38, 13), (38, 50), (34, 48)], fill=dark)
	d.line([(11, 17), (37, 17)], fill=dark)
	d.line([(11, 40), (37, 40)], fill=dark)
	emblem(d, kind, 24, 28, device)
	# tassels
	for x in (12, 36):
		d.line([(x, 50), (x, 55)], fill=cb.GOLD)
		d.point([(x, 56)], fill=cb.GOLD_DK)
	cb.speckle(im, rng, (10, 13, 38, 50), [main, dark], amount=0.08, amp=10)
	return im


def draw_worker_robe(rng):
	im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	robe = (250, 248, 242, 255)
	robe_dk = (200, 196, 188, 255)
	d.polygon([(16, 12), (23, 26), (9, 26)], fill=robe, outline=OUT)
	d.polygon([(16, 12), (23, 26), (18, 26)], fill=robe_dk)
	d.line([(10, 21), (22, 21)], fill=robe_dk)
	d.line([(16, 14), (16, 25)], fill=(226, 222, 214, 255))
	return im


def draw_worker(rng):
	im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([6, 25, 26, 31], fill=(0, 0, 0, 70))
	# legs
	d.line([(13, 24), (12, 29)], fill=OUT, width=2)
	d.line([(19, 24), (20, 29)], fill=OUT, width=2)
	# arms up holding the basket
	d.line([(11, 15), (9, 9)], fill=SKIN, width=2)
	d.line([(21, 15), (23, 9)], fill=SKIN, width=2)
	# head
	d.ellipse([12, 7, 20, 15], fill=SKIN, outline=OUT)
	d.point([(14, 11), (18, 11)], fill=(20, 10, 5, 255))
	# head basket with gold nuggets and a salt slab
	d.polygon([(7, 7), (25, 7), (22, 2), (10, 2)], fill=(168, 118, 60, 255), outline=OUT)
	d.line([(9, 5), (23, 5)], fill=(120, 80, 36, 255))
	d.ellipse([11, 0, 15, 3], fill=cb.GOLD, outline=OUT)
	d.rectangle([17, 0, 22, 2], fill=(244, 240, 232, 255), outline=OUT)
	return im


def draw_library(rng):
	im = cb.new(80, 72)
	d = ImageDraw.Draw(im)
	cb.shadow(d, 40, 66, 36, 6)
	pal = ((236, 214, 176, 255), (224, 198, 156, 255), (206, 178, 136, 255), (160, 132, 96, 255))
	cb.block(d, 8, 71, 26, 34, 64, pal, merlons=True)
	cb.block(d, 22, 57, 12, 20, 36, pal, merlons=True)
	for x in range(12, 70, 6):
		d.point([(x, 40)], fill=cb.TIMBER)
		d.point([(x + 1, 40)], fill=cb.TIMBER_HI)
	cb.door(d, 40, 63, 12, 16)
	for x in (16, 26, 54, 64):
		cb.window(d, x, 46, 3, 5)
	# scroll rack on the roof terrace and a book stand
	for i in range(4):
		x = 27 + i * 7
		d.rectangle([x, 22, x + 4, 26], fill=(245, 236, 206, 255), outline=OUT)
		d.line([(x + 1, 24), (x + 3, 24)], fill=(150, 90, 40, 255))
	d.polygon([(64, 64), (70, 52), (76, 64)], fill=(120, 80, 40, 255), outline=OUT)
	d.rectangle([66, 52, 74, 55], fill=(245, 236, 206, 255), outline=OUT)
	cb.speckle(im, rng, (0, 0, 79, 71), [pal[0], pal[2]], amount=0.1, amp=8)
	return im


def draw_flag(kind, rng):
	main, dark, device = EMPIRES[kind]
	im = Image.new("RGBA", (24, 32), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.ellipse([3, 27, 13, 31], fill=(0, 0, 0, 80))
	d.rectangle([6, 3, 8, 29], fill=POLE, outline=OUT)
	d.ellipse([5, 0, 9, 4], fill=cb.GOLD, outline=OUT)
	d.polygon([(9, 4), (22, 7), (18, 11), (22, 15), (9, 17)], fill=main, outline=OUT)
	d.line([(10, 15), (20, 15)], fill=dark)
	d.line([(10, 6), (15, 7)], fill=shade(main, 40))
	if kind != "neutral":
		d.point([(13, 10), (14, 10), (13, 11), (14, 11)], fill=device)
	return im


def build_all():
	out = {}
	i = 0
	for kind in ("songhai", "mossi", "tuareg"):
		out["banner_%s.png" % kind] = draw_banner(kind, random.Random(7311 + i))
		i += 1
	out["ai_worker.png"] = draw_worker(random.Random(7400))
	out["ai_worker_robe.png"] = draw_worker_robe(random.Random(7402))
	out["library.png"] = draw_library(random.Random(7401))
	for kind in ("neutral", "player", "songhai", "mossi", "tuareg"):
		out["flag_%s.png" % kind] = draw_flag(kind, random.Random(7500 + i))
		i += 1
	return out


def preview(images, path):
	"""Composite everything (and tinted workers / libraries) on sand at 3x."""
	sheet = Image.new("RGBA", (400, 132), (196, 154, 98, 255))
	x = 8
	for kind in ("songhai", "mossi", "tuareg"):
		sheet.alpha_composite(images["banner_%s.png" % kind], (x, 8))
		x += 56
	sheet.alpha_composite(images["library.png"], (x, 16))
	x += 88
	for kind in ("songhai", "mossi", "tuareg"):
		c = EMPIRES[kind][0]
		tint = tuple(int(255 * 0.45 + ch * 0.55) for ch in c[:3])
		robe = images["ai_worker_robe.png"].copy()
		px = robe.load()
		for yy in range(robe.height):
			for xx in range(robe.width):
				r, g, b, a = px[xx, yy]
				px[xx, yy] = (r * tint[0] // 255, g * tint[1] // 255, b * tint[2] // 255, a)
		w = images["ai_worker.png"].copy()
		w.alpha_composite(robe)
		sheet.alpha_composite(w, (x, 40))
		x += 34
	x = 8
	for kind in ("neutral", "player", "songhai", "mossi", "tuareg"):
		sheet.alpha_composite(images["flag_%s.png" % kind], (x, 96))
		x += 30
	big = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
	big.save(path)


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	images = build_all()
	for name, im in images.items():
		im.save(os.path.join(OUT_DIR, name))
	print("wrote %d AI sprites to %s" % (len(images), OUT_DIR))
	if "--preview" in sys.argv:
		preview(images, sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
	main()
