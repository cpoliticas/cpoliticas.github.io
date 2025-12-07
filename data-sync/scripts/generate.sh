#!/usr/bin/env bash
set -e

echo "Generando archivos desde data-sources..."

# Directorio donde están las fuentes
SOURCE_DIR="data-sources"

# Directorio destino
DEST_DIR="data"

mkdir -p "$DEST_DIR"

# Copiar cada archivo y procesarlo si es YAML o JSON
for file in "$SOURCE_DIR"/*; do
    filename=$(basename "$file")

    # Si es YAML, convertirlo a JSON
    if [[ "$file" == *.yaml || "$file" == *.yml ]]; then
        echo "Convirtiendo $filename a JSON..."
        yq -o=json "$file" > "$DEST_DIR/${filename%.*}.json"

    # Si es JSON, copiarlo directamente
    elif [[ "$file" == *.json ]]; then
        echo "Copiando $filename..."
        cp "$file" "$DEST_DIR/$filename"
    fi
done

echo "Generación completa."
