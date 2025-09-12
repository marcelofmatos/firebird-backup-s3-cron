# Quick Start - Firebird Backup S3 Cron

## 🚀 Configuração Rápida

### 1. Configure as variáveis
```bash
cp .env.example .env
# Edite .env com suas configurações
```

### 2. Build e teste
```bash
chmod +x build.sh
./build.sh

# Teste as ferramentas
docker run --rm firebird-backup-s3-cron:latest /usr/local/bin/check-tools.sh
```

### 3. Teste conexão com seu banco
```bash
docker run --rm \
  -e FB_HOST=192.168.1.100 \
  -e FB_DATABASE_PATH=/data/DATABASE.FDB \
  -e FB_USER=SYSDBA \
  -e FB_PASSWORD=suasenha \
  firebird-backup-s3-cron:latest /usr/local/bin/test-connection.sh
```

### 4. Execute backup manual
```bash
docker run --rm \
  -e FB_HOST=192.168.1.100 \
  -e FB_DATABASE_PATH=/data/DATABASE.FDB \
  -e FB_USER=SYSDBA \
  -e FB_PASSWORD=suasenha \
  -e S3_BUCKET_NAME=seu-bucket-backups \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=... \
  firebird-backup-s3-cron:latest /usr/local/bin/backup.sh
```

### 5. Deploy com Docker Compose
```bash
docker-compose up -d
```

## 🔧 Comandos Úteis

### Logs do container
```bash
docker logs -f <container_id>
```

### Shell no container
```bash
docker exec -it <container_id> bash
```

### Listar backups no S3
```bash
docker exec <container_id> /usr/local/bin/list.sh
```

### Restaurar backup
```bash
docker exec <container_id> /usr/local/bin/restore.sh backup_20240101_120000.fbk.gz
```

## ⚡ Exemplo Comando gbak

O sistema usa internamente:
```bash
gbak -b -v -g -se 192.168.1.100:3050 /data/DATABASE.FDB /backup/backup.fbk -user SYSDBA -pass suasenha
```

## 📅 Agendamento Cron

Padrão: 22h todos os dias
```bash
0 22 * * *
```

Personalizar via `CRON_SCHEDULE`:
- `0 2 * * *` - 2h da madrugada
- `0 */6 * * *` - A cada 6 horas  
- `0 22 * * 0` - Domingos às 22h
