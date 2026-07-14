#!/usr/bin/env bash
# Testes da imagem — executados DENTRO dela (ver tests/run.sh).
# Garantem que as ferramentas existem e que o gbak é compatível com o servidor.
set -u

FAILED=0

# O gbak do cliente precisa ser >= ao do servidor: um gbak 3.0 não lê um backup gerado
# por um servidor 5.0 ("Expected backup version 1..10. Found 11"). Um gbak novo lê os antigos.
echo "=== gbak compatível com Firebird 5 ==="
GBAK_VERSION=$(gbak -z 2>&1 | grep -m1 'LI-V')
GBAK_MAJOR=$(echo "$GBAK_VERSION" | sed -n 's/.*LI-V\([0-9]*\)\..*/\1/p')
if [ -n "$GBAK_MAJOR" ] && [ "$GBAK_MAJOR" -ge 5 ]; then
    echo "PASS: $GBAK_VERSION"
else
    echo "FAIL: gbak major=$GBAK_MAJOR, esperado >= 5 ($GBAK_VERSION)"
    FAILED=1
fi

echo "=== ferramentas necessárias ==="
for tool in gbak isql-fb gfix gstat aws gzip zip unzip 7z cron crontab; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "PASS: $tool -> $(command -v "$tool")"
    else
        echo "FAIL: $tool não encontrado"
        FAILED=1
    fi
done

echo "=== os scripts do projeto têm precedência no PATH ==="
# as suítes de backup/restore instalam stubs em /usr/local/bin: se /opt/firebird/bin viesse
# antes, os stubs não sombreariam o gbak real e os testes rodariam contra o binário de verdade
case ":$PATH:" in
    *:/usr/local/bin:*)
        FIREBIRD_POS=$(echo "$PATH" | tr ':' '\n' | grep -n '^/opt/firebird/bin$' | cut -d: -f1)
        LOCAL_POS=$(echo "$PATH" | tr ':' '\n' | grep -n '^/usr/local/bin$' | cut -d: -f1)
        if [ -z "$FIREBIRD_POS" ] || [ "$LOCAL_POS" -lt "$FIREBIRD_POS" ]; then
            echo "PASS: /usr/local/bin vem antes de /opt/firebird/bin"
        else
            echo "FAIL: /opt/firebird/bin vem antes de /usr/local/bin no PATH"
            FAILED=1
        fi
        ;;
    *)
        echo "FAIL: /usr/local/bin não está no PATH"
        FAILED=1
        ;;
esac

echo "=== o servidor Firebird não sobe nesta imagem ==="
# a base é a imagem oficial do Firebird: o entrypoint dela precisa estar desativado,
# senão o container serviria banco em vez de rodar o cron de backup
if pgrep -x firebird >/dev/null 2>&1; then
    echo "FAIL: o servidor Firebird está rodando no container de backup"
    FAILED=1
else
    echo "PASS: nenhum servidor Firebird rodando"
fi

echo "-----------------------------------"
[ "$FAILED" -eq 0 ] && echo "imagem: TODOS OS TESTES PASSARAM" || echo "imagem: HOUVE FALHAS"
exit "$FAILED"
