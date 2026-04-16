#!/usr/bin/env bash

INCLUDEFILE="$(dirname "$0")/demo.env"
readonly INCLUDEFILE

if [[ -f "$INCLUDEFILE" ]]; then
    # shellcheck source=./env.demo
    source "$INCLUDEFILE"
fi

# Verify ISO(s) referenced in compose.yml exist in ./ISOs
check_isos_in_compose() {
    local base_dir comp_file iso_dir
    base_dir="$(dirname "$0")"
    comp_file="$base_dir/compose.yml"
    iso_dir="$base_dir/ISOs"

    if [[ ! -f "$comp_file" ]]; then
        echo "Error: compose.yml not found at: $comp_file"
        return 1
    fi

    if [[ ! -d "$iso_dir" ]]; then
        echo "Error: ISOs directory not found at: $iso_dir"
        return 1
    fi

    # Extract ISO paths referenced under ./ISOs in compose.yml (left side of volume mapping)
    mapfile -t iso_refs < <(grep -Eo '\./ISOs/[^": ]+\.iso' "$comp_file" | sort -u)

    if [[ ${#iso_refs[@]} -eq 0 ]]; then
        echo "Info: No ISO references found in compose.yml under ./ISOs."
        return 0
    fi

    echo "Verifying ISO files referenced in compose.yml:"
    local missing=0
    for rel in "${iso_refs[@]}"; do
        # Normalize ./ prefix and check file existence
        local file="$base_dir/${rel#./}"
        if [[ -f "$file" ]]; then
            echo "  OK: $(basename "$file") exists at $file"
        else
            echo "  MISSING: $(basename "$file") expected at $file"
            missing=1
        fi
    done

    if [[ $missing -ne 0 ]]; then
        echo "[!] Error: One or more ISO files referenced in compose.yml are missing in ./ISOs. Please download them!"
        return 1
    fi

    return 0
}

# Abort if ISO verification fails
if ! check_isos_in_compose; then
    echo "Aborting deployment due to missing ISO files."
    exit 1
fi

docker compose --env-file "$INCLUDEFILE" up -d

