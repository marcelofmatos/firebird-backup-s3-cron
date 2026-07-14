#!/usr/bin/env bash

source /etc/environment
source /usr/local/lib/firebird-backup/common.sh

FB_USER=${FB_USER:-"SYSDBA"}
FB_PASSWORD=${FB_PASSWORD:-"masterkey"}
FB_DATABASE_PATH=${FB_DATABASE_PATH:-"/data/DATABASE.FDB"}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-""}
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"firebird-backups"}
S3_REGION=${S3_REGION:-"us-east-1"}
INITDB_DIR=${INITDB_DIR:-"/docker-entrypoint-initdb.d"}

FILENAME=$1

if [ -z "$FILENAME" ]; then
    echo "Uso: $0 <arquivo_backup>"
    echo "Formatos aceitos: .fbk, .fbk.gz, .fbk.zip, .fbk.7z"
    exit 1
fi

# Remove um preparo anterior para não restaurar um backup obsoleto no próximo start
rm -f "$INITDB_DIR"/10-restore-*.sh "$INITDB_DIR"/*.fbk

fb_download_backup "$FILENAME" "$INITDB_DIR" || exit 1

FBK_FILE=$(fb_extract_backup "$INITDB_DIR/$FILENAME") || exit 1

INIT_SCRIPT="$INITDB_DIR/10-restore-$(basename "$FBK_FILE" .fbk).sh"

cat > "$INIT_SCRIPT" <<EOF
#!/bin/sh
# Gerado por restore2entrypoint.sh — executado pelo entrypoint da imagem Firebird
# na primeira inicialização do servidor.
set -e

FBK_FILE="$FBK_FILE"
FB_DATABASE_PATH="$FB_DATABASE_PATH"

if [ -f "\$FB_DATABASE_PATH" ]; then
    echo "Banco já existe em \$FB_DATABASE_PATH — restore ignorado."
    exit 0
fi

echo "Restaurando \$FBK_FILE em \$FB_DATABASE_PATH..."
gbak -c -v "\$FBK_FILE" "\$FB_DATABASE_PATH" -user "$FB_USER" -pass "$FB_PASSWORD"
echo "Restore concluído."
EOF

chmod +x "$INIT_SCRIPT"

echo "Backup preparado para restauração automática:"
echo "  backup:  $FBK_FILE"
echo "  script:  $INIT_SCRIPT"
echo "O servidor Firebird restaura o banco no próximo start, se $FB_DATABASE_PATH ainda não existir."
echo "Atenção: $INIT_SCRIPT contém a senha do banco e fica no volume compartilhado."
