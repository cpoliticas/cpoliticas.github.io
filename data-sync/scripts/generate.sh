#!/usr/bin/env bash

DATA_DIR="data-sync/public/data"
OUTPUT="data-sync/public/main.m3u"

echo "#EXTM3U" > "$OUTPUT"

for country in "$DATA_DIR"/*; do
    if [ -d "$country" ]; then
        country_name=$(basename "$country")

        process_file() {
            local file="$1"
            local category="$2"

            # Agrega o reemplaza group-title
            sed -E \
                -e "s/group-title=\"[^\"]*\"/group-title=\"$country_name - $category\"/g" \
                -e "s/#EXTINF:-1([^,]*)#/EXTINF:-1 group-title=\"$country_name - $category\"\1#/g" \
                "$file" >> "$OUTPUT"
        }

        # 1. favoritos.m3u
        if [ -f "$country/favoritos.m3u" ]; then
            process_file "$country/favoritos.m3u" "Favoritos"
        fi

        # 2. sin-clasificar.m3u
        if [ -f "$country/sin-clasificar.m3u" ]; then
            process_file "$country/sin-clasificar.m3u" "General"
        fi

        # 3. categorías internas
        if [ -d "$country/categorias" ]; then
            for category_file in "$country/categorias"/*.m3u; do
                if [ -f "$category_file" ]; then
                    category_name=$(basename "$category_file" .m3u)
                    process_file "$category_file" "$category_name"
                fi
            done
        fi

    fi
done
