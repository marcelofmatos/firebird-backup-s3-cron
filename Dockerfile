# Imagem oficial do Firebird: traz gbak/isql/gfix na versão do servidor.
# O gbak precisa ser >= ao do servidor — um gbak 3.0 não lê um backup gerado por um
# servidor 5.0 ("Expected backup version 1..10. Found 11"). A base é jammy (Ubuntu 22.04).
FROM firebirdsql/firebird:5.0.4-jammy

ENV DEBIAN_FRONTEND=noninteractive

# /usr/local/bin antes de /opt/firebird/bin: os scripts do projeto têm precedência
ENV PATH=/usr/local/sbin:/usr/local/bin:/opt/firebird/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    python3-pip \
    gzip \
    zip \
    unzip \
    p7zip-full \
    cron \
    tzdata \
    && pip3 install awscli \
    && ln -s /opt/firebird/bin/isql /usr/local/bin/isql-fb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV FB_HOST=localhost
ENV FB_PORT=3050
ENV FB_USER=SYSDBA
ENV FB_PASSWORD=masterkey
ENV FB_DATABASE_PATH=/data/DATABASE.FDB
ENV S3_BUCKET_NAME=your_s3_bucket_name
ENV S3_REGION=sa-east-1
ENV AWS_ACCESS_KEY_ID=your_access_key_id
ENV AWS_SECRET_ACCESS_KEY=your_secret_access_key
ENV S3_DIRECTORY_NAME=default-directory
ENV COMPRESSION_TYPE=gzip
ENV CRON_SCHEDULE="0 22 * * *"
ENV CRON_BACKUP_COMMAND="/usr/local/bin/backup.sh > /proc/1/fd/1 2>&1"

COPY etc /etc
COPY usr /usr
RUN chmod +x /usr/local/bin/*.sh

# Neutraliza o entrypoint da imagem base, que sobe o servidor Firebird:
# aqui o container roda o cron de backup, não serve banco.
ENTRYPOINT []
CMD ["/usr/local/bin/start-cron.sh"]
