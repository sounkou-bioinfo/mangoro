#!/bin/bash
# vendorMangos.sh: Vendors go.nanomsg.org/mangos/v3 into src/go for local builds
# Usage: bash vendorMangos.sh

set -xe
cd "$(dirname "$0")/../inst/go"

# Initialize go module if not present
if [ ! -f go.mod ]; then
    go mod init mango.local || exit 1
fi

go get go.nanomsg.org/mangos/v3@2c434adf4860dd26da9fe96329237fe5aabc6acc

go mod tidy

go mod vendor

echo "Vendoring complete. Mangos and dependencies are now in ./vendor."
