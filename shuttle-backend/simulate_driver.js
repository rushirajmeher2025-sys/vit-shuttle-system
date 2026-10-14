const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8080?role=driver');

ws.on('open', () => {
    console.log('Driver connected to server');
    
    // VIT Vellore Campus Base Coordinates
    let lat = 12.9692;
    let lng = 79.1559;

    setInterval(() => {
        // Simulate some random movement
        lat += (Math.random() - 0.5) * 0.0005;
        lng += (Math.random() - 0.5) * 0.0005;
        
        const payload = {
            type: 'SHUTTLE_MOVED',
            shuttleId: 'vit_shuttle_1',
            lat: lat,
            lng: lng,
            timestamp: new Date().toISOString()
        };
        
        console.log('Sending shuttle update:', payload);
        ws.send(JSON.stringify(payload));
    }, 2000); // update every 2 seconds
});

ws.on('error', (err) => {
    console.error('WebSocket Error:', err);
});
