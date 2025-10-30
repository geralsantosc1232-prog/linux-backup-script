#!/bin/bash
# linux-backup-script - Backup cifrado a S3 con rotación
# Autor: Geraldine Santos

set -euo pipefail

# Cargar configuración
if [[ -f "config.env" ]]; then
    source config.env
else
    echo "Error: config.env no encontrado"
    exit 1
fi

# Validación
[[ -z "$SOURCE_DIR" || -z "$S3_BUCKET" ]] && { echo "Faltan variables en config.env"; exit 1; }

LOG_DIR="logs"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/backup_$DATE.log"
TEMP_DIR="/tmp/backup_$$"

mkdir -p "$LOG_DIR" "$TEMP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Iniciando backup de $SOURCE_DIR → $S3_BUCKET"

# Backup incremental
rsync -av --delete "$SOURCE_DIR/" "$TEMP_DIR/" >> "$LOG_FILE" 2>&1

# Comprimir y cifrar
tar -cz "$TEMP_DIR" | openssl enc -aes-256-cbc -salt -pass pass:"$BACKUP_PASS" -out "/tmp/backup_$DATE.tar.gz.enc"

# Subir a S3
aws s3 cp "/tmp/backup_$DATE.tar.gz.enc" "$S3_BUCKET" >> "$LOG_FILE" 2>&1

# Rotación: eliminar > 7 días
aws s3 ls "$S3_BUCKET" | grep "backup_.*.tar.gz.enc" | while read -r line; do
    file_date=$(echo "$line" | awk '{print $1}' | sed 's/-//g')
    file_name=$(echo "$line" | awk '{print $4}')
    if (( file_date < $(date -d '7 days ago' +%Y%m%d) )); then
        aws s3 rm "$S3_BUCKET$file_name" >> "$LOG_FILE" 2>&1
        log "Eliminado backup antiguo: $file_name"
    fi
done

# Limpieza
rm -rf "$TEMP_DIR" "/tmp/backup_$DATE.tar.gz.enc"

log "Backup completado con éxito"

# Notificación por email (opcional)
if [[ -n "${EMAIL_ALERT:-}" ]]; then
    echo "Backup completado: $DATE" | mail -s "Backup OK" "$EMAIL_ALERT"
fi
