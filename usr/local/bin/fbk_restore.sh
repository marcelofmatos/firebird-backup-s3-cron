#!/bin/bash

# Script para restaurar backup FBK no Firebird
# Deve ser executado dentro de /docker-entrypoint-initdb.d

set -e  # Parar execução em caso de erro

# Configurações padrão
FBK_FILE="${FBK_FILE:-/backup/database.fbk}"
DB_PATH="${FIREBIRD_DATABASE:-/var/lib/firebird/data/database.fdb}"
FB_USER="${FIREBIRD_USER:-SYSDBA}"
FB_PASSWORD="${FIREBIRD_PASSWORD:-masterkey}"
FB_HOST="${FB_HOST:-localhost}"
FB_PORT="${FB_PORT:-3050}"
PAGE_SIZE="${PAGE_SIZE:-8192}"
VERBOSE="${VERBOSE:-false}"

# Função para log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Função para log de erro
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Verificar se o arquivo FBK existe
if [ ! -f "$FBK_FILE" ]; then
    error "Arquivo FBK não encontrado: $FBK_FILE"
    exit 1
fi

# Verificar se o diretório de destino existe
DB_DIR=$(dirname "$DB_PATH")
if [ ! -d "$DB_DIR" ]; then
    log "Criando diretório: $DB_DIR"
    mkdir -p "$DB_DIR"
fi

# Verificar se o banco já existe
if [ -f "$DB_PATH" ]; then
    log "AVISO: Banco de dados já existe em $DB_PATH"
    if [ "$FORCE_RESTORE" != "true" ]; then
        log "Para forçar a restauração, defina FORCE_RESTORE=true"
        exit 0
    else
        log "FORCE_RESTORE=true, removendo banco existente..."
        rm -f "$DB_PATH"
    fi
fi

log "Iniciando restauração do backup..."
log "Arquivo FBK: $FBK_FILE"
log "Destino: $DB_PATH"
log "Usuário: $FB_USER"
log "Host: $FB_HOST:$FB_PORT"

# Construir comando gbak
GBAK_CMD="/opt/firebird/bin/gbak"
GBAK_ARGS="-c -user $FB_USER -password $FB_PASSWORD"

# Adicionar argumentos opcionais
if [ "$VERBOSE" = "true" ]; then
    GBAK_ARGS="$GBAK_ARGS -v"
fi

if [ -n "$PAGE_SIZE" ]; then
    GBAK_ARGS="$GBAK_ARGS -page_size $PAGE_SIZE"
fi

# Executar restauração
log "Executando: gbak $GBAK_ARGS \"$FBK_FILE\" \"$DB_PATH\""

if $GBAK_CMD $GBAK_ARGS "$FBK_FILE" "$DB_PATH"; then
    log "Restauração concluída com sucesso!"
    
    # Verificar se o arquivo foi criado
    if [ -f "$DB_PATH" ]; then
        DB_SIZE=$(du -h "$DB_PATH" | cut -f1)
        log "Banco criado: $DB_PATH (Tamanho: $DB_SIZE)"
        
        # Definir permissões corretas
        chown firebird:firebird "$DB_PATH" 2>/dev/null || true
        chmod 660 "$DB_PATH" 2>/dev/null || true
        
        log "Permissões ajustadas para o usuário firebird"
    else
        error "Arquivo de banco não foi criado: $DB_PATH"
        exit 1
    fi
    
    # Teste de conectividade (opcional)
    if [ "$TEST_CONNECTION" = "true" ]; then
        log "Testando conectividade..."
        if /usr/local/firebird/bin/isql -user "$FB_USER" -password "$FB_PASSWORD" "$DB_PATH" -q <<< "SELECT 1 FROM RDB\$DATABASE;"; then
            log "Teste de conectividade: OK"
        else
            error "Falha no teste de conectividade"
            exit 1
        fi
    fi
    
else
    error "Falha na restauração do backup"
    exit 1
fi

# Cleanup opcional
if [ "$REMOVE_FBK_AFTER_RESTORE" = "true" ]; then
    log "Removendo arquivo FBK após restauração..."
    rm -f "$FBK_FILE"
fi

log "Script fbk_restore.sh finalizado com sucesso!"
