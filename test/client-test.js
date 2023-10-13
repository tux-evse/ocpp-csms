const { RPCClient } = require('ocpp-rpc');

const cli = new RPCClient({
    endpoint: 'ws://csms-host:9310/ws', // the OCPP endpoint URL
    identity: 'Tux-Basic',
    password: 'snoopy',            // the OCPP identity
    protocols: ['ocpp1.6'],          // client understands ocpp1.6 subprotocol
    strictMode: true,                // enable strict validation of requests & responses
});

// connect to the OCPP server
cli.connect()
    .catch(x => { console.log('fail to connect OCPP server'); process.exit(1) })
    .then(x => {
        console.log('connected to ocpp server')

        // send a BootNotification request and await the response
        cli.call('BootNotification', {
            chargePointVendor: "ocpp-rpc",
            chargePointModel: "ocpp-rpc",
        })
            .catch(x => { console.log('fail BootNotification call'); process.exit(1) })
            .then(bootResponse => {
                console.log('Status ocpp:', bootResponse)

                // check that the server accepted the client
                if (bootResponse.status === 'Accepted') {

                    // send a Heartbeat request and await the response
                    cli.call('Heartbeat', {})
                        .catch(x => { console.log('fail Heartbeat call'); process.exit(1) })
                        .then(heartbeatResponse => {

                            // read the current server time from the response
                            console.log('Server time is:', heartbeatResponse.currentTime);

                            // send a StatusNotification request for the controller
                            cli.call('StatusNotification', {
                                connectorId: 0,
                                errorCode: "NoError",
                                status: "Available",
                            });
                        })
                }
            })
    })