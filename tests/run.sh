#!/usr/bin/env bash
# Runner dos testes: constrói a imagem e executa cada suíte dentro dela.
# As suítes usam stubs de gbak e aws — nenhum servidor Firebird ou bucket S3 real é necessário.
#
# Uso: ./tests/run.sh
set -u

IMAGE=${TEST_IMAGE:-"firebird-backup-s3-cron:test"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "Construindo $IMAGE..."
if ! docker build -q -t "$IMAGE" "$ROOT" >/dev/null; then
    echo "Erro ao construir a imagem"
    exit 1
fi

FAILED=0
for suite in backup restore; do
    echo ""
    echo "########## suíte: $suite ##########"
    if ! docker run --rm -v "$ROOT/tests:/tests:ro" --entrypoint bash "$IMAGE" "/tests/${suite}_test.sh"; then
        FAILED=1
    fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "✅ Todas as suítes passaram"
else
    echo "❌ Houve falhas"
fi
exit "$FAILED"
