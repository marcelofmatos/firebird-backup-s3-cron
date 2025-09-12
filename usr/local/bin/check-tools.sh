#!/bin/bash

echo "Verificando instalação dos utilitários do Firebird..."
echo "==========================================="

echo "1. Verificando gbak (backup utility):"
if command -v gbak >/dev/null 2>&1; then
    echo "✓ gbak encontrado em: $(which gbak)"
    gbak -? 2>&1 | head -n 3
else
    echo "✗ gbak não encontrado"
fi

echo ""
echo "2. Verificando isql-fb (interactive SQL):"
if command -v isql-fb >/dev/null 2>&1; then
    echo "✓ isql-fb encontrado em: $(which isql-fb)"
    isql-fb -? 2>&1 | head -n 3
else
    echo "✗ isql-fb não encontrado"
fi

echo ""
echo "3. Verificando gstat (statistics):"
if command -v gstat >/dev/null 2>&1; then
    echo "✓ gstat encontrado em: $(which gstat)"
    gstat -? 2>&1 | head -n 3
else
    echo "✗ gstat não encontrado"
fi

echo ""
echo "4. Verificando gsec (user management):"
if command -v gsec >/dev/null 2>&1; then
    echo "✓ gsec encontrado em: $(which gsec)"
    gsec -? 2>&1 | head -n 3
else
    echo "✗ gsec não encontrado"
fi

echo ""
echo "5. Verificando nbackup (physical backup):"
if command -v nbackup >/dev/null 2>&1; then
    echo "✓ nbackup encontrado em: $(which nbackup)"
    nbackup -? 2>&1 | head -n 3
else
    echo "✗ nbackup não encontrado"
fi

echo ""
echo "6. Verificando pacotes Firebird instalados:"
dpkg -l | grep -i firebird || echo "Nenhum pacote Firebird encontrado via dpkg"

echo ""
echo "7. Verificando AWS CLI:"
if command -v aws >/dev/null 2>&1; then
    echo "✓ AWS CLI encontrado: $(aws --version)"
else
    echo "✗ AWS CLI não encontrado"
fi

echo ""
echo "8. Verificando utilitários de compressão:"
if command -v gzip >/dev/null 2>&1; then
    echo "✓ gzip encontrado: $(gzip --version | head -n 1)"
else
    echo "✗ gzip não encontrado"
fi

echo ""
echo "==========================================="
echo "Verificação concluída!"
