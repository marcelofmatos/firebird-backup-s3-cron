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

# stub gbak: registra os argumentos e "cria" o banco no caminho da string de conexão
# (host/porta:/caminho/do.fdb). Falha se o arquivo de destino já existir, como o gbak -c faz.
cat > /usr/local/bin/gbak <<'EOF'
#!/bin/bash
echo "$@" > /tmp/gbak-args
for arg in "$@"; do
    case "$arg" in
        */*:/*) DB="${arg#*:}" ;;
    esac
done
if [ -f "$DB" ]; then
    echo "gbak: ERROR: database $DB already exists" >&2
    exit 1
fi
mkdir -p "$(dirname "$DB")"
printf 'banco-restaurado' > "$DB"
EOF
chmod +x /usr/local/bin/gbak

echo "=== restore.sh: restaura os 4 formatos num caminho novo ==="
for fmt in $FORMATS; do
    FILE=$(archive_for "$fmt")
    rm -rf /restore /data
    rm -f /tmp/gbak-args
    printf 'banco-de-producao' > /tmp/prod.fdb
    mkdir -p /data && cp /tmp/prod.fdb "$FB_DATABASE_PATH"

    if ! OUT=$(RESTORE_DIR=/restore /usr/local/bin/restore.sh "$FILE" 2>&1); then
        echo "FAIL: $fmt — restore.sh saiu com erro"
        echo "$OUT"
        FAILED=1
        continue
    fi
    check_fbk "restore.sh $fmt descompactou" "/restore/$BASE.fbk"

    # o gbak precisa ter sido executado sobre o .fbk, num caminho novo
    if grep -q -- "-c -v /restore/$BASE.fbk firebird-server/3050:/data/DATABASE_RESTORE.FDB" /tmp/gbak-args 2>/dev/null; then
        echo "PASS: restore.sh $fmt executou o gbak no caminho novo"
    else
        echo "FAIL: restore.sh $fmt não chamou o gbak como esperado (args: $(cat /tmp/gbak-args 2>/dev/null))"
        FAILED=1
    fi

    if [ -f /data/DATABASE_RESTORE.FDB ]; then
        echo "PASS: restore.sh $fmt criou o banco restaurado"
    else
        echo "FAIL: restore.sh $fmt não criou o banco restaurado"
        FAILED=1
    fi

    # o banco de produção não pode ser tocado
    if [ "$(cat "$FB_DATABASE_PATH")" = "banco-de-producao" ]; then
        echo "PASS: restore.sh $fmt não tocou em $FB_DATABASE_PATH"
    else
        echo "FAIL: restore.sh $fmt alterou o banco de produção!"
        FAILED=1
    fi

    # o arquivo compactado não pode ficar para trás
    if [ "$fmt" != none ] && [ -f "/restore/$FILE" ]; then
        echo "FAIL: restore.sh $fmt não removeu o arquivo compactado"
        FAILED=1
    fi
done

echo "=== restore.sh: RESTORE_DATABASE_PATH sobrescreve o destino ==="
rm -rf /restore /data
if RESTORE_DIR=/restore RESTORE_DATABASE_PATH=/data/OUTRO.FDB /usr/local/bin/restore.sh "$BASE.fbk.gz" >/dev/null 2>&1 && [ -f /data/OUTRO.FDB ]; then
    echo "PASS: banco restaurado em /data/OUTRO.FDB"
else
    echo "FAIL: RESTORE_DATABASE_PATH não foi respeitado"
    FAILED=1
fi

echo "=== restore.sh --extract-only: prepara o .fbk e não executa o gbak ==="
# preserva o /data/OUTRO.FDB criado acima, usado pelo teste seguinte
rm -rf /restore
rm -f /tmp/gbak-args /data/DATABASE_RESTORE.FDB
if OUT=$(RESTORE_DIR=/restore /usr/local/bin/restore.sh --extract-only "$BASE.fbk.gz" 2>&1); then
    check_fbk "--extract-only descompactou" "/restore/$BASE.fbk"
    if echo "$OUT" | grep -q "^gbak -c -v \"/restore/$BASE.fbk\" \"firebird-server/3050:/data/DATABASE_RESTORE.FDB\""; then
        echo "PASS: --extract-only imprimiu o comando gbak"
    else
        echo "FAIL: --extract-only não imprimiu o comando gbak esperado"
        FAILED=1
    fi
    if [ -f /tmp/gbak-args ] || [ -f /data/DATABASE_RESTORE.FDB ]; then
        echo "FAIL: --extract-only executou o gbak"
        FAILED=1
    else
        echo "PASS: --extract-only não executou o gbak"
    fi
else
    echo "FAIL: restore.sh --extract-only saiu com erro"
    FAILED=1
fi

echo "=== restore.sh: destino já existente aborta sem destruir nada ==="
rm -rf /restore
if RESTORE_DIR=/restore RESTORE_DATABASE_PATH=/data/OUTRO.FDB /usr/local/bin/restore.sh "$BASE.fbk.gz" >/dev/null 2>&1; then
    echo "FAIL: restore.sh deveria falhar quando o destino já existe"
    FAILED=1
else
    if [ "$(cat /data/OUTRO.FDB)" = "banco-restaurado" ]; then
        echo "PASS: restore.sh falhou e preservou o banco existente"
    else
        echo "FAIL: o banco existente foi corrompido"
        FAILED=1
    fi
fi

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

echo "=== TEST_CONNECTION usa o isql disponível na imagem ==="
# stub em /usr/local/bin (vem antes de /usr/bin no PATH) para sombrear o isql-fb real
cat > /usr/local/bin/isql-fb <<'EOF'
#!/bin/bash
echo "$@" > /tmp/isql-args
EOF
chmod +x /usr/local/bin/isql-fb

rm -f /data/DATABASE.FDB /tmp/isql-args
if env -i PATH="$PATH" FIREBIRD_ROOT_PASSWORD=senha-do-servidor TEST_CONNECTION=true "$WRAPPER" 2>&1 | grep -q "Teste de conectividade: OK"; then
    echo "PASS: teste de conectividade executado após o restore"
else
    echo "FAIL: teste de conectividade não rodou ou falhou"
    FAILED=1
fi
if [ -f /tmp/isql-args ]; then
    echo "PASS: isql encontrado via PATH (args: $(cat /tmp/isql-args))"
else
    echo "FAIL: o isql do PATH não foi chamado"
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
