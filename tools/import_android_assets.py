#!/usr/bin/env python3
"""
Импорт общих ресурсов из Android-проекта в iOS. Руками сгенерированные файлы не править — перезапускать скрипт.

    python3 tools/import_android_assets.py ["~/Documents/Claude/FirstSpoon Android"] [--icon ~/Documents/First-spoon/assets/icon.png]

Что делает:
- `app/src/main/assets/catalog.json`          → FirstSpoon/Resources/catalog.json
- `res/drawable-nodpi/product_*.webp`          → FirstSpoon/Resources/Assets.xcassets/Products/product_*.imageset (PNG, @3x, через sips)
- `res/values/strings.xml`                     → FirstSpoon/Resources/ru.lproj/Localizable.strings
  (те же ключи, что в Android; `%1$s` → `%1$@`; plurals → ключи `<name>#one|few|many|other`)
- `res/font/onest.ttf`                         → FirstSpoon/Resources/Fonts/Onest.ttf
- иконка 1024×1024 (RN `assets/icon.png`)      → AppIcon.appiconset
"""
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "FirstSpoon" / "Resources"


def main():
    args = [a for a in sys.argv[1:]]
    icon = None
    if "--icon" in args:
        i = args.index("--icon")
        icon = Path(args[i + 1]).expanduser()
        del args[i:i + 2]
    android = Path(args[0]).expanduser() if args else Path.home() / "Documents/Claude/FirstSpoon Android"
    main_src = android / "app/src/main"

    APP.mkdir(parents=True, exist_ok=True)
    shutil.copy(main_src / "assets/catalog.json", APP / "catalog.json")

    fonts = APP / "Fonts"
    fonts.mkdir(exist_ok=True)
    shutil.copy(main_src / "res/font/onest.ttf", fonts / "Onest.ttf")

    xcassets = APP / "Assets.xcassets"
    write_json(xcassets / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    products = xcassets / "Products"
    if products.exists():
        shutil.rmtree(products)
    write_json(products / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    count = 0
    for webp in sorted((main_src / "res/drawable-nodpi").glob("product_*.webp")):
        name = webp.stem
        imageset = products / f"{name}.imageset"
        imageset.mkdir(parents=True)
        subprocess.run(["sips", "-s", "format", "png", str(webp), "--out", str(imageset / f"{name}.png")],
                       check=True, capture_output=True)
        write_json(imageset / "Contents.json", {
            "images": [
                {"idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "filename": f"{name}.png", "scale": "3x"},
            ],
            "info": {"author": "xcode", "version": 1},
        })
        count += 1

    if icon:
        appicon = xcassets / "AppIcon.appiconset"
        appicon.mkdir(parents=True, exist_ok=True)
        subprocess.run(["sips", "-s", "format", "png", "-z", "1024", "1024", str(icon), "--out", str(appicon / "icon.png")],
                       check=True, capture_output=True)
        write_json(appicon / "Contents.json", {
            "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        })

    strings = convert_strings(main_src / "res/values/strings.xml")
    lproj = APP / "ru.lproj"
    lproj.mkdir(exist_ok=True)
    (lproj / "Localizable.strings").write_text(strings, encoding="utf-8")
    print(f"catalog.json, {count} product images, strings, font{', icon' if icon else ''} → {APP}")


def write_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def android_text(el) -> str:
    text = "".join(el.itertext())
    text = text.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n")
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    # %1$s → %1$@ (строки в Swift — объекты); %d/%1$d и %% остаются.
    return re.sub(r"%(\d+\$)?s", lambda m: "%" + (m.group(1) or "") + "@", text)


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def convert_strings(xml_path: Path) -> str:
    root = ET.parse(xml_path).getroot()
    out = ["/* Сгенерировано tools/import_android_assets.py из Android res/values/strings.xml — руками не править. */", ""]
    for el in root:
        name = el.get("name")
        if el.tag == "string":
            out.append(f'"{name}" = "{escape(android_text(el))}";')
        elif el.tag == "plurals":
            for item in el.findall("item"):
                out.append(f'"{name}#{item.get("quantity")}" = "{escape(android_text(item))}";')
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    main()
