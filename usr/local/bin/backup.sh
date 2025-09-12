#!/bin/bash

FB_HOST=${FB_HOST:-"localhost"}
FB_PORT=${FB_PORT:-"3050"}
FB_USER=${FB_USER:-"SYSDBA"}
FB_PASSWORD=${FB_PASSWORD:-"masterkey"}
FB_DATABASE_PATH=${FB_DATABASE_PATH:-"/data/DATABASE.FDB"}
BACKUP_DIR=${BACKUP_DIR:-"/data/backups"}
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"firebird-backups"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "Iniciando backup do Firebird..."

DB_NAME=$(basename "$FB_DATABASE_PATH" .FDB)
BACKUP_FILE_FBK="$BACKUP_DIR/${FB_HOST}_${DB_NAME}_${TIMESTAMP}.fbk"
BACKUP_FILE_GZ="$BACKUP_DIR/${FB_HOST}_${DB_NAME}_${TIMESTAMP}.fbk.gz"

echo "Backup: $DB_NAME"
echo "Conectando em: $FB_HOST:$FB_PORT:$FB_DATABASE_PATH"

if gbak -b -v -g -se "$FB_HOST:$FB_PORT" "$FB_DATABASE_PATH" "$BACKUP_FILE_FBK" -user "$FB_USER" -pass "$FB_PASSWORD"; then
    echo "Backup criado com sucesso: $BACKUP_FILE_FBK"
    
    echo "Compactando backup..."
    gzip "$BACKUP_FILE_FBK"
    
    echo "Enviando para S3..."
    if aws s3 cp "$BACKUP_FILE_GZ" "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/" --region "$S3_REGION"; then
        echo "Backup enviado para S3 com sucesso"
        rm "$BACKUP_FILE_GZ"
        echo "Arquivo local removido"
    else
        echo "Erro ao enviar backup para S3"
        rm "$BACKUP_FILE_GZ"
        exit 1
    fi
else
    echo "Erro ao criar backup do banco $DB_NAME"
    [ -f "$BACKUP_FILE_FBK" ] && rm "$BACKUP_FILE_FBK"
    exit 1
fi

echo "Backup do Firebird concluído!"
