#!/usr/bin/env python3
# Build a styled Patina .dmg whose background uses a Bookmark (which modern
# macOS Finder resolves) rather than a classic alias (which Tahoe ignores).
# Hidden files are parked off-screen so they don't show even with "Show Hidden".
#
# Env: APP, VOL, OUT, BG, ICNS
import os, subprocess, shutil, sys
from ds_store import DSStore
from mac_alias import Bookmark

APP  = os.environ["APP"]
VOL  = os.environ["VOL"]
OUT  = os.environ["OUT"]
BG   = os.environ["BG"]
ICNS = os.environ.get("ICNS", "")
appname = os.path.basename(APP)

rw = "/tmp/_patina_rw.dmg"
for p in (rw, OUT):
    if os.path.exists(p):
        os.remove(p)

subprocess.run(["hdiutil", "create", "-volname", VOL, "-fs", "HFS+",
                "-size", "200m", "-ov", rw],   # empty RW image (UDRW is the default)
               check=True, stdout=subprocess.DEVNULL)
out = subprocess.check_output(["hdiutil", "attach", rw, "-nobrowse", "-noverify"]).decode()
mp = next(l.split("\t")[-1] for l in out.splitlines() if "/Volumes/" in l)

try:
    subprocess.run(["ditto", APP, os.path.join(mp, appname)], check=True)
    os.symlink("/Applications", os.path.join(mp, "Applications"))
    shutil.copy(BG, os.path.join(mp, ".background.png"))
    if ICNS:
        shutil.copy(ICNS, os.path.join(mp, ".VolumeIcon.icns"))
        subprocess.run(["SetFile", "-a", "C", mp], check=False)

    bookmark = Bookmark.for_file(os.path.join(mp, ".background.png")).to_bytes()

    icvp = {
        "arrangeBy": "none",
        "backgroundColorBlue": 1.0, "backgroundColorGreen": 1.0, "backgroundColorRed": 1.0,
        "backgroundImageAlias": bookmark,    # a Bookmark blob — Finder resolves it on Tahoe
        "backgroundType": 2,                 # 2 = picture
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
        "iconSize": 128.0, "labelOnBottom": True,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        "showIconPreview": False, "showItemInfo": False,
        "textSize": 13.0, "viewOptionsVersion": 1,
    }
    bwsp = {
        "ContainerShowSidebar": False, "PreviewPaneVisibility": False,
        "ShowPathbar": False, "ShowSidebar": False, "ShowStatusBar": False,
        "ShowTabView": False, "ShowToolbar": False, "SidebarWidth": 180,
        "WindowBounds": "{{220, 220}, {660, 440}}",
    }

    with DSStore.open(os.path.join(mp, ".DS_Store"), "w+") as d:
        d["."]["vSrn"] = ("long", 1)
        d["."]["bwsp"] = bwsp
        d["."]["icvp"] = icvp
        d[appname]["Iloc"] = (175, 215)
        d["Applications"]["Iloc"] = (485, 215)
        # Park required hidden files far outside the 660×440 window.
        for hidden in (".background.png", ".VolumeIcon.icns", ".fseventsd", ".Trashes", ".DS_Store"):
            d[hidden]["Iloc"] = (3000, 3000)
finally:
    subprocess.run(["hdiutil", "detach", mp], check=False, stdout=subprocess.DEVNULL)

subprocess.run(["hdiutil", "convert", rw, "-format", "UDZO", "-imagekey",
                "zlib-level=9", "-o", OUT], check=True, stdout=subprocess.DEVNULL)
os.remove(rw)
print("built", OUT)
