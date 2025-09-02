#!/bin/bash

# Script di installazione per l'aggiornatore automatico dati carburanti
# Questo script configura tutto il necessario per l'esecuzione automatica

SCRIPT_NAME="fuel_data_updater.sh"
INSTALL_DIR="/usr/local/bin"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
CRON_TIME="0 9 * * *"  # Ogni giorno alle 9:00

echo "=== INSTALLAZIONE AGGIORNATORE DATI CARBURANTI ==="
echo

# Verifica privilegi root
if [ "$EUID" -ne 0 ]; then
    echo "ERRORE: Questo script deve essere eseguito come root"
    echo "Usa: sudo $0"
    exit 1
fi

# Verifica dipendenze
echo "Verificando dipendenze..."
missing_deps=()

if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
fi

if ! command -v cron &> /dev/null && ! command -v crond &> /dev/null; then
    missing_deps+=("cron")
fi

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "ERRORE: Dipendenze mancanti: ${missing_deps[*]}"
    echo
    echo "Su Ubuntu/Debian installa con:"
    echo "  apt update && apt install ${missing_deps[*]}"
    echo
    echo "Su CentOS/RHEL installa con:"
    echo "  yum install ${missing_deps[*]}"
    exit 1
fi

echo "✓ Tutte le dipendenze sono soddisfatte"

# Verifica directory target
TARGET_DIR="/var/www/blancostudio.dev/public_html/benzinai_italia"
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creando directory target: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    chown www-data:www-data "$TARGET_DIR" 2>/dev/null || chown apache:apache "$TARGET_DIR" 2>/dev/null || true
    chmod 755 "$TARGET_DIR"
fi

echo "✓ Directory target verificata: $TARGET_DIR"

# Copia lo script principale
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "ERRORE: File $SCRIPT_NAME non trovato nella directory corrente"
    echo "Assicurati di avere il file fuel_data_updater.sh nella stessa directory"
    exit 1
fi

echo "Installando script in $SCRIPT_PATH..."
cp "$SCRIPT_NAME" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
chown root:root "$SCRIPT_PATH"

echo "✓ Script installato"

# Crea directory log
LOG_DIR="/var/log"
touch "$LOG_DIR/fuel_data_updater.log"
chmod 644 "$LOG_DIR/fuel_data_updater.log"

echo "✓ File log configurato: $LOG_DIR/fuel_data_updater.log"

# Configura cron job
echo "Configurando cron job..."

# Rimuovi eventuali cron job esistenti per questo script
crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -

# Aggiungi nuovo cron job
(crontab -l 2>/dev/null; echo "$CRON_TIME $SCRIPT_PATH") | crontab -

if [ $? -eq 0 ]; then
    echo "✓ Cron job configurato: ogni giorno alle 9:00"
else
    echo "ERRORE: Impossibile configurare il cron job"
    exit 1
fi

# Test dello script
echo
echo "Testando lo script (esecuzione di prova)..."
echo "Questo potrebbe richiedere alcuni minuti..."

# Esegui test in background e mostra progresso
$SCRIPT_PATH &
TEST_PID=$!

# Mostra spinner durante il test
spinner=('|' '/' '-' '\')
i=0
while kill -0 $TEST_PID 2>/dev/null; do
    printf "\r[${spinner[$i]}] Test in corso..."
    i=$(( (i+1) % 4 ))
    sleep 1
done

wait $TEST_PID
TEST_RESULT=$?

printf "\r                    \r"

if [ $TEST_RESULT -eq 0 ]; then
    echo "✓ Test completato con successo!"
else
    echo "⚠ Test completato con avvertimenti (codice: $TEST_RESULT)"
    echo "Controlla il log per dettagli: tail -f /var/log/fuel_data_updater.log"
fi

# Mostra stato dei file
echo
echo "=== STATO INSTALLAZIONE ==="
echo "Script installato: $SCRIPT_PATH"
echo "Directory dati: $TARGET_DIR"
echo "Log file: $LOG_DIR/fuel_data_updater.log"
echo
echo "File attualmente presenti in $TARGET_DIR:"
ls -la "$TARGET_DIR" 2>/dev/null || echo "  (directory vuota o non accessibile)"

echo
echo "Cron job configurato:"
crontab -l | grep "$SCRIPT_PATH"

echo
echo "=== COMANDI UTILI ==="
echo
echo "Visualizzare log in tempo reale:"
echo "  tail -f /var/log/fuel_data_updater.log"
echo
echo "Eseguire manualmente l'aggiornamento:"
echo "  $SCRIPT_PATH"
echo
echo "Verificare cron job:"
echo "  crontab -l"
echo
echo "Rimuovere cron job:"
echo "  crontab -l | grep -v '$SCRIPT_PATH' | crontab -"
echo
echo "Verificare stato servizio cron:"
echo "  systemctl status cron   # Ubuntu/Debian"
echo "  systemctl status crond  # CentOS/RHEL"

echo
echo "=== INSTALLAZIONE COMPLETATA ==="
echo "L'aggiornamento automatico è ora configurato per eseguirsi ogni giorno alle 9:00"

# Crea script di controllo
CONTROL_SCRIPT="/usr/local/bin/fuel_updater_control.sh"
cat > "$CONTROL_SCRIPT" << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "=== STATO AGGIORNATORE CARBURANTI ==="
        echo
        echo "Cron job:"
        crontab -l | grep fuel_data_updater || echo "  Nessun cron job trovato"
        echo
        echo "Ultimo aggiornamento:"
        if [ -f "/var/www/blancostudio.dev/public_html/benzinai_italia/last_update.txt" ]; then
            cat "/var/www/blancostudio.dev/public_html/benzinai_italia/last_update.txt"
        else
            echo "  Nessun aggiornamento registrato"
        fi
        echo
        echo "File presenti:"
        ls -la /var/www/blancostudio.dev/public_html/benzinai_italia/ 2>/dev/null || echo "  Directory non trovata"
        ;;
    run)
        echo "Eseguendo aggiornamento manuale..."
        /usr/local/bin/fuel_data_updater.sh
        ;;
    log)
        tail -f /var/log/fuel_data_updater.log
        ;;
    enable)
        (crontab -l 2>/dev/null; echo "0 9 * * * /usr/local/bin/fuel_data_updater.sh") | crontab -
        echo "Cron job abilitato"
        ;;
    disable)
        crontab -l 2>/dev/null | grep -v fuel_data_updater | crontab -
        echo "Cron job disabilitato"
        ;;
    *)
        echo "Uso: $0 {status|run|log|enable|disable}"
        echo
        echo "  status  - Mostra stato del sistema"
        echo "  run     - Esegue aggiornamento manualmente"
        echo "  log     - Mostra log in tempo reale"
        echo "  enable  - Abilita cron job"
        echo "  disable - Disabilita cron job"
        exit 1
        ;;
esac
EOF

chmod +x "$CONTROL_SCRIPT"
echo
echo "Script di controllo creato: $CONTROL_SCRIPT"
echo "Uso: fuel_updater_control.sh {status|run|log|enable|disable}"

exit 0