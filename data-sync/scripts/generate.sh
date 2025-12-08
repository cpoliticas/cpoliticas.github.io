#!/usr/bin/env bash

DATA_DIR="data-sync/public/data"
OUTPUT="data-sync/public/main.m3u"

# Limpia archivo previo
echo "#EXTM3U" > "$OUTPUT"
echo "" >> "$OUTPUT"

process_file() {
    local file="$1"
    local category="$2"
    local country_name="$3"

    # Para separar correctamente archivos
    echo "" >> "$OUTPUT"

    # Procesar líneas preservando EXTINF y URLs
    while IFS= read -r line; do

        if [[ "$line" =~ ^#EXTINF ]]; then
            # Quitar cualquier group-title previo
            clean=$(echo "$line" | sed -E 's/group-title="[^"]*"//g')

            # Insertar group-title correcto
            echo "${clean%,} group-title=\"$country_name - $category\"," >> "$OUTPUT"

        elif [[ "$line" =~ ^http ]]; then
            # URL normal
            echo "$line" >> "$OUTPUT"
        fi

    done < "$file"
}

for country in "$DATA_DIR"/*; do
    if [ -d "$country" ]; then

        country_name=$(basename "$country")

        # 1. favoritos.m3u
        if [ -f "$country/favoritos.m3u" ]; then
            process_file "$country/favoritos.m3u" "Favoritos" "$country_name"
        fi

        # 2. sin-clasificar.m3u
        if [ -f "$country/sin-clasificar.m3u" ]; then
            process_file "$country/sin-clasificar.m3u" "General" "$country_name"
        fi

        # 3. categorías internas
        if [ -d "$country/categorias" ]; then
            for category_file in "$country/categorias"/*.m3u; do
                if [ -f "$category_file" ]; then
                    category_name=$(basename "$category_file" .m3u)
                    process_file "$category_file" "$category_name" "$country_name"
                fi
            done
        fi

    fi
done
