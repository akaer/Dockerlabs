#!/usr/bin/env bash

# Check for required commands
for cmd in unix2dos inotifywait docker vde_switch; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed!"
        exit 1
    fi
done

INCLUDEFILE="$(dirname "$0")/env.demo"
readonly INCLUDEFILE

if [[ -f "$INCLUDEFILE" ]]; then
    # shellcheck source=./env.demo
    source "$INCLUDEFILE"
fi

helper/create_certificates.sh "$DOMAIN_NAME_1" "dc1"
helper/create_certificates.sh "$DOMAIN_NAME_2" "dc2"
helper/create_certificates.sh "$DOMAIN_NAME_3" "dc3"

sudo vde_switch -d -s /tmp/vde_switch.sock -t vde_tap0 -M /tmp/vde_mgmt.sock

cp -f "$INCLUDEFILE" scripts/env.ps1

# Convert docker compose env file to a sourceable file by PowerShell
sed -i -e "/=/ s|^|\$|g" \
       -e "/=/ s|=|=\'|g" \
       -e "/=/ s|$|'|g" \
       -e "/:/ s|:|-|g" \
       scripts/env.ps1
unix2dos -m scripts/env.ps1

docker compose --env-file "$INCLUDEFILE" up -d

# Start of silly Microsoft Windows workaround to reboot any of our VMs to stablelize the network configuration
mapfile -t computernames < <(grep '_COMPUTERNAME=' "$INCLUDEFILE" | cut -d'=' -f2)

WATCH_DIR="$(pwd)/shared/state"

if [[ ! -d "$WATCH_DIR" ]]; then
    sudo mkdir -p "$WATCH_DIR"
fi

declare -A rebooted

for name in "${computernames[@]}"; do
    rebooted[$name]=0
done

echo "[+] Monitoring $WATCH_DIR for reboot triggers..."
echo "[+] Watching for: ${computernames[*]}"
echo "[+] Total containers to reboot: ${#computernames[@]}"

rebooted_count=0

inotifywait -m -e create,moved_to "$WATCH_DIR" --format '%f' | while read -r filename; do
    for name in "${computernames[@]}"; do
        if [[ "$filename" == "${name}_reboot.txt" ]]; then
            echo "[+] $(date): Detected $filename - triggering restart for container: $name"

            docker restart "$name"

            echo "[+] $(date): Container $name restarted"

            # Only count first reboot for exit condition
            if [[ ${rebooted[$name]} -eq 0 ]]; then
                rebooted[$name]=1
                ((rebooted_count++))
                echo "[+] Progress: $rebooted_count/${#computernames[@]} containers rebooted"
            else
                echo "[+] Note: $name was rebooted again (not counted towards completion)"
            fi

            # Check if all containers have been rebooted at least once
            if [[ $rebooted_count -eq ${#computernames[@]} ]]; then
                echo "[+] $(date): All containers have been rebooted at least once. Exiting monitor."
                pkill -P $$ inotifywait
                exit 0
            fi
        fi
    done
done

exit 0
