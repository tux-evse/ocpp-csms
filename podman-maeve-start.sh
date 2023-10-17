#!/bin/bash

# Script to start maeve-cms inside a podman 'pod'
# author: Fulup Ar Foll (iot.bzh)
# Licence: Apache-v2

# Note:
# This script expect csms-host (csms-pod ip-addr) to be defined within /etc/host|dns
# All exchange between container should go true 'csms-pod' ip-addr/name

if test -z "$MAEVE_SRCDIR"; then
    export MAEVE_SRCDIR='.'
fi

if test -z "$MAEVE_CONFDIR"; then
    export MAEVE_CONFDIR=`dirname $0`
fi

if ! test -f "$MAEVE_SRCDIR/manager/Dockerfile"; then
  echo "ERROR: invalid 'maeve-scms' sources not found. Check => MAEVE_SRCDIR=../xxxx/maeve-csms ./podman-maeve-start.sh"
  exit 1
fi

# if needed regenerate TLLS+OCCP certificates
if ! test -f "$MAEVE_CONFDIR/config/certificates/trust.pem"; then
    mkdir -p $MAEVE_CONFDIR/config/certificates
    make --directory="$MAEVE_CONFDIR/config/certificates" --file="../../config/scripts/Makefile"
    chmod -f a+r $MAEVE_CONFDIR/config/certificates/*

    if ! test -s "$MAEVE_CONFDIR/config/certificates/trust.pem"; then
        echo "ERROR: fail to retreive hubject.stoplight.io certificates (check daily authentication token)"
        rm $MAEVE_CONFDIR/config/certificates/trust.pem
        exit 1
    fi
fi

CSMS_ADDR=`getent hosts csms-host | awk '{ print $1 }'`
if test -z "$CSMS_ADDR"; then
  echo "ERROR: 'csms-host' should be resolvable and point to podman bridge(privileged) or localhost(un-privileged)"
  exit 1
fi

# restart from stratch
echo "cleaning old 'csms-pod' containers"
podman pod rm -f csms-pod

# create podman/pod
if test "$UID" != 0; then
  # unprivileges mode: containers port are exposed through localhost port forwaring
  podman pod create --name=csms-pod --hostname=csms-host -p 9310:9310 -p 9311:9311 -p 9312:9312 -p 9410:9410 -p 9411:9411 -v $MAEVE_CONFDIR/config:/config:Z
else
  # privileged mode: containers use a routable ip-addr from podman default bridge
  podman pod create --name=csms-pod --hostname=csms-host --ip=$CSMS_ADDR --network=podman  -v $MAEVE_CONFDIR/config:/config:Z # privileged
fi

# after pod creation csms-host should be pingable
ping -q -c 1 -w 1 $CSMS_ADDR
if test $? != 0; then
  echo "ERROR: Fail to ping [csms-host=$CSMS_ADDR] please check /etc/hosts "
  exit 1
fi


# rebuild local-image
for DOCKER_DIR in  $MAEVE_SRCDIR/*; do
    DOCKER_FILE=$DOCKER_DIR/Dockerfile
    if test -f $DOCKER_FILE; then
        DOCKER_IMG=`basename $DOCKER_DIR`
        echo "Building '$DOCKER_IMG' images"
        podman build -t csms-$DOCKER_IMG -f $DOCKER_FILE
        if test $? != 0; then
           echo "Fail to rebuild  $DOCKER_FILE"
           exit
        fi
        echo "--- Done localhot/$DOCKER_IMG image"
    fi
done

# start container within pod
podman create --pod csms-pod --name=csms-debug --interactive alpine
podman create --pod csms-pod --name=csms-mqtt -u 10000:10000 eclipse-mosquitto:2 "/usr/sbin/mosquitto" "-c" "/config/mosquitto/mosquitto.conf"
podman create --pod csms-pod  --name=csms-firestore google/cloud-sdk gcloud emulators firestore start --host-port=0.0.0.0:8080
podman create --pod csms-pod --name=csms-manager --requires=csms-mqtt -u 10000:10000 localhost/csms-manager serve -c /config/manager/config.toml
podman create --pod csms-pod --name=csms-gateway --requires=csms-mqtt,csms-manager localhost/csms-gateway serve --ws-addr :9310 --wss-addr :9311 --status-addr :9312 --tls-server-cert /config/certificates/csms.pem --tls-server-key /config/certificates/csms.key --tls-trust-cert /config/certificates/trust.pem --mqtt-addr mqtt://csms-host:1883 --manager-api-addr http://csms-host:9410

for CONTAINER in csms-debug csms-firestore csms-mqtt csms-manager csms-gateway; do
 echo starting: $CONTAINER
 podman start $CONTAINER
 if test $? != 0; then
   echo "fail to start container: $CONTAINER"
   exit
 fi
done

PWD_ASCII="snoopy"
echo "Create your 1st charger station (basic-auth pwd=$PWD_ASCII)"
echo ----------------------------------------------------------
PWD_BASE64=`echo -n $PWD_ASCII | openssl dgst -sha256 -binary | openssl base64`
cat <<!EOF
Basic-Auth: curl http://csms-host:9410/api/v0/cs/Tux-Auth -H 'content-type: application/json' -d "{\"securityProfile\":0, \"base64SHA256Password\":\"$PWD_BASE64\"}"
TLS-Auth:   curl http://csms-host:9410/api/v0/cs/Tux-TLS -H 'content-type: application/json' -d "{\"securityProfile\":1, \"base64SHA256Password\":\"$PWD_BASE64\"}"
TlS-CERT:   curl http://csms-host:9410/api/v0/cs/Tux-CERT -H 'content-type: application/json' -d "{\"securityProfile\":2}"
!EOF

# create a dummy account for 'ram-only' testing storae config
curl http://csms-host:9410/api/v0/cs/Tux-Auth -H 'content-type: application/json' -d "{\"securityProfile\":0, \"base64SHA256Password\":\"$PWD_BASE64\"}"
curl http://csms-host:9410/api/v0/cs/Tux-TLS -H 'content-type: application/json' -d "{\"securityProfile\":1, \"base64SHA256Password\":\"$PWD_BASE64\"}"
curl http://csms-host:9410/api/v0/cs/Tux-CERT -H 'content-type: application/json' -d "{\"securityProfile\":2}"

echo ""
echo "Create your initial authen token"
echo ----------------------------------
cat << !EOF
curl http://csms-host:9410/api/v0/token -H 'content-type: application/json' -d '{
  "countryCode": "GB",
  "partyId": "TWK",
  "type": "RFID",
  "uid": "DEADBEEF",
  "contractId": "GBTWK012345678V",
  "issuer": "Thoughtworks",
  "valid": true,
  "cacheMode": "ALWAYS"
}'
!EOF
echo ""

echo "Connect with ocpp-sebsocket with ws://csms-host:9310 or wss://csms-host:9311"
echo ""

echo "to debug container networking issues or share file mapping"
echo " podman start csms-debug && podman exec -it csms-debug sh"

echo "to enter gateway or manager container"
echo " podman exec -it csms-gateway busybox sh"

echo "to check mqtt exchanges from you desktop/host"
echo "podman exec -it csms-mqtt /usr/bin/mosquitto_sub -v -h localhost -p 1883 -t '#'"

echo "to debug a non starting container"
echo " podman start -a csms-gateway"




