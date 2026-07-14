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

INITDB=/docker-entrypoint-initdb.d
WRAPPER="$INITDB/10-restore.sh"
PAYLOAD="$INITDB/restore"

echo "=== restore2entrypoint.sh: os 4 formatos ==="
for fmt in $FORMATS; do
    FILE=$(archive_for "$fmt")
    rm -rf "$INITDB"
    mkdir -p "$INITDB"
    if ! /usr/local/bin/restore2entrypoint.sh "$FILE" >/dev/null 2>&1; then
        echo "FAIL: $fmt — restore2entrypoint.sh saiu com erro"
        FAILED=1
        continue
    fi
    check_fbk "initdb $fmt" "$PAYLOAD/$BASE.fbk"

    if [ -x "$WRAPPER" ] && sh -n "$WRAPPER"; then
        echo "PASS: wrapper executável e com sintaxe válida ($fmt)"
    else
        echo "FAIL: wrapper ausente, não executável ou com sintaxe inválida ($fmt)"
        FAILED=1
    fi

    if [ -x "$PAYLOAD/fbk_restore.sh" ]; then
        echo "PASS: fbk_restore.sh copiado e executável ($fmt)"
    else
        echo "FAIL: fbk_restore.sh ausente ou não executável ($fmt)"
        FAILED=1
    fi

    # a senha do banco não pode acabar gravada no volume compartilhado
    if grep -rq "$FB_PASSWORD" "$INITDB" 2>/dev/null; then
        echo "FAIL: a senha do banco vazou para $INITDB ($fmt)"
        FAILED=1
    else
        echo "PASS: nenhuma senha gravada em $INITDB ($fmt)"
    fi

    # o entrypoint do Firebird executa os *.sh do primeiro nível: só o wrapper pode estar lá
    N_SH=$(find "$INITDB" -maxdepth 1 -name '*.sh' | wc -l)
    if [ "$N_SH" -ne 1 ]; then
        echo "FAIL: $N_SH scripts no primeiro nível de $INITDB (esperado só o wrapper) ($fmt)"
        FAILED=1
    fi
done

echo "=== o entrypoint do Firebird executa o wrapper e o banco é restaurado ==="
# Simula o container do Firebird: gbak stub cria o banco a partir do .fbk,
# e a senha vem do ambiente do servidor (FIREBIRD_ROOT_PASSWORD), não do wrapper.
cat > /usr/local/bin/gbak <<'EOF'
#!/bin/bash
echo "$@" > /tmp/gbak-args
FBK=${@: -2:1}
DB=${@: -1}
mkdir -p "$(dirname "$DB")"
cp "$FBK" "$DB"
EOF
chmod +x /usr/local/bin/gbak

rm -f /data/DATABASE.FDB /tmp/gbak-args
if env -i PATH="$PATH" FIREBIRD_ROOT_PASSWORD=senha-do-servidor "$WRAPPER" >/dev/null 2>&1; then
    check_fbk "banco restaurado pelo wrapper" /data/DATABASE.FDB
else
    echo "FAIL: wrapper saiu com erro"
    FAILED=1
fi

if grep -q -- "-password senha-do-servidor" /tmp/gbak-args 2>/dev/null; then
    echo "PASS: gbak recebeu a senha do ambiente do servidor Firebird"
else
    echo "FAIL: gbak não recebeu a senha do servidor (args: $(cat /tmp/gbak-args 2>/dev/null))"
    FAILED=1
fi

echo "=== o wrapper não sobrescreve um banco já existente ==="
if env -i PATH="$PATH" FIREBIRD_ROOT_PASSWORD=senha-do-servidor "$WRAPPER" 2>&1 | grep -q "já existe"; then
    echo "PASS: restore ignorado quando o banco já existe"
else
    echo "FAIL: o wrapper deveria ignorar o restore com o banco já existente"
    FAILED=1
fi

echo "=== restore2entrypoint.sh: um novo preparo substitui o anterior ==="
/usr/local/bin/restore2entrypoint.sh "$BASE.fbk.gz" >/dev/null 2>&1
COUNT=$(find "$INITDB" -maxdepth 1 -name '*.sh' | wc -l)
FBK_COUNT=$(find "$PAYLOAD" -name '*.fbk' | wc -l)
if [ "$COUNT" -eq 1 ] && [ "$FBK_COUNT" -eq 1 ]; then
    echo "PASS: apenas 1 wrapper e 1 .fbk após novo preparo"
else
    echo "FAIL: $COUNT wrapper(s) e $FBK_COUNT .fbk após novo preparo (esperado 1 e 1)"
    FAILED=1
fi

echo "-----------------------------------"
[ "$FAILED" -eq 0 ] && echo "restore: TODOS OS TESTES PASSARAM" || echo "restore: HOUVE FALHAS"
exit "$FAILED"
