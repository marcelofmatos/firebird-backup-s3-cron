#!/usr/bin/env bash

source /etc/environment
source /usr/local/lib/firebird-backup/common.sh

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

# O .fbk e o fbk_restore.sh ficam num subdiretório: o entrypoint do Firebird executa
# apenas os *.sh do primeiro nível de INITDB_DIR, e quem dispara o restore é o wrapper.
PAYLOAD_DIR="$INITDB_DIR/restore"
WRAPPER="$INITDB_DIR/10-restore.sh"

# Remove um preparo anterior para não restaurar um backup obsoleto no próximo start
rm -rf "$PAYLOAD_DIR" "$WRAPPER"

fb_download_backup "$FILENAME" "$PAYLOAD_DIR" || exit 1

FBK_FILE=$(fb_extract_backup "$PAYLOAD_DIR/$FILENAME") || exit 1

cp /usr/local/bin/fbk_restore.sh "$PAYLOAD_DIR/fbk_restore.sh"
chmod +x "$PAYLOAD_DIR/fbk_restore.sh"

# O wrapper roda dentro do container do Firebird. As credenciais vêm do ambiente DELE
# (FIREBIRD_USER / FIREBIRD_PASSWORD / FIREBIRD_ROOT_PASSWORD), nunca gravadas aqui.
cat > "$WRAPPER" <<EOF
#!/bin/sh
# Gerado por restore2entrypoint.sh — executado pelo entrypoint da imagem Firebird.
set -e

export FBK_FILE="$FBK_FILE"
export DB_PATH="$FB_DATABASE_PATH"

if [ -z "\${FIREBIRD_PASSWORD:-}" ] && [ -n "\${FIREBIRD_ROOT_PASSWORD:-}" ]; then
    export FIREBIRD_PASSWORD="\$FIREBIRD_ROOT_PASSWORD"
fi

exec "$PAYLOAD_DIR/fbk_restore.sh"
EOF

chmod +x "$WRAPPER"

echo "Backup preparado para restauração automática:"
echo "  backup:  $FBK_FILE"
echo "  restore: $PAYLOAD_DIR/fbk_restore.sh"
echo "  wrapper: $WRAPPER"
echo "O servidor Firebird restaura o banco no próximo start, se $FB_DATABASE_PATH ainda não existir."
echo "As credenciais usadas são as do próprio container do Firebird (FIREBIRD_USER/FIREBIRD_PASSWORD)."
