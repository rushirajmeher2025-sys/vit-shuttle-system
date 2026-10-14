require('dotenv').config();
const WebSocket = require('ws');
const http = require('http');
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL || 'https://YOUR_SUPABASE_URL.supabase.co';
const supabaseKey = process.env.SUPABASE_ANON_KEY || 'YOUR_SUPABASE_ANON_KEY';
const supabase = createClient(supabaseUrl, supabaseKey);

// State for 5-minute batch logging
let activeShuttlePositions = {};
let recentCrowdingReports = [];

const fs = require('fs');
const path = require('path');

const server = http.createServer(async (req, res) => {
    const parsedUrl = (req.url || '').split('?')[0];

    // Serve Web Frontend
    if (req.method === 'GET' && (parsedUrl === '/' || parsedUrl === '' || parsedUrl === '/index.html')) {
        const indexPath = path.join(__dirname, 'public', 'index.html');
        try {
            const html = fs.readFileSync(indexPath, 'utf-8');
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(html);
        } catch (err) {
            res.writeHead(500, { 'Content-Type': 'text/plain' });
            res.end('Error loading web interface');
        }
        return;
    }

    // API Endpoint: /api/analytics/peak-hours
    if (req.method === 'GET' && req.url === '/api/analytics/peak-hours') {
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Access-Control-Allow-Origin', '*');
        
        try {
            const peakHoursHeatmap = {
                "08:00": { averageCrowding: "High", shuttleFrequency: 12 },
                "09:00": { averageCrowding: "Moderate", shuttleFrequency: 10 },
                "10:00": { averageCrowding: "Low", shuttleFrequency: 5 },
                "11:00": { averageCrowding: "Low", shuttleFrequency: 4 },
                "12:00": { averageCrowding: "Moderate", shuttleFrequency: 6 },
                "13:00": { averageCrowding: "High", shuttleFrequency: 15 },
                "17:00": { averageCrowding: "High", shuttleFrequency: 14 }
            };
            
            res.writeHead(200);
            res.end(JSON.stringify({ success: true, data: peakHoursHeatmap }));
        } catch (e) {
            res.writeHead(500);
            res.end(JSON.stringify({ success: false, error: e.message }));
        }
    } else {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Not Found' }));
    }
});

const wss = new WebSocket.Server({ server });

let cachedStops = [];

// Haversine formula to compute distance in km and ETA in minutes
function calculateETA(shuttleLat, shuttleLng, stopLat, stopLng, speed = 18) {
    if (!speed || speed <= 0) {
        speed = 18;
    }

    const R = 6371;
    const dLat = (stopLat - shuttleLat) * Math.PI / 180;
    const dLng = (stopLng - shuttleLng) * Math.PI / 180;
    const a = 
        Math.sin(dLat/2) * Math.sin(dLat/2) +
        Math.cos(shuttleLat * Math.PI / 180) * Math.cos(stopLat * Math.PI / 180) * 
        Math.sin(dLng/2) * Math.sin(dLng/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    const distanceKm = R * c;

    const timeHours = distanceKm / speed;
    const timeMinutes = timeHours * 60;
    
    return {
        distanceKm: parseFloat(distanceKm.toFixed(2)),
        etaMinutes: Math.round(timeMinutes)
    };
}

async function fetchStops() {
    if (supabaseUrl.includes('YOUR_SUPABASE_URL')) {
        console.log('Using placeholder Supabase URL. Skipping stops fetch.');
        cachedStops = [
            { id: 1, name: 'Main Gate', lat: 12.9692, lng: 79.1559 },
            { id: 2, name: 'SJT', lat: 12.9715, lng: 79.1633 }
        ];
        return;
    }
    try {
        const { data: stops, error } = await supabase.from('stops').select('*');
        if (error) {
            console.error('Error fetching stops:', error.message);
            return;
        }
        cachedStops = stops || [];
        console.log(`Loaded ${cachedStops.length} stops from Supabase.`);
    } catch (err) {
        console.error('Failed to fetch stops:', err);
    }
}

// 5-Minute Batch Logger
setInterval(async () => {
    try {
        if (supabaseUrl.includes('YOUR_SUPABASE_URL')) {
            console.log('Skipping Supabase batch log (placeholder URL in use).');
            return;
        }
        
        // 1. Log active shuttle positions
        const shuttleLogs = Object.values(activeShuttlePositions).map(shuttle => ({
            shuttle_id: shuttle.shuttleId,
            lat: shuttle.lat,
            lng: shuttle.lng,
            speed: shuttle.speed,
            timestamp: new Date().toISOString()
        }));
        
        if (shuttleLogs.length > 0) {
            await supabase.from('shuttle_logs').insert(shuttleLogs);
        }

        // 2. Log crowding reports
        if (recentCrowdingReports.length > 0) {
            const reportsToInsert = [...recentCrowdingReports];
            recentCrowdingReports = []; // Clear immediately to avoid duplicates while awaiting
            await supabase.from('crowding_reports').insert(reportsToInsert);
        }
        
        console.log(`[Batch Log] Inserted ${shuttleLogs.length} shuttle positions and ${recentCrowdingReports.length} crowding reports.`);
    } catch (err) {
        console.error('[Batch Log] Error writing to Supabase:', err.message);
    }
}, 5 * 60 * 1000); // 300,000 ms = 5 minutes


wss.on('connection', (ws, req) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const role = url.searchParams.get('role') || 'passenger';
    const clientShuttleId = url.searchParams.get('shuttleId');
    
    console.log(`Client connected with role: ${role}${clientShuttleId ? ` (shuttle: ${clientShuttleId})` : ''}`);
    ws.role = role;
    ws.shuttleId = clientShuttleId;

    // Send currently active shuttles to newly connected client immediately
    const activeList = Object.values(activeShuttlePositions).map(s => {
        const stopETAs = cachedStops.map(stop => {
            const etaData = calculateETA(s.lat, s.lng, stop.lat, stop.lng, s.speed);
            return {
                stopId: stop.id,
                stopName: stop.name,
                distanceKm: etaData.distanceKm,
                etaMinutes: etaData.etaMinutes
            };
        });
        return {
            ...s,
            stopETAs
        };
    });

    if (activeList.length > 0) {
        ws.send(JSON.stringify({
            type: 'ALL_SHUTTLES',
            shuttles: activeList
        }));
    }

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === 'LOCATION_UPDATE' || data.type === 'SHUTTLE_MOVED') {
                const speed = data.speed !== undefined ? data.speed : 18;
                const shuttleId = data.shuttleId || 'vit_general_bus_101';
                const shuttleType = data.shuttleType || (shuttleId.includes('faculty') ? 'faculty' : 'general');
                const fare = data.fare !== undefined ? data.fare : (shuttleType === 'faculty' ? 0 : 20);
                const name = data.name || (shuttleType === 'faculty' ? 'Faculty Exclusive Shuttle' : 'General Campus Bus');
                
                // Track for 5-minute interval logging & state caching
                activeShuttlePositions[shuttleId] = {
                    shuttleId: shuttleId,
                    name: name,
                    shuttleType: shuttleType,
                    fare: fare,
                    lat: data.lat,
                    lng: data.lng,
                    speed: speed,
                    heading: data.heading || 0,
                    capacity: data.capacity || (shuttleType === 'faculty' ? 20 : 40),
                    lastUpdated: new Date().toISOString()
                };
                
                // Calculate ETA for all cached stops
                const stopETAs = cachedStops.map(stop => {
                    const etaData = calculateETA(data.lat, data.lng, stop.lat, stop.lng, speed);
                    return {
                        stopId: stop.id,
                        stopName: stop.name,
                        distanceKm: etaData.distanceKm,
                        etaMinutes: etaData.etaMinutes
                    };
                });
                
                const broadcastPayload = {
                    ...data,
                    type: 'SHUTTLE_MOVED',
                    shuttleId: shuttleId,
                    name: name,
                    shuttleType: shuttleType,
                    fare: fare,
                    stopETAs: stopETAs
                };

                // Broadcast to all listening passenger/student/faculty/web clients
                wss.clients.forEach((client) => {
                    if (client.readyState === WebSocket.OPEN && client.role !== 'driver') {
                        client.send(JSON.stringify(broadcastPayload));
                    }
                });
            } else if (data.type === 'REPORT_CROWDING') {
                // Track for 5-minute interval logging
                recentCrowdingReports.push({
                    shuttle_id: data.shuttleId || 'unknown',
                    level: data.level,
                    timestamp: data.timestamp || new Date().toISOString()
                });
                
                // Broadcast crowding update in real-time
                wss.clients.forEach((client) => {
                    if (client.readyState === WebSocket.OPEN && client.role !== 'driver') {
                        client.send(JSON.stringify(data));
                    }
                });
            }
        } catch (e) {
            console.error('Invalid message', e);
        }
    });

    ws.on('close', () => {
        console.log(`Client disconnected (role: ${role})`);
    });
});

server.listen(8080, async () => {
    console.log('Server is running on port 8080 (HTTP + WS)');
    await fetchStops();
});
