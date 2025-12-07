#!/usr/bin/env bash

set -e

# Ruta del repositorio público
BASE_URL="https://raw.githubusercontent.com/iptv-org/iptv/master/channels"

CONFIG_FILE="data-sync/config.yaml"
OUTPUT_DIR="data-sync/public"

# Dependencia mínima: yq (ya viene instalada en GitHub Actions)
# Extraemos países del config.yaml
COUNTRIES=$(yq '.paises[]' "$CONFIG_FILE")

echo "===== Generando listas M3U ====="

for COUNTRY in $COUNTRIES; do
    # Convertimos espacios a guiones bajos para el nombre del archivo
    FILE_NAME=$(echo "$COUNTRY" | tr ' ' '_' | tr 'ÁÉÍÓÚÜÑáéíóúüñ' 'AEIOUUNaeiouun')

    OUTPUT_FILE="${OUTPUT_DIR}/${FILE_NAME}.m3u"

    echo "#EXTM3U" > "$OUTPUT_FILE"

    # Archivos M3U de iptv-org que potencialmente pueden contener este país
    # (iptv-org agrupa por idioma, país, tipo y más)
    POSSIBLE_FILES=$(curl -s https://api.github.com/repos/iptv-org/iptv/contents/channels \
                     | yq '.[].name' - | grep ".m3u")

    for M3U_FILE in $POSSIBLE_FILES; do
        RAW_URL="${BASE_URL}/${M3U_FILE}"
        curl -s "$RAW_URL" | grep -i "$COUNTRY" >> "$OUTPUT_FILE" || true
    done

    echo "✔ Generado: $OUTPUT_FILE"
done

echo "===== Listas generadas correctamente ====="
