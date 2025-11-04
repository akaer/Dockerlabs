#!/usr/bin/env bash

set -Eeuo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CERTS_DIR="${SCRIPT_DIR}/../scripts/certs"
readonly DOMAIN="${1:-qs-lab.local}"
readonly ORG="Umbrella Corp."
readonly CA_VALIDITY=3650  # 10 years
readonly CERT_VALIDITY=3650
readonly KEY_SIZE=2048

# Create certificate directory
mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"
rm -f ./*

# Create Root CA
create_root_ca() {
    local -r ca_key="${DOMAIN}.ca.key"
    local -r ca_crt="${DOMAIN}.ca.crt"

    echo "[*] Creating Root CA for ${DOMAIN}..."

    # Generate CA private key (unencrypted for automation; encrypt if needed)
    openssl genrsa -out "${ca_key}" "${KEY_SIZE}" 2>/dev/null
    chmod 400 "${ca_key}"

    # Create self-signed CA certificate
    openssl req -x509 -new -sha256 \
        -key "${ca_key}" \
        -days "${CA_VALIDITY}" \
        -out "${ca_crt}" \
        -subj "/O=${ORG}/CN=${DOMAIN} Root CA" \
        -extensions v3_ca \
        -config <(cat <<-EOF
                        [req]
                        distinguished_name = req_dn
                        [req_dn]
                        [v3_ca]
                        basicConstraints = critical,CA:TRUE,pathlen:0
                        keyUsage = critical,digitalSignature,keyCertSign,cRLSign
                        subjectKeyIdentifier = hash
                        authorityKeyIdentifier = keyid:always,issuer
EOF
        )

    # Create DER format for Windows compatibility
    openssl x509 -in "${ca_crt}" -outform der -out "${DOMAIN}.ca.der"

    echo "[✓] Root CA created"
    openssl x509 -in "${ca_crt}" -noout -subject -dates
}

# Create end-entity certificate
create_certificate() {
    local -r cn="${1}"
    local -r cert_type="${2:-serverAuth,clientAuth}"  # default to dual-purpose
    local -r key="${cn}.key"
    local -r csr="${cn}.csr"
    local -r crt="${cn}.crt"
    local -r ca_crt="${DOMAIN}.ca.crt"
    local -r ca_key="${DOMAIN}.ca.key"

    echo "[*] Creating certificate for ${cn}..."

    # Generate private key
    openssl genrsa -out "${key}" "${KEY_SIZE}" 2>/dev/null
    chmod 400 "${key}"

    # Create CSR
    openssl req -new -sha256 \
        -key "${key}" \
        -out "${csr}" \
        -subj "/O=${ORG}/CN=${cn}"

    # Sign certificate with CA
    openssl x509 -req -sha256 \
        -in "${csr}" \
        -CA "${ca_crt}" \
        -CAkey "${ca_key}" \
        -CAcreateserial \
        -out "${crt}" \
        -days "${CERT_VALIDITY}" \
        -extensions v3_req \
        -extfile <(cat <<-EOF
                        [v3_req]
                        basicConstraints = critical,CA:FALSE
                        keyUsage = critical,keyEncipherment,dataEncipherment,digitalSignature
                        extendedKeyUsage = critical,${cert_type}
                        subjectAltName = DNS:${cn}
                        subjectKeyIdentifier = hash
                        authorityKeyIdentifier = keyid:always,issuer
EOF
        )

    # Append CA certificate for chain validation
    cat "${ca_crt}" >> "${crt}"

    # Create PKCS#12 for Windows (password-less for automation)
    openssl pkcs12 -export -passout pass: \
        -inkey "${key}" \
        -in "${crt}" \
        -out "${cn}.pfx"

    # Cleanup
    rm -f "${csr}"

    echo "[✓] Certificate created for ${cn}"
    openssl x509 -in "${crt}" -noout -subject -dates
}

# Main execution
main() {
    create_root_ca

    # Create server certificates
    create_certificate "dc.${DOMAIN}" "serverAuth,clientAuth"
    create_certificate "web.${DOMAIN}" "serverAuth"
    create_certificate "client.${DOMAIN}" "clientAuth"
    create_certificate "sql1.${DOMAIN}" "serverAuth"
    create_certificate "sql2.${DOMAIN}" "serverAuth"

    echo "[✓] All certificates generated successfully in ${CERTS_DIR}"
}

main
