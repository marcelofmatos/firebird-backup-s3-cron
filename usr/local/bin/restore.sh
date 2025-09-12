#!/bin/bash

FILENAME=$1

if [ -z "$FILENAME" ]; then
    echo "Uso: $0 <arquivo_backup.fbk.gz>"
    echo "Exemplo: $0 backup_20240101_120000.fbk.gz"
    exit 1
fi

RESTORE_DIR="/restore"
mkdir -p "$RESTORE_DIR"

echo "Baixando backup do S3..."
if aws s3 cp "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$FILENAME" "$RESTORE_DIR/$FILENAME" --region "$S3_REGION"; then
    echo "Backup baixado com sucesso"
    
    cd "$RESTORE_DIR"
    
    if [[ "$FILENAME" == *.gz ]]; then
        echo "Descompactando arquivo..."
        gunzip "$FILENAME"
        FILENAME=${FILENAME%%.gz}
    fi
    
    echo "Arquivo de backup preparado: $RESTORE_DIR/$FILENAME"
    echo "Para restaurar use:"
    echo "gbak -c -v -se $FB_HOST:$FB_PORT $RESTORE_DIR/$FILENAME $FB_DATABASE_PATH -user $FB_USER -pass $FB_PASSWORD"
    
else
    echo "Erro ao baixar backup do S3"
    exit 1
fi
