FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    firebird3.0-utils \
    firebird3.0-common \
    curl \
    ca-certificates \
    python3-pip \
    gzip \
    cron \
    && pip3 install awscli \
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
ENV CRON_SCHEDULE="0 22 * * *"
ENV CRON_BACKUP_COMMAND="/usr/local/bin/backup.sh > /proc/1/fd/1 2>&1"

RUN mkdir -p /backup

COPY etc /etc
COPY usr /usr
RUN chmod +x /usr/local/bin/*.sh

CMD ["/usr/local/bin/start-cron.sh"]
