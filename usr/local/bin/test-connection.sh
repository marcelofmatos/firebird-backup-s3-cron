#!/bin/bash

FB_HOST=${FB_HOST:-"localhost"}
FB_PORT=${FB_PORT:-"3050"}
FB_USER=${FB_USER:-"SYSDBA"}
FB_PASSWORD=${FB_PASSWORD:-"masterkey"}
FB_DATABASE_PATH=${FB_DATABASE_PATH:-"/data/DATABASE.FDB"}

echo "Testando conexão com Firebird..."
echo "Host: $FB_HOST"
echo "Port: $FB_PORT"
echo "Database: $FB_DATABASE_PATH"
echo "User: $FB_USER"
echo "---"

TEMP_QUERY_FILE="/tmp/test_query.sql"
TEMP_OUTPUT_FILE="/tmp/test_output.txt"

echo "SELECT COUNT(*) FROM RDB\$RELATIONS;" > "$TEMP_QUERY_FILE"

if isql -user "$FB_USER" -password "$FB_PASSWORD" -i "$TEMP_QUERY_FILE" -o "$TEMP_OUTPUT_FILE" "$FB_HOST/$FB_PORT:$FB_DATABASE_PATH" 2>/dev/null; then
    echo "✓ Conexão com Firebird estabelecida com sucesso!"
    echo "Tabelas encontradas no banco:"
    cat "$TEMP_OUTPUT_FILE" | tail -n +3
else
    echo "✗ Erro ao conectar com Firebird"
    echo "Verifique as configurações de conexão"
    exit 1
fi

rm -f "$TEMP_QUERY_FILE" "$TEMP_OUTPUT_FILE"

echo "---"
echo "Testando ferramenta gbak..."
if command -v gbak >/dev/null 2>&1; then
    echo "✓ gbak encontrado"
    gbak -? 2>&1 | head -n 3
else
    echo "✗ gbak não encontrado"
    exit 1
fi

echo "---"
echo "Testando AWS CLI..."
if command -v aws >/dev/null 2>&1; then
    echo "✓ AWS CLI encontrado"
    if aws s3 ls "s3://$S3_BUCKET_NAME/" --region "$S3_REGION" >/dev/null 2>&1; then
        echo "✓ Conexão com S3 estabelecida"
    else
        echo "✗ Erro ao acessar bucket S3: $S3_BUCKET_NAME"
        exit 1
    fi
else
    echo "✗ AWS CLI não encontrado"
    exit 1
fi

echo "---"
echo "✓ Todos os testes passaram! Sistema pronto para backup."
