#!/usr/bin/env bash

BEARER_TOKEN=$(curl -s https://hubject.stoplight.io/api/v1/projects/cHJqOjk0NTg5/nodes/6bb8b3bc79c2e-authorization-token | jq -r .data | sed -n '/Bearer/s/^.*Bearer //p')

certs=$(curl -s https://open.plugncharge-test.hubject.com/cpo/cacerts/ISO15118-2 \
  -H 'Accept: application/pkcs10, application/pkcs7' \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -H 'Content-Transfer-Encoding: application/pkcs10' | openssl enc -base64 -d | openssl pkcs7 -inform DER -print_certs)

echo "${certs}" | awk '/subject.*CN.*=.*CPO Sub1 CA QA G1.2/,/END CERTIFICATE/' > cpo_sub_ca1.pem
echo "${certs}" | awk '/subject.*CN.*=.*CPO Sub2 CA QA G1.2.1/,/END CERTIFICATE/' > cpo_sub_ca2.pem
echo "${certs}" | awk '/subject.*CN.*=.*V2G Root CA QA G1/,/END CERTIFICATE/' > root-V2G-cert.pem
cat cpo_sub_ca1.pem cpo_sub_ca2.pem > trust.pem
