const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8080?role=driver');

// Waypoints for General Campus Bus #101 (Fare: ₹20, For Everyone)
const generalRouteWaypoints = [
    { lat: 12.9692, lng: 79.1559 }, // Main Gate
    { lat: 12.9695, lng: 79.1573 },
    { lat: 12.9698, lng: 79.1588 }, // Main Building (MB)
    { lat: 12.9708, lng: 79.1610 }, // Central Library
    { lat: 12.9715, lng: 79.1633 }, // Silver Jubilee Tower (SJT)
    { lat: 12.9735, lng: 79.1620 }, // SMV
    { lat: 12.9750, lng: 79.1610 }, // Men's Hostel
    { lat: 12.9740, lng: 79.1595 },
    { lat: 12.9730, lng: 79.1585 }, // Technology Tower (TT)
    { lat: 12.9705, lng: 79.1565 }, // Food Mall
];

// Waypoints for Faculty Exclusive Shuttle #201 (Fare: Free ₹0, Only Faculty)
const facultyRouteWaypoints = [
    { lat: 12.9715, lng: 79.1633 }, // SJT Faculty Wing
    { lat: 12.9723, lng: 79.1609 },
    { lat: 12.9730, lng: 79.1585 }, // Technology Tower (TT / Dean Office)
    { lat: 12.9714, lng: 79.1586 },
    { lat: 12.9698, lng: 79.1588 }, // MB Admin Block
    { lat: 12.9692, lng: 79.1559 }, // Main Gate
    { lat: 12.9702, lng: 79.1600 }, // Faculty Quarters / Staff Club
];

function interpolate(p1, p2, t) {
    return {
        lat: p1.lat + (p2.lat - p1.lat) * t,
        lng: p1.lng + (p2.lng - p1.lng) * t
    };
}

class SimulatedShuttle {
    constructor(config) {
        this.shuttleId = config.shuttleId;
        this.name = config.name;
        this.shuttleType = config.shuttleType; // 'general' | 'faculty'
        this.fare = config.fare; // 20 | 0
        this.capacity = config.capacity;
        this.waypoints = config.waypoints;
        this.speed = config.speed;
        this.currentIndex = 0;
        this.progress = 0.0;
        this.step = config.step || 0.08;
    }

    getNextPosition() {
        this.progress += this.step;
        if (this.progress >= 1.0) {
            this.progress = 0.0;
            this.currentIndex = (this.currentIndex + 1) % this.waypoints.length;
        }

        const nextIndex = (this.currentIndex + 1) % this.waypoints.length;
        const p1 = this.waypoints[this.currentIndex];
        const p2 = this.waypoints[nextIndex];
        const pos = interpolate(p1, p2, this.progress);

        // Calculate heading in degrees
        const dy = p2.lat - p1.lat;
        const dx = p2.lng - p1.lng;
        const heading = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360;

        return {
            type: 'LOCATION_UPDATE',
            shuttleId: this.shuttleId,
            name: this.name,
            shuttleType: this.shuttleType,
            fare: this.fare,
            capacity: this.capacity,
            lat: parseFloat(pos.lat.toFixed(6)),
            lng: parseFloat(pos.lng.toFixed(6)),
            speed: parseFloat((this.speed + (Math.random() * 2 - 1)).toFixed(1)),
            heading: parseFloat(heading.toFixed(1)),
            timestamp: new Date().toISOString()
        };
    }
}

const shuttles = [
    new SimulatedShuttle({
        shuttleId: 'vit_general_bus_101',
        name: 'General Campus Bus #101',
        shuttleType: 'general',
        fare: 20,
        capacity: 40,
        waypoints: generalRouteWaypoints,
        speed: 22.0,
        step: 0.12
    }),
    new SimulatedShuttle({
        shuttleId: 'vit_faculty_shuttle_201',
        name: 'Faculty Exclusive Shuttle #201',
        shuttleType: 'faculty',
        fare: 0,
        capacity: 20,
        waypoints: facultyRouteWaypoints,
        speed: 19.5,
        step: 0.10
    })
];

ws.on('open', () => {
    console.log('Driver Simulator connected to WebSocket Server.');
    console.log('Broadcasting 2 Active VIT Shuttles:');
    console.log('1. [vit_general_bus_101] General Campus Bus - Fare: Rs 20 (Everyone)');
    console.log('2. [vit_faculty_shuttle_201] Faculty Exclusive Shuttle - Fare: FREE (Faculty Only)');

    setInterval(() => {
        shuttles.forEach((shuttle) => {
            const payload = shuttle.getNextPosition();
            ws.send(JSON.stringify(payload));
        });
    }, 2000);
});

ws.on('close', () => {
    console.log('Driver Simulator disconnected from server.');
});

ws.on('error', (err) => {
    console.error('WebSocket Error in Driver Simulator:', err.message);
});
