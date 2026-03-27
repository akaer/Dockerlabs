#!/usr/bin/env bash

# Set global script options
set -euo pipefail

# Windows 11 Enterprise
if [[ ! -f '26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso'  ]]; then
    curl -SLO https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso
fi

exit 0
