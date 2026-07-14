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

EXTRACT_ONLY=false
ON_REMOTE=false
FILENAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --extract-only)
            EXTRACT_ONLY=true
            ;;
        --restore-on-remote)
            ON_REMOTE=true
            ;;
        *)
            FILENAME=$1
            ;;
    esac
    shift
done

if [ -z "$FILENAME" ]; then
    echo "Uso: $0 [--restore-on-remote] [--extract-only] <arquivo_backup>"
    echo "Formatos aceitos: .fbk, .fbk.gz, .fbk.zip, .fbk.7z"
    echo "Exemplo: $0 firebird-server_DATABASE_20240101_120000.fbk.gz"
    echo ""
    echo "Por padrão o banco é restaurado NESTE container, num arquivo local — o servidor"
    echo "Firebird não é envolvido, e o .fdb resultante é movido para ele depois."
    echo ""
    echo "  --restore-on-remote  cria o banco no servidor Firebird, pela rede. Exige que o"
    echo "                       usuário tenha o privilégio CREATE DATABASE e que a política"
    echo "                       DatabaseAccess do servidor permita o caminho de destino"
    echo "  --extract-only       baixa e descompacta o backup, imprime o comando gbak e sai"
    echo ""
    echo "Use /usr/local/bin/list.sh para ver os backups disponíveis no S3."
    exit 1
fi

DB_NAME=$(basename "${FB_DATABASE_PATH%.*}")

# O banco de produção (FB_DATABASE_PATH) NUNCA é o destino: a restauração vai para um
# arquivo novo, e a troca fica a cargo do operador.
if [ "$ON_REMOTE" = true ]; then
    RESTORE_DATABASE_PATH=${RESTORE_DATABASE_PATH:-"${FB_DATABASE_PATH%.*}_RESTORE.FDB"}
    FB_HOST_CLEAN="${FB_HOST%%:*}"
    DB_TARGET="$FB_HOST_CLEAN/$FB_PORT:$RESTORE_DATABASE_PATH"
else
    RESTORE_DATABASE_PATH=${RESTORE_DATABASE_PATH:-"$RESTORE_DIR/${DB_NAME}_RESTORE.FDB"}
    DB_TARGET="$RESTORE_DATABASE_PATH"
fi

fb_download_backup "$FILENAME" "$RESTORE_DIR" || exit 1

FBK_FILE=$(fb_extract_backup "$RESTORE_DIR/$FILENAME") || exit 1

echo "Arquivo de backup preparado: $FBK_FILE"

if [ "$EXTRACT_ONLY" = true ]; then
    echo ""
    echo "Para restaurar, execute dentro deste container:"
    echo ""
    echo "gbak -c -v \"$FBK_FILE\" \"$DB_TARGET\" -user \"\$FB_USER\" -pass \"\$FB_PASSWORD\""
    exit 0
fi

if [ "$ON_REMOTE" = true ]; then
    echo "Restaurando em $RESTORE_DATABASE_PATH (no servidor $FB_HOST_CLEAN)..."
else
    echo "Restaurando localmente em $RESTORE_DATABASE_PATH..."
fi

if ! gbak -c -v "$FBK_FILE" "$DB_TARGET" -user "$FB_USER" -pass "$FB_PASSWORD"; then
    echo "Erro ao restaurar o backup"
    echo "O banco em $FB_DATABASE_PATH não foi tocado."
    echo "Se $RESTORE_DATABASE_PATH já existir, remova-o ou aponte RESTORE_DATABASE_PATH para outro caminho."
    exit 1
fi

echo ""
echo "Restauração concluída: $RESTORE_DATABASE_PATH"
echo "O banco em $FB_DATABASE_PATH continua intacto e em uso."
echo ""

if [ "$ON_REMOTE" = true ]; then
    echo "Para promover o banco restaurado, rode DENTRO do container do Firebird:"
    echo "  gfix -shut -force 30 -user <user> -password <senha> $FB_DATABASE_PATH"
    echo "  mv $FB_DATABASE_PATH $FB_DATABASE_PATH.old"
    echo "  mv $RESTORE_DATABASE_PATH $FB_DATABASE_PATH"
else
    echo "O banco restaurado está NESTE container. Para promovê-lo:"
    echo "  1. leve o arquivo para o servidor (pule se $RESTORE_DIR for volume compartilhado):"
    echo "     docker cp <este-container>:$RESTORE_DATABASE_PATH - | docker cp - <container-firebird>:/"
    echo "  2. dentro do container do Firebird:"
    echo "     gfix -shut -force 30 -user <user> -password <senha> $FB_DATABASE_PATH"
    echo "     mv $FB_DATABASE_PATH $FB_DATABASE_PATH.old"
    echo "     mv <caminho-do-restaurado> $FB_DATABASE_PATH"
    echo "     chown firebird:firebird $FB_DATABASE_PATH && chmod 660 $FB_DATABASE_PATH"
fi
echo "Guarde o .old até confirmar que a aplicação subiu bem com o banco restaurado."
