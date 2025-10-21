#!/usr/bin/env bash

CRON_SCHEDULE=${CRON_SCHEDULE:-"0 0 * * *"}
CRON_BACKUP_COMMAND=${CRON_BACKUP_COMMAND:-"/usr/local/bin/backup.sh > /proc/1/fd/1 2>&1"}

# Verificação das Variáveis de Ambiente
if [[ ! -z "${RESTORE_BACKUP_FILE}" ]]; then
  echo "Arquivo de backup será copiado para o entrypoint (RESTORE_BACKUP_FILE=${RESTORE_BACKUP_FILE})"
  restore2entrypoint.sh "${RESTORE_BACKUP_FILE}" 
  echo "Arquivo copiado."
fi

if [[ -z "${CRON_SCHEDULE}" ]]; then
  echo "A variável CRON_SCHEDULE não está definida. Cron job não será configurado."
  exit 0
fi

if [[ -z "${CRON_BACKUP_COMMAND}" ]]; then
  echo "A variável CRON_BACKUP_COMMAND não está definida. Cron job não será configurado."
  exit 0
fi

echo "Variáveis CRON_SCHEDULE e CRON_BACKUP_COMMAND detectadas. Iniciando configuração do cron."

# Verificação do Script de Backup
BACKUP_SCRIPT=$(echo "${CRON_BACKUP_COMMAND}" | awk '{print $1}')

if [[ ! -x "${BACKUP_SCRIPT}" ]]; then
  echo "Erro: O script de backup '${BACKUP_SCRIPT}' não existe ou não tem permissões de execução."
  exit 1
fi

# Configuração do Cron
CRON_ENTRY="${CRON_SCHEDULE} ${CRON_BACKUP_COMMAND}"

if crontab -l >/dev/null 2>&1; then
  echo "Adicionando nova entrada ao cron existente."
  crontab -l > /tmp/current_cron
  echo "${CRON_ENTRY}" >> /tmp/current_cron
  crontab /tmp/current_cron
  rm /tmp/current_cron
else
  echo "Criando nova crontab com a entrada fornecida."
  echo "${CRON_ENTRY}" | crontab -
fi

echo "Exportando variáveis de ambiente para o cron"
env > /etc/environment

echo "Cron job configurado com sucesso:"
crontab -l

echo ""
echo "Cron iniciado"

# Início do Serviço Cron
if command -v cron >/dev/null 2>&1; then
  echo "Iniciando cron..."
  exec cron -f
else
  echo "Erro: Daemon cron não encontrado. Instale o cron."
  exit 1
fi
