# OCPP test with maeve-csms/podman

## Dependencies

* MAEVE-SCSM: source code: https://github.com/thoughtworks/maeve-csms
* podman: check podman with ```podman run --rm hello-world```

## Config

*csms-host*: should point to ip-addr of the containers pod (edit /etc/hosts)
  * privileged: set 'csms-host' to a valid ip-addr within podman bridge
  * unprivileged: set 'csms-host' as an alias to localhost

## rebuilding & start docker containers

Build and start podman maeve-csms containers. The script should work for both privileged and un-privilege Podman mode. MAEVE_SRCDIR should point to the git clone of maeve-csms project.

if not config/certificates/csms.pem is not present, the script should regenerate both TLS and https://hubject.stoplight.io certificates. (check https://hubject.stoplight.io/ for further information)

```
MAEVE_SRCDIR=../maeve-csms ./podman-maeve-start.sh
```
Check containers are up and running
```
podman ps -f pod=csms-pod
```
## Testing ocpp-csms connectivity

Create a charger entry. Note: default config use in-memory store that is wiped out each time you restart the pod.
```
PWD_ASCII="snoopy"
PWD_BASE64=`echo -n $PWD_ASCII | openssl dgst -sha256 -binary | openssl base64`
curl http://csms-host:9410/api/v0/cs/Tux-Basic -H 'content-type: application/json' -d "{\"securityProfile\":0, \"base64SHA256Password\":\"$PWD_BASE64\"}"
```

Check your charger-id is visible from csms service.
```
curl http://csms-host:9410/api/v0/cs/Tux-Basic/auth
```

Start an OCPP client connection. Test directory hold a simple client test based on ocpp-rpc for OCPP-1.6.
```
cd test
npm install
node client-test.js
```

## Debug

Access containers log
```
podman pod logs -f csms-pod
```

Enter Debug container. To check pod configuration from inside your may enter the debug container.
```
podman exec -it csms-debug sh
```