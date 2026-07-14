# Funções compartilhadas por restore.sh e restore2entrypoint.sh.
# Mensagens vão para stderr; o stdout carrega apenas o caminho do .fbk resultante.

# fb_download_backup <arquivo> <diretorio_destino>
fb_download_backup() {
    local filename=$1
    local dest_dir=$2

    mkdir -p "$dest_dir" || return 1

    echo "Baixando backup do S3..." >&2
    if ! aws s3 cp "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$filename" "$dest_dir/$filename" --region "$S3_REGION" >&2; then
        echo "Erro ao baixar backup do S3" >&2
        return 1
    fi
    echo "Backup baixado: $dest_dir/$filename" >&2
}

# fb_extract_backup <caminho_do_arquivo>
# Descompacta conforme a extensão gerada pelo backup.sh (.fbk.gz, .fbk.7z, .fbk.zip, .fbk)
# e imprime no stdout o caminho do .fbk pronto para o gbak.
fb_extract_backup() {
    local archive=$1
    local dir fbk
    dir=$(dirname "$archive")

    case "$archive" in
        *.gz)
            echo "Descompactando (gzip)..." >&2
            gunzip -f "$archive" >&2 || return 1
            fbk="${archive%.gz}"
            ;;
        *.7z)
            echo "Descompactando (7z)..." >&2
            7z e -y -o"$dir" "$archive" >&2 || return 1
            rm -f "$archive"
            fbk="${archive%.7z}"
            ;;
        *.zip)
            echo "Descompactando (zip)..." >&2
            unzip -o -j "$archive" -d "$dir" >&2 || return 1
            rm -f "$archive"
            fbk="${archive%.zip}"
            ;;
        *)
            fbk="$archive"
            ;;
    esac

    if [ ! -f "$fbk" ]; then
        echo "Erro: arquivo .fbk não encontrado após a descompactação: $fbk" >&2
        return 1
    fi

    echo "$fbk"
}
