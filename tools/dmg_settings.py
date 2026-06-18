# dmgbuild settings for the Patina install window.
# Usage: APP=dist/Patina.app python3 -m dmgbuild -s tools/dmg_settings.py "Patina" out.dmg
import os.path

app = os.environ.get("APP", "dist/Patina.app")
appname = os.path.basename(app)

# Volume
format = "UDZO"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"          # the mounted volume's icon

# Window
background = "assets/dmg-bg.png"
window_rect = ((220, 220), (660, 440))    # ((x, y), (w, h))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13

# Icon placement (centre points, top-left origin) — match the background arrow.
icon_locations = {
    appname: (175, 215),
    "Applications": (485, 215),
}
