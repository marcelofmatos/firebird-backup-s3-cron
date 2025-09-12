# Firebird Backup S3 Cron

Sistema automatizado de backup para bancos de dados Firebird com envio para Amazon S3.

Baseado em Ubuntu 22.04 com ferramentas oficiais do Firebird.

## Funcionamento

O sistema realiza backup usando `gbak` (Firebird backup utility), compacta o arquivo resultante e envia para um bucket S3 configurado. O processo é executado via cron job conforme agendamento definido.

## Variáveis de Ambiente

### Firebird
- `FB_HOST`: Servidor Firebird (padrão: localhost)
- `FB_PORT`: Porta do servidor (padrão: 3050)
- `FB_USER`: Usuário do banco (padrão: SYSDBA)
- `FB_PASSWORD`: Senha do usuário (padrão: masterkey)
- `FB_DATABASE_PATH`: Caminho completo do arquivo .FDB (padrão: /data/DATABASE.FDB)

### AWS S3
- `S3_BUCKET_NAME`: Nome do bucket S3
- `S3_REGION`: Região do bucket (padrão: sa-east-1)
- `AWS_ACCESS_KEY_ID`: Chave de acesso AWS
- `AWS_SECRET_ACCESS_KEY`: Chave secreta AWS
- `S3_DIRECTORY_NAME`: Diretório no bucket (padrão: firebird-backups)

### Agendamento
- `CRON_SCHEDULE`: Agendamento cron (padrão: "0 22 * * *" - 22h diariamente)
- `CRON_BACKUP_COMMAND`: Comando executado (padrão: backup.sh com logs)

## Uso com Docker

```bash
docker run -d \
  -e FB_HOST=192.168.1.100 \
  -e FB_PORT=3050 \
  -e FB_DATABASE_PATH=/data/DATABASE.FDB \
  -e FB_USER=SYSDBA \
  -e FB_PASSWORD=suasenha \
  -e S3_BUCKET_NAME=seu-bucket-backups \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=... \
  -e CRON_SCHEDULE="0 2 * * *" \
  ghcr.io/marcelofmatos/firebird-backup-s3-cron:latest
```

## Uso com Docker Compose

```yaml
version: '3.8'
services:
  fb-backup-s3:
    image: ghcr.io/marcelofmatos/firebird-backup-s3-cron:latest
    environment:
      FB_HOST: "firebird-server"
      FB_PORT: 3050
      FB_DATABASE_PATH: "/data/DATABASE.FDB"
      FB_USER: "SYSDBA"
      FB_PASSWORD: "masterkey"
      S3_BUCKET_NAME: "backup-bucket"
      AWS_ACCESS_KEY_ID: "AKIA..."
      AWS_SECRET_ACCESS_KEY: "..."
```

## Scripts Disponíveis

- `/usr/local/bin/backup.sh`: Executa backup do Firebird
- `/usr/local/bin/restore.sh`: Baixa e prepara backup para restauração
- `/usr/local/bin/test-connection.sh`: Testa conectividade com Firebird e S3
- `/usr/local/bin/check-tools.sh`: Verifica instalação dos utilitários Firebird
- `/usr/local/bin/list.sh`: Lista backups no S3
- `/usr/local/bin/s3_bucket_list.sh`: Lista conteúdo do bucket S3

## Comando gbak Utilizado

```bash
gbak -b -v -g -se HOST:PORT DATABASE_PATH BACKUP_FILE -user USER -pass PASSWORD
```

Parâmetros:
- `-b`: Backup mode
- `-v`: Verbose output
- `-g`: Garbage collection durante backup
- `-se`: Especifica servidor e porta

## Testando o Sistema

Verifique a instalação dos utilitários:

```bash
docker exec -it <container_id> /usr/local/bin/check-tools.sh
```

Antes de ativar o backup automático, teste a conectividade:

```bash
docker exec -it <container_id> /usr/local/bin/test-connection.sh
```

Para executar backup manual:

```bash
docker exec -it <container_id> /usr/local/bin/backup.sh
```

## Build da Imagem

Para construir a imagem localmente:

```bash
chmod +x build.sh
./build.sh
```

Ou manualmente:

```bash
docker build -t firebird-backup-s3-cron:latest .
```
