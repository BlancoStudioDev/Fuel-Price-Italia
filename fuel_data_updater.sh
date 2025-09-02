#!/bin/bash

# Script per aggiornamento automatico dati carburanti
# Autore: Sistema automatico
# Data: $(date +%Y-%m-%d)

# Configurazione
DOWNLOAD_DIR="/tmp/fuel_data_$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="/var/www/blancostudio.dev/public_html/benzinai_italia"
LOG_FILE="/var/log/fuel_data_updater.log"
WEBSITE_URL="https://www.mimit.gov.it/it/open-data/elenco-dataset/carburanti-prezzi-praticati-e-anagrafica-degli-impianti"

# File da scaricare
ANAGRAFICA_FILE="anagrafica_impianti_attivi.csv"
PREZZO_FILE="prezzo_alle_8.csv"

# Funzione di logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Funzione per inviare notifica (opzionale)
send_notification() {
    local status="$1"
    local message="$2"
    
    # Esempio con mail (decommentare se hai configurato sendmail/postfix)
    # echo "Subject: Fuel Data Update - $status
    # 
    # $message
    # 
    # Time: $(date)
    # Server: $(hostname)" | sendmail admin@blancostudio.dev
    
    log "NOTIFICATION: $status - $message"
}

# Funzione per pulizia in caso di errore
cleanup() {
    if [ -d "$DOWNLOAD_DIR" ]; then
        rm -rf "$DOWNLOAD_DIR"
        log "Cleaned up temporary directory: $DOWNLOAD_DIR"
    fi
}

# Trap per pulizia automatica
trap cleanup EXIT

# Inizio script
log "=== INIZIO AGGIORNAMENTO DATI CARBURANTI ==="
log "Download directory: $DOWNLOAD_DIR"
log "Target directory: $TARGET_DIR"

# Verifica che curl sia disponibile
if ! command -v curl &> /dev/null; then
    log "ERRORE: curl non è installato"
    send_notification "ERROR" "curl non disponibile sul sistema"
    exit 1
fi

# Verifica che la directory target esista
if [ ! -d "$TARGET_DIR" ]; then
    log "ERRORE: Directory target non esiste: $TARGET_DIR"
    send_notification "ERROR" "Directory target non trovata: $TARGET_DIR"
    exit 1
fi

# Crea directory temporanea
mkdir -p "$DOWNLOAD_DIR"
if [ $? -ne 0 ]; then
    log "ERRORE: Impossibile creare directory temporanea"
    send_notification "ERROR" "Impossibile creare directory temporanea"
    exit 1
fi

log "Directory temporanea creata: $DOWNLOAD_DIR"

# Funzione per estrarre link di download dal sito
extract_download_links() {
    log "Analizzando la pagina web per trovare i link di download..."
    
    # Scarica la pagina HTML
    local html_content=$(curl -s -L "$WEBSITE_URL")
    if [ $? -ne 0 ]; then
        log "ERRORE: Impossibile scaricare la pagina web"
        return 1
    fi
    
    # Estrai i link dei file CSV
    # I link sono tipicamente in formato: href="path/to/file.csv"
    local anagrafica_link=$(echo "$html_content" | grep -o 'href="[^"]*anagrafica_impianti_attivi\.csv[^"]*"' | sed 's/href="//;s/"//' | head -1)
    local prezzo_link=$(echo "$html_content" | grep -o 'href="[^"]*prezzo_alle_8\.csv[^"]*"' | sed 's/href="//;s/"//' | head -1)
    
    # Se i link sono relativi, aggiunge il dominio
    if [[ "$anagrafica_link" == /* ]]; then
        anagrafica_link="https://www.mimit.gov.it$anagrafica_link"
    elif [[ "$anagrafica_link" != http* ]] && [ -n "$anagrafica_link" ]; then
        anagrafica_link="https://www.mimit.gov.it/it/open-data/elenco-dataset/$anagrafica_link"
    fi
    
    if [[ "$prezzo_link" == /* ]]; then
        prezzo_link="https://www.mimit.gov.it$prezzo_link"
    elif [[ "$prezzo_link" != http* ]] && [ -n "$prezzo_link" ]; then
        prezzo_link="https://www.mimit.gov.it/it/open-data/elenco-dataset/$prezzo_link"
    fi
    
    log "Link anagrafica trovato: $anagrafica_link"
    log "Link prezzi trovato: $prezzo_link"
    
    if [ -z "$anagrafica_link" ] || [ -z "$prezzo_link" ]; then
        log "ATTENZIONE: Alcuni link non sono stati trovati automaticamente"
        
        # Fallback: usa i link diretti più comuni (aggiorna questi URL se necessario)
        anagrafica_link="https://www.mimit.gov.it/images/exportCSV/anagrafica_impianti_attivi.csv"
        prezzo_link="https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv"
        log "Usando link fallback - Anagrafica: $anagrafica_link"
        log "Usando link fallback - Prezzi: $prezzo_link"
    fi
    
    export ANAGRAFICA_DOWNLOAD_URL="$anagrafica_link"
    export PREZZO_DOWNLOAD_URL="$prezzo_link"
}

# Funzione per scaricare un file
download_file() {
    local url="$1"
    local filename="$2"
    local filepath="$DOWNLOAD_DIR/$filename"
    
    log "Scaricando $filename da: $url"
    
    # Scarica il file con timeout e retry
    curl -L --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 10 \
         -o "$filepath" "$url"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -f "$filepath" ]; then
        local file_size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
        if [ "$file_size" -gt 1000 ]; then  # File deve essere > 1KB
            log "✓ $filename scaricato correttamente ($file_size bytes)"
            return 0
        else
            log "ERRORE: $filename scaricato ma sembra troppo piccolo ($file_size bytes)"
            return 1
        fi
    else
        log "ERRORE: Download fallito per $filename (exit code: $exit_code)"
        return 1
    fi
}

# Funzione per validare un file CSV
validate_csv() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    
    log "Validando $filename..."
    
    # Controlla se il file esiste
    if [ ! -f "$filepath" ]; then
        log "ERRORE: File non trovato: $filepath"
        return 1
    fi
    
    # Controlla le prime righe per assicurarsi che sia un CSV valido
    local first_line=$(head -n 1 "$filepath")
    local line_count=$(wc -l < "$filepath")
    
    # Deve avere almeno 2 righe (header + dati)
    if [ "$line_count" -lt 2 ]; then
        log "ERRORE: $filename ha solo $line_count righe, sembra non valido"
        return 1
    fi
    
    # Controlla se contiene punto e virgola (separatore CSV italiano)
    if [[ "$first_line" == *";"* ]]; then
        log "✓ $filename sembra un CSV valido ($line_count righe)"
        return 0
    else
        log "ATTENZIONE: $filename potrebbe non essere un CSV con separatore ;"
        log "Prima riga: $first_line"
        # Continua comunque, potrebbe essere valido
        return 0
    fi
}

# Funzione per creare backup
create_backup() {
    local target_file="$TARGET_DIR/$1"
    local backup_file="$TARGET_DIR/backup_$(date +%Y%m%d)_$1"
    
    if [ -f "$target_file" ]; then
        cp "$target_file" "$backup_file"
        if [ $? -eq 0 ]; then
            log "✓ Backup creato: $backup_file"
        else
            log "ATTENZIONE: Impossibile creare backup di $1"
        fi
    fi
}

# Funzione per installare il nuovo file
install_file() {
    local source_file="$DOWNLOAD_DIR/$1"
    local target_file="$TARGET_DIR/$1"
    
    if [ -f "$source_file" ]; then
        # Crea backup del file esistente
        create_backup "$1"
        
        # Copia il nuovo file
        cp "$source_file" "$target_file"
        if [ $? -eq 0 ]; then
            # Imposta permessi corretti
            chmod 644 "$target_file"
            chown www-data:www-data "$target_file" 2>/dev/null || true
            log "✓ $1 installato correttamente"
            return 0
        else
            log "ERRORE: Impossibile installare $1"
            return 1
        fi
    else
        log "ERRORE: File sorgente non trovato: $source_file"
        return 1
    fi
}

# ESECUZIONE PRINCIPALE

# Estrai i link di download
extract_download_links

# Scarica i file
log "--- FASE DOWNLOAD ---"
download_success=true

if ! download_file "$ANAGRAFICA_DOWNLOAD_URL" "$ANAGRAFICA_FILE"; then
    download_success=false
fi

if ! download_file "$PREZZO_DOWNLOAD_URL" "$PREZZO_FILE"; then
    download_success=false
fi

if [ "$download_success" = false ]; then
    log "ERRORE: Uno o più download sono falliti"
    send_notification "ERROR" "Fallimento durante il download dei file"
    exit 1
fi

# Valida i file scaricati
log "--- FASE VALIDAZIONE ---"
validation_success=true

if ! validate_csv "$DOWNLOAD_DIR/$ANAGRAFICA_FILE"; then
    validation_success=false
fi

if ! validate_csv "$DOWNLOAD_DIR/$PREZZO_FILE"; then
    validation_success=false
fi

if [ "$validation_success" = false ]; then
    log "ERRORE: Uno o più file non hanno superato la validazione"
    send_notification "ERROR" "File scaricati non validi"
    exit 1
fi

# Installa i nuovi file
log "--- FASE INSTALLAZIONE ---"
install_success=true

if ! install_file "$ANAGRAFICA_FILE"; then
    install_success=false
fi

if ! install_file "$PREZZO_FILE"; then
    install_success=false
fi

if [ "$install_success" = false ]; then
    log "ERRORE: Uno o più file non sono stati installati correttamente"
    send_notification "ERROR" "Fallimento durante l'installazione dei file"
    exit 1
fi

# Pulizia vecchi backup (mantieni solo gli ultimi 7 giorni)
log "--- PULIZIA BACKUP ---"
find "$TARGET_DIR" -name "backup_*" -type f -mtime +7 -delete 2>/dev/null || true
log "✓ Pulizia backup completata"

# Aggiorna timestamp ultimo aggiornamento
echo "Ultimo aggiornamento: $(date)" > "$TARGET_DIR/last_update.txt"

# Successo!
log "=== AGGIORNAMENTO COMPLETATO CON SUCCESSO ==="
log "Files aggiornati:"
log "  - $TARGET_DIR/$ANAGRAFICA_FILE"
log "  - $TARGET_DIR/$PREZZO_FILE"

send_notification "SUCCESS" "Aggiornamento dati carburanti completato con successo"

# Statistiche finali
anagrafica_size=$(stat -f%z "$TARGET_DIR/$ANAGRAFICA_FILE" 2>/dev/null || stat -c%s "$TARGET_DIR/$ANAGRAFICA_FILE" 2>/dev/null)
prezzo_size=$(stat -f%z "$TARGET_DIR/$PREZZO_FILE" 2>/dev/null || stat -c%s "$TARGET_DIR/$PREZZO_FILE" 2>/dev/null)

log "Statistiche:"
log "  - Anagrafica: $anagrafica_size bytes"
log "  - Prezzi: $prezzo_size bytes"
log "  - Directory target: $TARGET_DIR"

exit 0