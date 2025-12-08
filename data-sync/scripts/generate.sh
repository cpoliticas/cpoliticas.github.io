#!/usr/bin/env bash

# Directorio donde están sus listas organizadas por país
DATA_DIR="data-sync/public/data"

# Archivo maestro final que se publicará
OUTPUT="data-sync/public/main.m3u"

# Encabezado del archivo M3U
echo "#EXTM3U" > "$OUTPUT"

# Recorre cada país (subcarpetas dentro de data-sync/public/data)
for country in "$DATA_DIR"/*; do
    if [ -d "$country" ]; then
        country_name=$(basename "$country")

        # 1. favoritos.m3u
        if [ -f "$country/favoritos.m3u" ]; then
            sed "s/group-title=\"[^\"]*\"/group-title=\"$country_name - Favoritos\"/g" \
                "$country/favoritos.m3u" >> "$OUTPUT"
        fi

        # 2. sin-clasificar.m3u
        if [ -f "$country/sin-clasificar.m3u" ]; then
            sed "s/group-title=\"[^\"]*\"/group-title=\"$country_name - General\"/g" \
                "$country/sin-clasificar.m3u" >> "$OUTPUT"
        fi

        # 3. categorías internas (si existen)
        if [ -d "$country/categorias" ]; then
            for category_file in "$country/categorias"/*.m3u; do
                if [ -f "$category_file" ]; then
                    category_name=$(basename "$category_file" .m3u)

                    sed "s/group-title=\"[^\"]*\"/group-title=\"$country_name - $category_name\"/g" \
                        "$category_file" >> "$OUTPUT"
                fi
            done
        fi
    fi
done
