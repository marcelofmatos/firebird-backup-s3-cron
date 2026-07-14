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
# O restore NUNCA sobrescreve FB_DATABASE_PATH: o banco nasce num caminho novo,
# e a troca pelo banco de produção fica a cargo do operador.
RESTORE_DATABASE_PATH=${RESTORE_DATABASE_PATH:-"${FB_DATABASE_PATH%.*}_RESTORE.FDB"}

EXTRACT_ONLY=false
FILENAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --extract-only)
            EXTRACT_ONLY=true
            ;;
        *)
            FILENAME=$1
            ;;
    esac
    shift
done

if [ -z "$FILENAME" ]; then
    echo "Uso: $0 [--extract-only] <arquivo_backup>"
    echo "Formatos aceitos: .fbk, .fbk.gz, .fbk.zip, .fbk.7z"
    echo "Exemplo: $0 firebird-server_DATABASE_20240101_120000.fbk.gz"
    echo ""
    echo "  --extract-only  baixa e descompacta o backup, imprime o comando gbak e não o executa"
    echo ""
    echo "Use /usr/local/bin/list.sh para ver os backups disponíveis no S3."
    exit 1
fi

fb_download_backup "$FILENAME" "$RESTORE_DIR" || exit 1

FBK_FILE=$(fb_extract_backup "$RESTORE_DIR/$FILENAME") || exit 1

FB_HOST_CLEAN="${FB_HOST%%:*}"
DB_TARGET="$FB_HOST_CLEAN/$FB_PORT:$RESTORE_DATABASE_PATH"

echo "Arquivo de backup preparado: $FBK_FILE"

if [ "$EXTRACT_ONLY" = true ]; then
    echo ""
    echo "Para restaurar, execute dentro deste container:"
    echo ""
    echo "gbak -c -v \"$FBK_FILE\" \"$DB_TARGET\" -user \"\$FB_USER\" -pass \"\$FB_PASSWORD\""
    echo ""
    echo "O gbak lê o .fbk aqui neste container e envia ao servidor Firebird pela rede (porta $FB_PORT),"
    echo "por isso o arquivo NÃO precisa estar visível para o servidor."
    exit 0
fi

echo "Restaurando em $RESTORE_DATABASE_PATH (no servidor $FB_HOST_CLEAN)..."

if ! gbak -c -v "$FBK_FILE" "$DB_TARGET" -user "$FB_USER" -pass "$FB_PASSWORD"; then
    echo "Erro ao restaurar o backup"
    echo "O banco em $FB_DATABASE_PATH não foi tocado."
    echo "Se $RESTORE_DATABASE_PATH já existir, remova-o no servidor ou aponte RESTORE_DATABASE_PATH para outro caminho."
    exit 1
fi

echo ""
echo "Restauração concluída: $RESTORE_DATABASE_PATH"
echo "O banco em $FB_DATABASE_PATH continua intacto e em uso."
echo ""
echo "Para promover o banco restaurado, rode DENTRO do container do Firebird:"
echo "  gfix -shut -force 30 -user <user> -password <senha> $FB_DATABASE_PATH"
echo "  mv $FB_DATABASE_PATH $FB_DATABASE_PATH.old"
echo "  mv $RESTORE_DATABASE_PATH $FB_DATABASE_PATH"
echo "Guarde o .old até confirmar que a aplicação subiu bem com o banco restaurado."
