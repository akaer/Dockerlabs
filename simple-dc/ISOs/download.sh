#!/usr/bin/env bash

# Set global script options
set -euo pipefail

# Windows Server 2025
if [[ ! -f '26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso' ]]; then
    curl -SLO https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
fi

exit 0
