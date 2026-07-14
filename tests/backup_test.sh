#!/usr/bin/env bash
# Testes do backup.sh — executados DENTRO da imagem (ver tests/run.sh).
# gbak e aws são substituídos por stubs: o "S3" é o diretório local /fake-s3.
set -u

FAILED=0
mkdir -p /fake-s3/bucket/dir

# stub gbak: gbak -b -v -g -se HOST:PORT DB BACKUPFILE -user U -pass P
cat > /usr/local/bin/gbak <<'EOF'
#!/bin/bash
printf 'conteudo-fbk' > "$7"
echo "gbak: backup gravado em $7"
EOF

# stub aws: falha o upload quando AWS_FAIL=1
cat > /usr/local/bin/aws <<'EOF'
#!/bin/bash
[ "${AWS_FAIL:-0}" = "1" ] && { echo "upload failed" >&2; exit 1; }
SRC=$3; DEST=$4
cp "$SRC" "/fake-s3/${DEST#s3://}" || exit 1
echo "upload: $SRC to $DEST"
EOF
chmod +x /usr/local/bin/gbak /usr/local/bin/aws

export FB_HOST=firebird-server FB_PORT=3050 FB_DATABASE_PATH=/data/DATABASE.FDB
export FB_USER=SYSDBA FB_PASSWORD=segredo S3_DIRECTORY_NAME=dir S3_REGION=sa-east-1
export BACKUP_DIR=/data/backups

reset() { rm -rf /data/backups /fake-s3/bucket/dir; mkdir -p /fake-s3/bucket/dir; }

# expect <label> <kept|gone> <yes|no>  — arquivos esperados em BACKUP_DIR e no S3
expect() {
    local label=$1 local_expect=$2 s3_expect=$3 ok=1 n_local n_s3
    n_local=$(ls /data/backups/*.fbk* 2>/dev/null | wc -l)
    n_s3=$(ls /fake-s3/bucket/dir 2>/dev/null | wc -l)
    [ "$local_expect" = kept ] && [ "$n_local" -ne 1 ] && ok=0
    [ "$local_expect" = gone ] && [ "$n_local" -ne 0 ] && ok=0
    [ "$s3_expect" = yes ] && [ "$n_s3" -ne 1 ] && ok=0
    [ "$s3_expect" = no ] && [ "$n_s3" -ne 0 ] && ok=0
    if [ "$ok" = 1 ]; then
        echo "PASS: $label (local=$n_local, s3=$n_s3)"
    else
        echo "FAIL: $label — esperado local=$local_expect s3=$s3_expect, obtido local=$n_local s3=$n_s3"
        FAILED=1
    fi
}

echo "=== 1) sem S3_BUCKET_NAME: o backup não pode ser apagado ==="
reset
S3_BUCKET_NAME="" /usr/local/bin/backup.sh >/dev/null 2>&1
expect "backup local preservado quando não há bucket" kept no

echo "=== 2) upload ok, DELETE_LOCAL_AFTER_UPLOAD default (true) ==="
reset
S3_BUCKET_NAME=bucket /usr/local/bin/backup.sh >/dev/null 2>&1
expect "arquivo local removido após upload confirmado" gone yes

echo "=== 3) upload ok, DELETE_LOCAL_AFTER_UPLOAD=false ==="
reset
S3_BUCKET_NAME=bucket DELETE_LOCAL_AFTER_UPLOAD=false /usr/local/bin/backup.sh >/dev/null 2>&1
expect "arquivo local mantido com a flag desativada" kept yes

echo "=== 4) upload falha: o backup não pode ser apagado ==="
reset
S3_BUCKET_NAME=bucket AWS_FAIL=1 /usr/local/bin/backup.sh >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "PASS: backup.sh saiu com erro (rc=$RC)"
else
    echo "FAIL: backup.sh deveria falhar quando o upload falha"
    FAILED=1
fi
expect "arquivo local preservado após falha no upload" kept no

echo "=== 5) COMPRESSION_TYPE: gzip, 7zip, zip e none ==="
for ct in gzip 7zip zip none; do
    reset
    if ! COMPRESSION_TYPE=$ct S3_BUCKET_NAME=bucket /usr/local/bin/backup.sh >/dev/null 2>&1; then
        echo "FAIL: $ct — backup.sh saiu com erro"
        FAILED=1
        continue
    fi
    UPLOADED=$(ls /fake-s3/bucket/dir 2>/dev/null)
    if [ -n "$UPLOADED" ]; then
        echo "PASS: $ct -> $UPLOADED"
    else
        echo "FAIL: $ct não gerou arquivo no S3"
        FAILED=1
    fi
    # o .fbk intermediário não pode sobrar quando há compressão
    if [ "$ct" != none ] && ls /data/backups/*.fbk >/dev/null 2>&1; then
        echo "FAIL: $ct deixou o .fbk intermediário em $BACKUP_DIR"
        FAILED=1
    fi
done

echo "-----------------------------------"
[ "$FAILED" -eq 0 ] && echo "backup: TODOS OS TESTES PASSARAM" || echo "backup: HOUVE FALHAS"
exit "$FAILED"
