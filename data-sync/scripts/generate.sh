#!/usr/bin/env bash
set -euo pipefail

# generate.sh - Generador de M3U por país (Opción A)
# Salida: data-sync/public/data/<CountrySlug>/...
#
# Requisitos: Python3 está disponible en GitHub Actions.
# El script intentará instalar pyyaml y requests si no están presentes.

REPO_ROOT="$(pwd)"
CONFIG_FILE="data-sync/config.yaml"
OUTPUT_BASE="data-sync/public/data"

# Map de nombres de país (tal como aparecen en config.yaml) a códigos iptv-org
declare -A COUNTRY_MAP=(
  ["Costa Rica"]="cr"
  ["EEUU"]="us"
  ["Alemania"]="de"
  ["Suiza"]="ch"
  ["Austria"]="at"
  ["Japon"]="jp"
  ["Francia"]="fr"
  ["España"]="es"
)

# Asegurarse que exista directorio de salida
mkdir -p "${OUTPUT_BASE}"

# Instalar dependencias Python si hacen falta (no falla si ya están)
python3 - <<'PY' || true
import sys, subprocess, importlib

reqs = ("yaml","requests")
installed = {pkg.key for pkg in importlib.metadata.distributions()} if sys.version_info >= (3,8) else set()
# fallback try import otherwise pip install
try:
    import yaml, requests  # noqa
except Exception:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "pip"])
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml", "requests"])
PY

# Ejecutar el generador en Python (embedded)
python3 - <<'PY'
import os, re, sys, yaml, requests
from collections import defaultdict, OrderedDict

REPO_ROOT = os.getcwd()
CONFIG_FILE = os.path.join(REPO_ROOT, "data-sync", "config.yaml")
OUTPUT_BASE = os.path.join(REPO_ROOT, "data-sync", "public", "data")

COUNTRY_MAP = {
  "Costa Rica":"cr",
  "EEUU":"us",
  "Alemania":"de",
  "Suiza":"ch",
  "Austria":"at",
  "Japon":"jp",
  "Francia":"fr",
  "España":"es"
}

BASE_URL = "https://iptv-org.github.io/iptv/countries/{}.m3u"

attr_re = re.compile(r'(\w+?)="([^"]*?)"')

def parse_extinf(line):
    parts = line.split(',', 1)
    attrs = {}
    name = parts[1].strip() if len(parts) > 1 else ""
    left = parts[0]
    for k, v in attr_re.findall(left):
        attrs[k] = v
    return attrs, name

def slug(name):
    s = name.strip()
    s = re.sub(r'\s+','_', s)
    s = re.sub(r'[^\w\-]','', s, flags=re.UNICODE)
    return s

def download_country(code):
    url = BASE_URL.format(code)
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.text.splitlines()

# Cargar config
if not os.path.exists(CONFIG_FILE):
    print("Error: config.yaml no encontrado:", CONFIG_FILE, file=sys.stderr)
    sys.exit(1)

with open(CONFIG_FILE, encoding="utf-8") as f:
    config = yaml.safe_load(f) or {}

paises = config.get("paises", [])
if not paises:
    print("Advertencia: no hay países listados en config.yaml")
    sys.exit(0)

# Container para evitar duplicados por URL global
seen_urls = set()

# Procesar cada país
for pais in paises:
    code = COUNTRY_MAP.get(pais)
    print(f"Procesando país: {pais} (code: {code})")
    if not code:
        print(f" - No existe mapping para {pais}, se salta.")
        continue

    try:
        lines = download_country(code)
    except Exception as e:
        print(f" - Error descargando lista para {pais}: {e}")
        continue

    # Parsear entradas
    entries = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("#EXTINF"):
            attrs, name = parse_extinf(line)
            # buscar URL siguiente significativa
            j = i + 1
            url = ""
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines):
                url = lines[j].strip()
            entries.append({"attrs": attrs, "name": name, "url": url, "raw_extinf": line})
            i = j + 1
        else:
            i += 1

    # Agrupar por group-title o region/subdivision; recolectar sin clasificar
    groups = defaultdict(list)
    sinclas = []
    for e in entries:
        url = e["url"]
        if not url:
            continue
        if url in seen_urls:
            continue
        seen_urls.add(url)
        attrs = e["attrs"]
        g = attrs.get("group-title") or attrs.get("category") or None
        if g:
            groups[g].append(e)
        else:
            region = attrs.get("subdivision") or attrs.get("region") or attrs.get("state") or attrs.get("province")
            if region:
                groups[f"Región: {region}"].append(e)
            else:
                sinclas.append(e)

    # Path del país
    country_slug = slug(pais)
    country_dir = os.path.join(OUTPUT_BASE, country_slug)
    categorias_dir = os.path.join(country_dir, "categorias")
    os.makedirs(categorias_dir, exist_ok=True)

    # FAVORITOS (vacío)
    favoritos_path = os.path.join(country_dir, "favoritos.m3u")
    with open(favoritos_path, "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n")
        # No agregamos entradas; queda vacío a la espera de que usted llene más tarde.

    # CATEGORIAS: crear un archivo por grupo detectado
    for grp in sorted(groups.keys()):
        safe_grp = slug(grp)
        outfile = os.path.join(categorias_dir, f"{safe_grp}.m3u")
        with open(outfile, "w", encoding="utf-8") as fo:
            fo.write("#EXTM3U\n\n")
            for e in groups[grp]:
                # reconstruir EXTINF línea original pero no forzamos group-title
                attrs = e["attrs"].copy()
                # rebuild attrs string
                parts = []
                # prefer tvg-id if exists order stable
                for k in sorted(attrs.keys()):
                    v = attrs[k].replace('"','\\"')
                    parts.append(f'{k}=\"{v}\"')
                attr_str = " ".join(parts)
                name = e["name"] or ""
                url = e["url"] or ""
                fo.write(f'#EXTINF:-1 {attr_str},{name}\n{url}\n\n')

    # SIN CLASIFICAR
    sin_path = os.path.join(country_dir, "sin-clasificar.m3u")
    # Si hay muchos sin clasificar (>20) intentamos agrupar por heurística de tokens en el nombre
    if len(sinclas) > 20:
        # heurística simple: agrupar por texto entre paréntesis como posible código/región
        region_map = defaultdict(list)
        rest = []
        for e in sinclas:
            m = re.search(r'\(([A-Za-z]{2,5})\)', e["name"])
            if m:
                region_map[m.group(1)].append(e)
            else:
                rest.append(e)
        # escribir grupos detectados como archivos dentro de categorias (Región:XX)
        for k in sorted(region_map.keys()):
            grpname = f"Región_{k}"
            fname = os.path.join(categorias_dir, f"{slug(grpname)}.m3u")
            with open(fname, "w", encoding="utf-8") as fo:
                fo.write("#EXTM3U\n\n")
                for e in region_map[k]:
                    attrs = e["attrs"].copy()
                    parts = []
                    for kk in sorted(attrs.keys()):
                        vv = attrs[kk].replace('"','\\"')
                        parts.append(f'{kk}=\"{vv}\"')
                    fo.write(f'#EXTINF:-1 {" ".join(parts)},{e["name"]}\n{e["url"]}\n\n')
        # escribir resto en sin-clasificar
        with open(sin_path, "w", encoding="utf-8") as fo:
            fo.write("#EXTM3U\n\n")
            for e in rest:
                attrs = e["attrs"].copy()
                parts = []
                for kk in sorted(attrs.keys()):
                    vv = attrs[kk].replace('"','\\"')
                    parts.append(f'{kk}=\"{vv}\"')
                fo.write(f'#EXTINF:-1 {" ".join(parts)},{e["name"]}\n{e["url"]}\n\n')
    else:
        with open(sin_path, "w", encoding="utf-8") as fo:
            fo.write("#EXTM3U\n\n")
            for e in sinclas:
                attrs = e["attrs"].copy()
                parts = []
                for kk in sorted(attrs.keys()):
                    vv = attrs[kk].replace('"','\\"')
                    parts.append(f'{kk}=\"{vv}\"')
                fo.write(f'#EXTINF:-1 {" ".join(parts)},{e["name"]}\n{e["url"]}\n\n')

    print(f" - Generado para {pais}: {country_dir}")

# ============================
# GENERAR PLAYLIST MAESTRA
# ============================

main_path = os.path.join(REPO_ROOT, "data-sync", "public", "main.m3u")

with open(main_path, "w", encoding="utf-8") as f:
    f.write("#EXTM3U\n\n")

    for pais in paises:
        country_slug = slug(pais)
        base_url = f"https://cpoliticas.github.io/data-sync/public/data/{country_slug}"

        # Entrada principal por país → sin clasificar
        f.write(f'#EXTINF:-1,{pais} (Sin clasificar)\n')
        f.write(f'{base_url}/sin-clasificar.m3u\n\n')

        # Categorías
        categorias_dir = os.path.join(OUTPUT_BASE, country_slug, "categorias")
        if os.path.isdir(categorias_dir):
            for fname in sorted(os.listdir(categorias_dir)):
                if fname.endswith(".m3u"):
                    categoria = fname.replace(".m3u","").replace("_"," ")
                    f.write(f'#EXTINF:-1,{pais} - {categoria}\n')
                    f.write(f'{base_url}/categorias/{fname}\n\n')

print(f"Playlist maestro generado en: {main_path}")


print("Generación completa.")
PY

echo "Script finalizado."
