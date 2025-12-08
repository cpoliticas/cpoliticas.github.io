#!/usr/bin/env bash

# Directorio donde están sus listas organizadas por país
DATA_DIR="data-sync/public/data"

# Archivo maestro final que se publicará
OUTPUT="main.m3u"

# Encabezado del archivo M3U
echo "#EXTM3U" > "$OUTPUT"

# Recorre cada país (subcarpetas dentro de data-sync/public/data)
for country in "$DATA_DIR"/*; do
    if [ -d "$country" ]; then
        country_name=$(basename "$country")

        # Recorre cada categoría dentro del país
        for
