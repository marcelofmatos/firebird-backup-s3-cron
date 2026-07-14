#!/usr/bin/env bash

source /etc/environment
source /usr/local/lib/firebird-backup/common.sh

FB_HOST=${FB_HOST:-"localhost"}
FB_PORT=${FB_PORT:-"3050"}
FB_USER=${FB_USER:-"SYSDBA"}
FB_PASSWORD=${FB_PASSWORD:-"masterkey"}
FB_DATABASE_PATH=${FB_DATABASE_PATH:-"/data/DATABASE.FDB"}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-""}
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"firebird-backups"}
S3_REGION=${S3_REGION:-"us-east-1"}
RESTORE_DIR=${RESTORE_DIR:-"/restore"}

FILENAME=$1

if [ -z "$FILENAME" ]; then
    echo "Uso: $0 <arquivo_backup>"
    echo "Formatos aceitos: .fbk, .fbk.gz, .fbk.zip, .fbk.7z"
    echo "Exemplo: $0 firebird-server_DATABASE_20240101_120000.fbk.gz"
    echo "Use /usr/local/bin/list.sh para ver os backups disponíveis no S3."
    exit 1
fi

fb_download_backup "$FILENAME" "$RESTORE_DIR" || exit 1

FBK_FILE=$(fb_extract_backup "$RESTORE_DIR/$FILENAME") || exit 1

FB_HOST_CLEAN="${FB_HOST%%:*}"

echo "Arquivo de backup preparado: $FBK_FILE"
echo ""
echo "Para restaurar, execute dentro deste container:"
echo ""
echo "gbak -c -v \"$FBK_FILE\" \"$FB_HOST_CLEAN/$FB_PORT:$FB_DATABASE_PATH\" -user \"\$FB_USER\" -pass \"\$FB_PASSWORD\""
echo ""
echo "O gbak lê o .fbk aqui neste container e envia ao servidor Firebird pela rede (porta $FB_PORT),"
echo "por isso o arquivo NÃO precisa estar visível para o servidor."
echo "Se o banco de destino já existir, troque -c por -rep para sobrescrevê-lo."
