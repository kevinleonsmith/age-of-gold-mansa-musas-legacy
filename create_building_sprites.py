#!/usr/bin/env python3
"""Generate pixel-art Sudanese mud-architecture building sprites for the
Age of Gold Godot project (Pillow). Deterministic (seeded).

Writes to "assets/buildings/":
  house.png (64x64), mosque.png (96x96), market.png (80x64),
  outpost.png (80x80), great_mosque.png (128x128), salt_cathedral.png (128x128)

3/4 view: a light roof/top face above a darker front face, dark outline,
conical buttress towers topped with ostrich-egg finials, and protruding
toron timbers.
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(ROOT, "assets", "buildings")

OUT = (30, 20, 12, 255)  # dark outline (same as create_sprites.py)
TIMBER = (84, 54, 28, 255)
TIMBER_HI = (122, 84, 44, 255)
DOOR = (46, 28, 16, 255)
EGG = (246, 240, 224, 255)
GOLD = (255, 205, 40, 255)
GOLD_DK = (190, 130, 20, 255)

# Mud palettes: (top face, front face light, front face, front shadow)
LATERITE = ((214, 150, 92, 255), (196, 124, 70, 255), (172, 102, 56, 255), (134, 74, 40, 255))
OCHRE = ((222, 172, 100, 255), (206, 150, 80, 255), (182, 128, 64, 255), (140, 94, 46, 255))
SALT = ((244, 240, 232, 255), (228, 222, 212, 255), (204, 196, 186, 255), (160, 150, 142, 255))


def new(w, h):
	return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def shade(c, v):
	return tuple(max(0, min(255, x + v)) for x in c[:3]) + (c[3],)


def shadow(d, cx, cy, rx, ry):
	d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, 70))


def speckle(im, rng, box, colors, amount=0.12, amp=12):
	"""Mud texture: randomly darken/lighten pixels of the given colours."""
	px = im.load()
	x0, y0, x1, y1 = box
	cs = set(colors)
	for y in range(max(0, y0), min(im.height, y1 + 1)):
		for x in range(max(0, x0), min(im.width, x1 + 1)):
			if px[x, y] in cs and rng.random() < amount:
				px[x, y] = shade(px[x, y], rng.choice((-amp, -amp, amp // 2)))


def block(d, x0, x1, top, face_top, bottom, pal, merlons=True):
	"""Box in 3/4 view: roof face top..face_top, front face face_top..bottom."""
	roof, light, face, dark = pal
	d.rectangle([x0, top, x1, face_top], fill=roof, outline=OUT)
	d.rectangle([x0, face_top, x1, bottom], fill=face, outline=OUT)
	d.line([(x0 + 1, face_top + 1), (x1 - 1, face_top + 1)], fill=light)
	d.line([(x1 - 1, face_top + 1), (x1 - 1, bottom - 1)], fill=dark)
	if merlons:
		# small rounded parapet teeth along the front roof edge
		for x in range(x0 + 2, x1 - 2, 5):
			d.polygon([(x, face_top), (x + 1, face_top - 3), (x + 2, face_top - 3), (x + 3, face_top)],
				fill=light, outline=OUT)


def toron(d, x, y, length=2, side=0):
	"""Protruding palm timber: side -1 left, 1 right, 0 both."""
	if side <= 0:
		d.line([(x - length, y), (x, y)], fill=TIMBER)
	if side >= 0:
		d.line([(x, y), (x + length, y)], fill=TIMBER)


def tower(d, cx, top, bottom, w, pal, cone_h=None, egg=True, torons=True, gold=False):
	"""Conical mud buttress/minaret: tapered body, cone cap, ostrich-egg finial."""
	roof, light, face, dark = pal
	if cone_h is None:
		cone_h = max(4, w)
	hw = w // 2
	body_top = top + cone_h
	# slightly tapered body (wider at the base)
	taper = max(1, w // 5)
	d.polygon([(cx - hw, body_top), (cx + hw, body_top), (cx + hw + taper, bottom), (cx - hw - taper, bottom)],
		fill=face, outline=OUT)
	d.line([(cx - hw + 1, body_top + 1), (cx - hw - taper + 1, bottom - 1)], fill=light)
	d.line([(cx + hw - 1, body_top + 1), (cx + hw + taper - 1, bottom - 1)], fill=dark)
	# bullet-shaped cone (rounded Sudanese pinnacle)
	mid = body_top - cone_h // 2
	d.polygon([(cx - hw, body_top), (cx - hw + max(1, hw // 3), mid), (cx - 1, top), (cx + 1, top),
		(cx + hw - max(1, hw // 3), mid), (cx + hw, body_top)], fill=roof, outline=OUT)
	d.line([(cx - hw + 2, body_top - 1), (cx - 1, top + 2)], fill=shade(roof, 18))
	if egg:
		c = GOLD if gold else EGG
		d.ellipse([cx - 1, top - 3, cx + 1, top], fill=c, outline=OUT)
	if torons:
		for y in range(body_top + 4, bottom - 3, 6):
			toron(d, cx - hw - 1, y, 2, -1)
			toron(d, cx + hw + 1, y, 2, 1)
	return body_top


def door(d, cx, bottom, w, h):
	d.rectangle([cx - w // 2, bottom - h, cx + w // 2, bottom], fill=DOOR, outline=OUT)
	d.pieslice([cx - w // 2, bottom - h - w // 2, cx + w // 2, bottom - h + w // 2], 180, 360, fill=DOOR, outline=OUT)


def window(d, x, y, w=2, h=3):
	d.rectangle([x, y, x + w - 1, y + h - 1], fill=DOOR)


# --- Buildings ---------------------------------------------------------------

def draw_house(rng):
	im = new(64, 64)
	d = ImageDraw.Draw(im)
	shadow(d, 32, 56, 27, 5)
	pal = LATERITE
	# main dwelling
	block(d, 8, 42, 20, 30, 56, pal)
	# corner pinnacles
	tower(d, 10, 12, 56, 6, pal, cone_h=6, egg=False, torons=False)
	tower(d, 40, 12, 56, 6, pal, cone_h=6, egg=False, torons=False)
	door(d, 25, 55, 7, 9)
	window(d, 17, 37)
	window(d, 32, 37)
	for x in (15, 22, 29, 36):
		toron(d, x, 32, 0)
		d.point([(x, 32), (x, 33)], fill=TIMBER)
	# roof clutter: ladder hatch + pot
	d.rectangle([30, 23, 34, 26], fill=DOOR, outline=OUT)
	d.ellipse([15, 22, 19, 26], fill=(150, 80, 40, 255), outline=OUT)
	# round granary with thatched cone
	gx = 51
	d.rectangle([gx - 7, 38, gx + 7, 55], fill=pal[2], outline=OUT)
	d.ellipse([gx - 7, 51, gx + 7, 58], fill=pal[2], outline=OUT)
	d.rectangle([gx - 6, 39, gx + 6, 54], fill=pal[2])
	d.line([(gx - 6, 39), (gx - 6, 54)], fill=pal[1])
	d.line([(gx + 6, 39), (gx + 6, 54)], fill=pal[3])
	thatch = (196, 164, 88, 255)
	d.polygon([(gx - 10, 40), (gx, 26), (gx + 10, 40)], fill=thatch, outline=OUT)
	for i in range(-7, 8, 3):
		d.line([(gx, 28), (gx + i, 39)], fill=shade(thatch, -30))
	speckle(im, rng, (0, 0, 63, 63), [pal[0], pal[2]])
	return im


def draw_mosque(rng):
	im = new(96, 96)
	d = ImageDraw.Draw(im)
	shadow(d, 48, 87, 42, 7)
	pal = LATERITE
	# prayer hall behind (roof with small skylight pots)
	block(d, 10, 86, 30, 48, 86, pal, merlons=False)
	for x in range(16, 82, 9):
		d.rectangle([x, 36, x + 2, 38], fill=pal[3], outline=OUT)
	# pilasters with small cones along the facade
	for x in range(20, 80, 8):
		if abs(x - 48) < 10:
			continue
		tower(d, x, 40, 86, 4, pal, cone_h=5, egg=False, torons=False)
	# rows of toron across the facade
	for row in (56, 66, 76):
		for x in range(14, 84, 6):
			d.point([(x, row)], fill=TIMBER)
			d.point([(x + 1, row)], fill=TIMBER_HI)
	# conical minarets: corners + tall central qibla tower
	tower(d, 12, 20, 86, 9, pal, cone_h=10)
	tower(d, 84, 20, 86, 9, pal, cone_h=10)
	tower(d, 48, 4, 86, 16, pal, cone_h=14)
	door(d, 48, 85, 9, 12)
	window(d, 46, 44, 5, 4)
	window(d, 46, 32, 5, 3)
	speckle(im, rng, (0, 0, 95, 95), [pal[0], pal[2]])
	return im


def draw_market(rng):
	im = new(80, 64)
	d = ImageDraw.Draw(im)
	shadow(d, 40, 57, 36, 5)
	pal = OCHRE
	# courtyard floor seen from above, low mud wall on the back and front
	d.rectangle([4, 14, 75, 56], fill=(226, 196, 140, 255), outline=OUT)
	block(d, 4, 75, 10, 14, 18, pal, merlons=False)
	# stalls with striped awnings
	awnings = [((180, 40, 30, 255), (240, 220, 190, 255)), ((40, 50, 120, 255), (230, 200, 120, 255)),
		((200, 140, 30, 255), (90, 40, 20, 255))]
	for i, (x, y) in enumerate(((8, 20), (30, 22), (52, 20), (18, 36), (44, 38))):
		a, b = awnings[i % 3]
		# posts
		d.line([(x + 1, y + 6), (x + 1, y + 13)], fill=TIMBER)
		d.line([(x + 18, y + 6), (x + 18, y + 13)], fill=TIMBER)
		# goods on the ground
		d.rectangle([x + 3, y + 10, x + 16, y + 13], fill=(170, 110, 60, 255), outline=OUT)
		for k in range(4):
			col = rng.choice([GOLD, EGG, (120, 60, 30, 255), (60, 130, 60, 255)])
			d.point([(x + 5 + k * 3, y + 11)], fill=col)
		# awning cloth
		d.polygon([(x - 1, y + 7), (x + 3, y), (x + 16, y), (x + 20, y + 7)], fill=a, outline=OUT)
		for sx in range(x + 3, x + 18, 4):
			d.line([(sx, y + 1), (sx - 1, y + 6)], fill=b)
	# front low wall with gate gap
	block(d, 4, 32, 52, 54, 58, pal, merlons=False)
	block(d, 47, 75, 52, 54, 58, pal, merlons=False)
	# water pots
	for x in (36, 41):
		d.ellipse([x, 51, x + 4, 56], fill=(150, 80, 40, 255), outline=OUT)
	tower(d, 5, 2, 18, 6, pal, cone_h=6, egg=False, torons=False)
	tower(d, 74, 2, 18, 6, pal, cone_h=6, egg=False, torons=False)
	speckle(im, rng, (0, 0, 79, 63), [pal[0], pal[2]])
	return im


def draw_outpost(rng):
	im = new(80, 80)
	d = ImageDraw.Draw(im)
	shadow(d, 40, 72, 36, 6)
	pal = LATERITE
	# enclosure wall
	block(d, 6, 74, 40, 50, 72, pal)
	# keep tower
	block(d, 24, 56, 14, 24, 60, pal)
	tower(d, 25, 4, 60, 7, pal, cone_h=8)
	tower(d, 55, 4, 60, 7, pal, cone_h=8)
	door(d, 40, 71, 9, 11)
	window(d, 33, 30, 2, 4)
	window(d, 46, 30, 2, 4)
	for y in (36, 46):
		for x in range(29, 53, 5):
			d.point([(x, y), (x + 1, y)], fill=TIMBER)
	# flag
	d.line([(40, 2), (40, 16)], fill=TIMBER)
	d.polygon([(41, 2), (50, 5), (41, 8)], fill=(40, 120, 60, 255), outline=OUT)
	d.point([(44, 5)], fill=GOLD)
	# stacked salt slabs by the wall
	for i, (x, y) in enumerate(((60, 60), (66, 60), (63, 55))):
		d.rectangle([x, y, x + 7, y + 4], fill=SALT[1], outline=OUT)
		d.line([(x + 1, y + 1), (x + 6, y + 1)], fill=EGG)
	tower(d, 7, 32, 72, 6, pal, cone_h=6, egg=False, torons=False)
	tower(d, 73, 32, 72, 6, pal, cone_h=6, egg=False, torons=False)
	speckle(im, rng, (0, 0, 79, 79), [pal[0], pal[2]])
	return im


def draw_great_mosque(rng):
	im = new(128, 128)
	d = ImageDraw.Draw(im)
	shadow(d, 64, 120, 60, 7)
	pal = LATERITE
	# raised plinth platform
	d.rectangle([2, 108, 125, 121], fill=pal[3], outline=OUT)
	d.line([(3, 109), (124, 109)], fill=pal[1])
	d.rectangle([50, 108, 77, 121], fill=pal[2], outline=OUT)  # stair
	for y in range(111, 121, 3):
		d.line([(51, y), (76, y)], fill=pal[3])
	# prayer hall roof
	block(d, 8, 119, 38, 58, 108, pal, merlons=False)
	for x in range(14, 116, 8):
		for y in (42, 50):
			d.rectangle([x, y, x + 2, y + 2], fill=pal[3], outline=OUT)
	# many pilasters with small cones
	for x in (21, 50, 78, 106):
		tower(d, x, 52, 108, 5, pal, cone_h=6, egg=False, torons=False)
	# dense toron rows
	for row in (66, 76, 86, 96):
		for x in range(12, 118, 5):
			d.point([(x, row)], fill=TIMBER)
			d.point([(x + 1, row)], fill=TIMBER_HI)
	# three great qibla towers + corner towers
	tower(d, 10, 34, 108, 11, pal, cone_h=12)
	tower(d, 117, 34, 108, 11, pal, cone_h=12)
	tower(d, 36, 20, 108, 14, pal, cone_h=14, gold=True)
	tower(d, 92, 20, 108, 14, pal, cone_h=14, gold=True)
	tower(d, 64, 3, 108, 22, pal, cone_h=18, gold=True)
	door(d, 64, 107, 12, 16)
	window(d, 61, 52, 7, 5)
	window(d, 61, 38, 7, 4)
	window(d, 34, 50, 4, 5)
	window(d, 90, 50, 4, 5)
	speckle(im, rng, (0, 0, 127, 127), [pal[0], pal[2], pal[3]])
	return im


def draw_salt_cathedral(rng):
	im = new(128, 128)
	d = ImageDraw.Draw(im)
	shadow(d, 64, 120, 60, 7)
	pal = SALT
	trim = LATERITE
	# laterite plinth
	d.rectangle([2, 108, 125, 121], fill=trim[3], outline=OUT)
	d.line([(3, 109), (124, 109)], fill=trim[1])
	# main hall of salt slabs, roofed with camel hide
	block(d, 10, 117, 40, 60, 108, pal, merlons=False)
	d.rectangle([11, 41, 116, 59], fill=(176, 120, 72, 255))
	for x in range(12, 116, 6):
		d.line([(x, 41), (x, 59)], fill=(150, 98, 56, 255))
	# salt-block coursing on the facade
	for y in range(64, 108, 6):
		d.line([(11, y), (116, y)], fill=pal[3])
		off = 0 if (y // 6) % 2 else 6
		for x in range(11 + off, 116, 12):
			d.line([(x, y), (x, y + 5)], fill=pal[3])
	# pink rock-salt accents
	for _ in range(30):
		x, y = rng.randint(12, 115), rng.randint(62, 106)
		d.point([(x, y)], fill=(236, 196, 196, 255))
	# laterite band with gold ingots
	d.rectangle([10, 60, 117, 63], fill=trim[2], outline=OUT)
	for x in range(16, 114, 10):
		d.rectangle([x, 61, x + 4, 62], fill=GOLD)
	# salt towers with laterite cones and gold finials
	cone_pal = (trim[0], pal[1], pal[2], pal[3])
	for cx, top, w in ((12, 36, 12), (115, 36, 12), (40, 22, 14), (88, 22, 14)):
		tower(d, cx, top, 108, w, cone_pal, cone_h=12, gold=True)
	# central dome-tower
	body_top = tower(d, 64, 4, 108, 24, cone_pal, cone_h=20, gold=True)
	d.rectangle([54, body_top + 6, 74, body_top + 9], fill=trim[2], outline=OUT)
	door(d, 64, 107, 14, 18)
	d.rectangle([56, 85, 72, 88], fill=GOLD_DK, outline=OUT)
	window(d, 61, 40, 7, 5)
	window(d, 38, 50, 4, 6)
	window(d, 86, 50, 4, 6)
	speckle(im, rng, (0, 0, 127, 127), [pal[0], pal[2]], amount=0.08, amp=10)
	return im


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	builders = {
		"house.png": draw_house,
		"mosque.png": draw_mosque,
		"market.png": draw_market,
		"outpost.png": draw_outpost,
		"great_mosque.png": draw_great_mosque,
		"salt_cathedral.png": draw_salt_cathedral,
	}
	for i, (name, fn) in enumerate(builders.items()):
		rng = random.Random(1324 + i)
		fn(rng).save(os.path.join(OUT_DIR, name))
	print("wrote %d building sprites to %s" % (len(builders), OUT_DIR))


if __name__ == "__main__":
	main()
