#!/bin/bash

FB_HOST=${FB_HOST:-"localhost"}
FB_PORT=${FB_PORT:-"3050"}
FB_USER=${FB_USER:-"SYSDBA"}
FB_PASSWORD=${FB_PASSWORD:-"masterkey"}
FB_DATABASE_PATH=${FB_DATABASE_PATH:-"/data/DATABASE.FDB"}
BACKUP_DIR=${BACKUP_DIR:-"/data/backups"}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-""}
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"firebird-backups"}
S3_PARAMS=${S3_PARAMS:-""}
S3_REGION=${S3_REGION:-"us-east-1"}
# Compression type: gzip, tgz, 7zip, 7z, zip, none (default: gzip for backward compatibility)
COMPRESSION_TYPE=${COMPRESSION_TYPE:-"gzip"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "Iniciando backup do Firebird..."

DB_NAME=$(basename "$FB_DATABASE_PATH" .FDB)
FB_HOST_CLEAN="${FB_HOST%%:*}"
BACKUP_FILE_FBK="$BACKUP_DIR/${FB_HOST_CLEAN}_${DB_NAME}_${TIMESTAMP}.fbk"

# Determine file extension and archive filename based on compression type
case "$COMPRESSION_TYPE" in
    7z|7zip)
        EXT="fbk.7z"
        ;;
    zip)
        EXT="fbk.zip"
        ;;
    none|"")
        EXT="fbk"
        ;;
    gzip|tgz|*)
        EXT="fbk.gz"
        ;;
esac
ARCHIVE_FILE="$BACKUP_DIR/${FB_HOST_CLEAN}_${DB_NAME}_${TIMESTAMP}.$EXT"

echo "Backup: $DB_NAME"
echo "Conectando em: $FB_HOST:$FB_PORT:$FB_DATABASE_PATH"

if gbak -b -v -g -se "$FB_HOST:$FB_PORT" "$FB_DATABASE_PATH" "$BACKUP_FILE_FBK" -user "$FB_USER" -pass "$FB_PASSWORD"; then
    echo "Backup criado com sucesso: $BACKUP_FILE_FBK"
    
    # Apply compression based on COMPRESSION_TYPE
    echo "Aplicando compressão ($COMPRESSION_TYPE)..."
    case "$COMPRESSION_TYPE" in
        7z|7zip)
            if command -v 7z >/dev/null 2>&1; then
                7z a -t7z "$ARCHIVE_FILE" "$BACKUP_FILE_FBK"
            else
                echo "Erro: 7z não encontrado. Instale p7zip-full"
                exit 1
            fi
            ;;
        zip)
            if command -v zip >/dev/null 2>&1; then
                zip -j "$ARCHIVE_FILE" "$BACKUP_FILE_FBK"
            else
                echo "Erro: zip não encontrado. Instale zip"
                exit 1
            fi
            ;;
        none|"")
            cp "$BACKUP_FILE_FBK" "$ARCHIVE_FILE"
            ;;
        gzip|tgz|*)
            gzip -c "$BACKUP_FILE_FBK" > "$ARCHIVE_FILE"
            ;;
    esac
    
    # Check if compression was successful
    if [ $? -eq 0 ]; then
        echo "Compressão concluída: $ARCHIVE_FILE"
        
        # Remove original .fbk file if compression was applied
        if [ "$COMPRESSION_TYPE" != "none" ] && [ "$COMPRESSION_TYPE" != "" ]; then
            rm "$BACKUP_FILE_FBK"
        fi
        
        if [ -n "$S3_BUCKET_NAME" ]; then
            echo "Enviando para S3..."
            if aws s3 cp "$ARCHIVE_FILE" "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/" --region "$S3_REGION" --storage-class GLACIER_IR $S3_PARAMS; then
                echo "Backup enviado para S3 com sucesso"
            else
                echo "Erro ao enviar backup para S3"
                exit 1
            fi
        fi
        # Remove local archive if DELETE_LOCAL_AFTER_UPLOAD is true
        case "${DELETE_LOCAL_AFTER_UPLOAD:-true}" in
            1|true|TRUE|True|y|Y|yes|YES|Yes)
                echo "Flag DELETE_LOCAL_AFTER_UPLOAD ativa: arquivo será removido após envio."
                rm "$ARCHIVE_FILE"
                echo "Arquivo local removido"
                ;;
            *)
                echo "Flag DELETE_LOCAL_AFTER_UPLOAD desativada: mantendo arquivo original."
                ;;
        esac
    else
        echo "Erro na compressão"
        [ -f "$BACKUP_FILE_FBK" ] && rm "$BACKUP_FILE_FBK"
        [ -f "$ARCHIVE_FILE" ] && rm "$ARCHIVE_FILE"
        exit 1
    fi
else
    echo "Erro ao criar backup do banco $DB_NAME"
    [ -f "$BACKUP_FILE_FBK" ] && rm "$BACKUP_FILE_FBK"
    exit 1
fi

echo "Backup do Firebird concluído!"
