const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8080?role=driver');

// Waypoints for Men's Hostels Express Bus #101 (Fare: ₹20, Student/General)
const mensHostelRouteWaypoints = [
    { lat: 12.9723, lng: 79.1627 }, // Vajpayee / Q & R-Block Cluster
    { lat: 12.9712, lng: 79.1612 }, // L, M, N, P Block Cluster
    { lat: 12.9701, lng: 79.1601 }, // MH Food Court & All Maart Area
    { lat: 12.9692, lng: 79.1588 }, // GD Naidu Block / A-G Blocks
    { lat: 12.9691, lng: 79.1560 }, // TT / Central Library Junction
    { lat: 12.9708, lng: 79.1558 }, // SJT (Silver Jubilee Tower)
];

// Waypoints for Women's Hostel Express Bus #102 (Fare: ₹20, Student/General)
const womensHostelRouteWaypoints = [
    { lat: 12.9675, lng: 79.1595 }, // Main Ladies' Hostel (LH) Gate
    { lat: 12.9668, lng: 79.1602 }, // LH G Block
    { lat: 12.9688, lng: 79.1561 }, // Periyar EVR Central Library
    { lat: 12.9698, lng: 79.1552 }, // SMV / MB Block Portico
    { lat: 12.9708, lng: 79.1558 }, // SJT (Silver Jubilee Tower)
];

// Waypoints for Faculty Exclusive Shuttle #201 (Fare: Free ₹0, Only Faculty)
const facultyRouteWaypoints = [
    { lat: 12.9682, lng: 79.1542 }, // Main Gate 1 Entrance
    { lat: 12.9665, lng: 79.1551 }, // Main Gate 2 Entrance
    { lat: 12.9688, lng: 79.1550 }, // Dr. M.G.R. Central Admin Block
    { lat: 12.9658, lng: 79.1578 }, // Staff & Faculty Quarters Zone
    { lat: 12.9695, lng: 79.1563 }, // TT (Technology Tower)
    { lat: 12.9708, lng: 79.1558 }, // SJT (Silver Jubilee Tower)
    { lat: 12.9715, lng: 79.1548 }, // Gandhi Block / Netaji Block
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
        name: "General Campus Bus #101 (Men's Hostels)",
        shuttleType: 'general',
        fare: 20,
        capacity: 40,
        waypoints: mensHostelRouteWaypoints,
        speed: 22.0,
        step: 0.10
    }),
    new SimulatedShuttle({
        shuttleId: 'vit_general_bus_102',
        name: "General Campus Bus #102 (Women's Hostel)",
        shuttleType: 'general',
        fare: 20,
        capacity: 35,
        waypoints: womensHostelRouteWaypoints,
        speed: 21.0,
        step: 0.10
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
    console.log('Broadcasting 3 Active VIT Campus Shuttles:');
    console.log("1. [vit_general_bus_101] General Campus Bus #101 (Men's Hostels) - Fare: Rs 20");
    console.log("2. [vit_general_bus_102] General Campus Bus #102 (Women's Hostel) - Fare: Rs 20");
    console.log("3. [vit_faculty_shuttle_201] Faculty Exclusive Shuttle #201 - Fare: FREE");

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
