# Changelog - Migração PostgreSQL → Firebird

## Principais Alterações

### Dockerfile
- **Base alterada**: Alpine Linux → Ubuntu 22.04
- **Pacotes**: Removido PostgreSQL, adicionado `firebird3.0-utils` e `firebird3.0-common`
- **AWS CLI**: Migrado para instalação via pip3
- **Cron**: Usa daemon `cron` padrão do Ubuntu

### Scripts de Backup
- **backup.sh**: Reescrito completamente para usar `gbak`
  - Comando: `gbak -b -v -g -se HOST:PORT DATABASE_PATH BACKUP_FILE -user USER -pass PASSWORD`
  - Compressão com gzip após backup
  - Suporte a banco único (padrão Firebird)
- **restore.sh**: Novo script para download e preparação de backups .fbk
- **test-connection.sh**: Teste de conectividade com `isql-fb`
- **check-tools.sh**: Verificação completa dos utilitários Firebird

### Variáveis de Ambiente
| PostgreSQL | Firebird | Descrição |
|------------|----------|-----------|
| `PGHOST` | `FB_HOST` | Servidor de banco |
| `PGPORT` | `FB_PORT` | Porta (3050 padrão) |
| `PGUSER` | `FB_USER` | Usuário (SYSDBA padrão) |
| `PGPASSWORD` | `FB_PASSWORD` | Senha |
| `PGDATABASE` | `FB_DATABASE_PATH` | Caminho .FDB completo |

### Docker Compose
- **Serviço**: `pg-backup-s3` → `fb-backup-s3`
- **Host**: `database` → `firebird-server`
- **Extensões**: `.sql.gz` → `.fbk.gz`

### Utilitários Disponíveis
- `gbak`: Backup/restore principal
- `isql-fb`: Console SQL interativo
- `gstat`: Estatísticas do banco
- `gsec`: Gerenciamento de usuários
- `nbackup`: Backup físico incremental

## Teste de Build

```bash
# Construir imagem
chmod +x build.sh
./build.sh

# Testar ferramentas
docker run --rm firebird-backup-s3-cron:latest /usr/local/bin/check-tools.sh

# Testar backup (requer configurações S3 e Firebird)
docker run --rm -e FB_HOST=... -e FB_DATABASE_PATH=... firebird-backup-s3-cron:latest /usr/local/bin/backup.sh
```

## Compatibilidade

- **Firebird 3.0+**: Versão LTS estável
- **Ubuntu 22.04**: Base confiável com pacotes oficiais
- **AWS S3**: Compatibilidade mantida
- **Cron**: Sintaxe padrão Unix
