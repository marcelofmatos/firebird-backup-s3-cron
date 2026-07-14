#!/usr/bin/env bash
# Testes do restore.sh e do restore2entrypoint.sh — executados DENTRO da imagem (ver tests/run.sh).
# aws é substituído por um stub: o "S3" é o diretório local /fake-s3.
set -u

FAILED=0
FAKE_S3=/fake-s3/bucket/dir
mkdir -p "$FAKE_S3"

cat > /usr/local/bin/aws <<'EOF'
#!/bin/bash
SRC=$3; DEST=$4
cp "/fake-s3/${SRC#s3://}" "$DEST" || exit 1
echo "download: $SRC to $DEST"
EOF
chmod +x /usr/local/bin/aws

export S3_BUCKET_NAME=bucket S3_DIRECTORY_NAME=dir S3_REGION=sa-east-1
export FB_HOST=firebird-server FB_PORT=3050 FB_DATABASE_PATH=/data/DATABASE.FDB
export FB_USER=SYSDBA FB_PASSWORD=segredo

# Publica no "S3" um backup em cada formato que o backup.sh produz,
# com a mesma convenção de nome: <FB_HOST>_<DB>_<timestamp>.<ext>
WORK=$(mktemp -d)
BASE="firebird-server_DATABASE_20240101_120000"
printf 'conteudo-fbk' > "$WORK/$BASE.fbk"
gzip -c "$WORK/$BASE.fbk" > "$FAKE_S3/$BASE.fbk.gz"
7z a -t7z "$FAKE_S3/$BASE.fbk.7z" "$WORK/$BASE.fbk" >/dev/null
zip -j "$FAKE_S3/$BASE.fbk.zip" "$WORK/$BASE.fbk" >/dev/null
cp "$WORK/$BASE.fbk" "$FAKE_S3/$BASE.fbk"

FORMATS="gz 7z zip none"
archive_for() { # archive_for <formato>
    [ "$1" = none ] && echo "$BASE.fbk" || echo "$BASE.fbk.$1"
}

check_fbk() { # check_fbk <label> <caminho_esperado>
    if [ -f "$2" ] && [ "$(cat "$2")" = "conteudo-fbk" ]; then
        echo "PASS: $1 -> $2"
    else
        echo "FAIL: $1 -> $2 (ausente ou conteúdo errado)"
        FAILED=1
    fi
}

echo "=== restore.sh: os 4 formatos gerados pelo backup.sh ==="
for fmt in $FORMATS; do
    FILE=$(archive_for "$fmt")
    rm -rf /restore
    if ! OUT=$(RESTORE_DIR=/restore /usr/local/bin/restore.sh "$FILE" 2>&1); then
        echo "FAIL: $fmt — restore.sh saiu com erro"
        echo "$OUT"
        FAILED=1
        continue
    fi
    check_fbk "restore.sh $fmt" "/restore/$BASE.fbk"

    # o comando de restauração precisa ser impresso, apontando para o .fbk descompactado
    if echo "$OUT" | grep -q "^gbak -c -v \"/restore/$BASE.fbk\""; then
        echo "PASS: restore.sh $fmt imprimiu o comando gbak"
    else
        echo "FAIL: restore.sh $fmt não imprimiu o comando gbak esperado"
        FAILED=1
    fi

    # o arquivo compactado não pode ficar para trás
    if [ "$fmt" != none ] && [ -f "/restore/$FILE" ]; then
        echo "FAIL: restore.sh $fmt não removeu o arquivo compactado"
        FAILED=1
    fi
done

echo "=== restore2entrypoint.sh: os 4 formatos ==="
for fmt in $FORMATS; do
    FILE=$(archive_for "$fmt")
    rm -rf /docker-entrypoint-initdb.d
    mkdir -p /docker-entrypoint-initdb.d
    if ! /usr/local/bin/restore2entrypoint.sh "$FILE" >/dev/null 2>&1; then
        echo "FAIL: $fmt — restore2entrypoint.sh saiu com erro"
        FAILED=1
        continue
    fi
    check_fbk "initdb $fmt" "/docker-entrypoint-initdb.d/$BASE.fbk"

    INIT="/docker-entrypoint-initdb.d/10-restore-$BASE.sh"
    if [ -x "$INIT" ] && sh -n "$INIT"; then
        echo "PASS: init script executável e com sintaxe válida ($fmt)"
    else
        echo "FAIL: init script ausente, não executável ou com sintaxe inválida ($fmt)"
        FAILED=1
    fi
    if ! grep -q "gbak -c -v" "$INIT" 2>/dev/null; then
        echo "FAIL: init script não contém o comando de restauração ($fmt)"
        FAILED=1
    fi
done

echo "=== restore2entrypoint.sh: um novo preparo substitui o anterior ==="
/usr/local/bin/restore2entrypoint.sh "$BASE.fbk.gz" >/dev/null 2>&1
COUNT=$(ls /docker-entrypoint-initdb.d/10-restore-*.sh 2>/dev/null | wc -l)
if [ "$COUNT" -eq 1 ]; then
    echo "PASS: apenas 1 init script após novo preparo"
else
    echo "FAIL: $COUNT init scripts em /docker-entrypoint-initdb.d (esperado 1)"
    FAILED=1
fi

echo "-----------------------------------"
[ "$FAILED" -eq 0 ] && echo "restore: TODOS OS TESTES PASSARAM" || echo "restore: HOUVE FALHAS"
exit "$FAILED"
