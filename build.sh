#!/bin/bash

echo "🔥 Firebird Backup S3 Cron - Build e Deploy"
echo "============================================="

# Build da imagem
echo "📦 Construindo imagem Docker..."
docker build -t firebird-backup-s3-cron:latest .

if [ $? -eq 0 ]; then
    echo "✅ Imagem construída com sucesso!"
else
    echo "❌ Erro ao construir imagem"
    exit 1
fi

echo ""
echo "🏷️  Para tagear a imagem para o registry:"
echo "docker tag firebird-backup-s3-cron:latest dockerhub.com.br/project/firebird-backup-s3-cron:main"

echo ""
echo "🚀 Para fazer push da imagem:"
echo "docker push dockerhub.com.br/project/firebird-backup-s3-cron:main"

echo ""
echo "🧪 Para testar localmente:"
echo "docker run --rm -it \\\\"
echo "  -e FB_HOST=192.168.1.100 \\\\"
echo "  -e FB_DATABASE_PATH=/data/DATABASE.FDB \\\\"
echo "  -e FB_USER=SYSDBA \\\\"
echo "  -e FB_PASSWORD=suasenha \\\\"
echo "  -e S3_BUCKET_NAME=seu-bucket-backups \\\\"
echo "  -e AWS_ACCESS_KEY_ID=AKIA... \\\\"
echo "  -e AWS_SECRET_ACCESS_KEY=... \\\\"
echo "  -e COMPRESSION_TYPE=7zip \\\\"
echo "  firebird-backup-s3-cron:latest /usr/local/bin/check-tools.sh"

echo ""
echo "🔍 Para executar teste de conexão:"
echo "docker run --rm -it \\\\"
echo "  -e FB_HOST=192.168.1.100 \\\\"
echo "  -e FB_DATABASE_PATH=/data/DATABASE.FDB \\\\"
echo "  -e FB_USER=SYSDBA \\\\"
echo "  -e FB_PASSWORD=suasenha \\\\"
echo "  -e S3_BUCKET_NAME=seu-bucket-backups \\\\"
echo "  -e AWS_ACCESS_KEY_ID=AKIA... \\\\"
echo "  -e AWS_SECRET_ACCESS_KEY=... \\\\"
echo "  -e COMPRESSION_TYPE=zip \\\\"
echo "  firebird-backup-s3-cron:latest /usr/local/bin/test-connection.sh"

echo ""
echo "⚙️  Para executar com Docker Compose:"
echo "docker-compose up -d"

echo ""
echo "✨ Build concluído!"
