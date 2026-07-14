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
- `DELETE_LOCAL_AFTER_UPLOAD`: Remove o arquivo local após o envio (padrão: true). O arquivo só
  é removido depois de um upload confirmado — sem `S3_BUCKET_NAME`, ou se o envio falhar, o
  backup é mantido localmente.

### Compressão
- `COMPRESSION_TYPE`: Tipo de compressão aplicada ao backup (padrão: gzip)
  - `gzip` ou `tgz`: Compressão gzip (padrão, compatibilidade retroativa)
  - `7zip` ou `7z`: Compressão 7-Zip (requer p7zip-full)
  - `zip`: Compressão ZIP (requer zip)
  - `none`: Sem compressão (arquivo .fbk original)

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
  -e COMPRESSION_TYPE=7zip \
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
      COMPRESSION_TYPE: "zip"
```

## Scripts Disponíveis

- `/usr/local/bin/backup.sh`: Executa backup do Firebird
- `/usr/local/bin/restore.sh`: Baixa e prepara backup para restauração
- `/usr/local/bin/restore2entrypoint.sh`: Prepara um backup para ser restaurado pelo entrypoint do servidor Firebird
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

Como o backup usa `-se` (Services Manager), o `.fbk` é gravado **pelo servidor Firebird**, no
caminho `BACKUP_DIR` (padrão `/data/backups`). Esse diretório precisa ser o mesmo volume, no
mesmo caminho, nos dois containers — senão a etapa de compressão não encontra o arquivo.

## Restauração

Os backups são nomeados como `<FB_HOST>_<DB>_<AAAAMMDD_HHMMSS>.<ext>`, onde a extensão
depende do `COMPRESSION_TYPE` (`.fbk.gz`, `.fbk.7z`, `.fbk.zip` ou `.fbk`). Use o `list.sh`
para obter o nome exato.

### Restauração manual (restore.sh)

```bash
docker exec <container_id> /usr/local/bin/list.sh
docker exec <container_id> /usr/local/bin/restore.sh firebird-server_DATABASE_20240101_120000.fbk.gz
```

O script baixa do S3, descompacta (qualquer um dos quatro formatos) em `RESTORE_DIR`
(padrão `/restore`) e **imprime** o comando `gbak` de restauração — nada é sobrescrito
automaticamente. O comando impresso não usa `-se`: o `gbak` lê o `.fbk` dentro do container
de backup e o envia ao servidor pela rede (porta 3050), então o arquivo não precisa estar
visível para o servidor:

```bash
gbak -c -v "/restore/<arquivo>.fbk" "$FB_HOST/$FB_PORT:$FB_DATABASE_PATH" -user "$FB_USER" -pass "$FB_PASSWORD"
```

Se o banco de destino já existir, troque `-c` (create) por `-rep` (replace) — `-c` falha
propositalmente para não destruir um banco existente por engano.

### Restauração automática no start do Firebird (RESTORE_BACKUP_FILE)

Definindo `RESTORE_BACKUP_FILE`, o container baixa o backup no start e prepara o volume
`/docker-entrypoint-initdb.d`, que precisa ser compartilhado com o container do servidor Firebird:

```
/docker-entrypoint-initdb.d/
├── 10-restore.sh          # wrapper executado pelo entrypoint do Firebird
└── restore/
    ├── <backup>.fbk       # backup já descompactado
    └── fbk_restore.sh     # faz o gbak -c, ajusta owner/permissões do .fdb
```

O wrapper apenas aponta `FBK_FILE` e `DB_PATH` (= `FB_DATABASE_PATH`) e delega ao
`fbk_restore.sh`. O `.fbk` e o `fbk_restore.sh` ficam no subdiretório `restore/` de propósito:
o entrypoint do Firebird executa apenas os `*.sh` do primeiro nível, então quem dispara o
restore é o wrapper, uma única vez.

As credenciais **não** são gravadas no volume: o `fbk_restore.sh` roda dentro do container do
Firebird e usa o ambiente dele (`FIREBIRD_USER` / `FIREBIRD_PASSWORD`, com fallback para
`FIREBIRD_ROOT_PASSWORD`). Se o banco já existir em `FB_DATABASE_PATH`, o restore é ignorado —
para sobrescrever, defina `FORCE_RESTORE=true` no container do Firebird.

## Testes Automatizados

```bash
./tests/run.sh
```

Constrói a imagem e roda as suítes dentro dela, com stubs de `gbak` e `aws` — não é necessário
nenhum servidor Firebird nem bucket S3 real. Cobrem:

- `tests/backup_test.sh`: os quatro `COMPRESSION_TYPE`, e a remoção do arquivo local apenas
  após um upload confirmado (sem bucket, ou com falha no envio, o backup é preservado).
- `tests/restore_test.sh`: `restore.sh` e `restore2entrypoint.sh` sobre os quatro formatos
  gerados pelo `backup.sh`, incluindo o comando `gbak` impresso e o init script gerado.

Rodam também no CI, a cada pull request.

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
