# VIT Shuttle Tracking System

## Campus Fleet & Shuttle Categories

The VIT Shuttle system supports two distinct shuttle service categories across all personas:

| Category | Eligibility | Fare | Badge / Visuals | Capabilities |
| :--- | :--- | :--- | :--- | :--- |
| **🚌 General Campus Bus** | Open for everyone (Students, Faculty, Staff, Visitors) | **₹20** (Flat fare) | Blue (`#0284C7`) • `BUS 101 • ₹20` | Real-time GPS & ETAs, QR Boarding Pass booking simulator, Crowding reporting |
| **⭐ Faculty Exclusive Shuttle** | Strictly VIT Faculty Only (`@vit.ac.in`) | **FREE (₹0)** | Emerald (`#059669`) • `FACULTY • FREE` | Real-time GPS & ETAs, VIP Faculty Digital Transit Pass, Access restriction for non-faculty |

---

## Supported Scenarios

1. **Student Persona (`@vitstudent.ac.in`)**:
   - Accesses the **Student Portal**.
   - Views both General Bus and Faculty Shuttle markers on the interactive campus map.
   - Can select the General Bus, check upcoming stop ETAs, and tap **"Book / Pay Ticket (₹20)"** to generate a digital QR boarding pass.
   - If attempting to board the Faculty Shuttle, the app presents a clear restriction alert informing that the service is restricted to faculty members and prompts switching to the General Bus.
   - Submits live crowding feedback (Low / Med / Full).

2. **Faculty Persona (`@vit.ac.in`)**:
   - Accesses the **Faculty Portal**.
   - Authenticates using their official `@vit.ac.in` email.
   - Gets access to the **Faculty Exclusive Shuttle (100% FREE)** with one-tap generation of the verified **VIT Faculty VIP Transit Pass**.
   - Can also view and ride the General Bus as needed.

3. **Shuttle Driver Persona**:
   - Accesses the **Driver Console**.
   - Selects which shuttle they are operating for their shift:
     - **General Campus Bus #101** (Instructed to collect ₹20 fare / scan QR).
     - **Faculty Exclusive Shuttle #201** (Instructed to verify Faculty ID / digital pass; complimentary ride).
   - Starts their driving shift to broadcast live telemetry (GPS coordinates, speedometer in KM/H, heading) over WebSockets to all passengers.

4. **Multi-Shuttle Real-Time Simulation**:
   - `simulate_driver.js` simulates both vehicles driving smoothly in synchronized loops along VIT Vellore campus waypoints (Main Gate, MB, SJT, TT, Men's Hostel).
   - Backend broadcasts metadata (`shuttleType`, `fare`, `name`, `speed`, and per-stop ETAs) simultaneously.
   - Both the Flutter Mobile App and the Web Dashboards (`http://localhost:8080/`) display both shuttles on the map simultaneously with filter toggles (`All`, `General`, `Faculty`).

---

## Mobile App (Flutter)
### Running Locally or Testing on Phone
- The web app runs on `http://0.0.0.0:8000` (accessible from any phone on campus Wi-Fi at `http://<YOUR_LOCAL_IP>:8000`).
- The app automatically detects host IP and connects to the backend WebSocket at port `8080`.

### Building the APK
You can build the production Android APK automatically using the provided scripts in the root directory:
- **Windows**: Open PowerShell and run `.\build_app.ps1`
- **Mac/Linux**: Open terminal and run `./build_app.sh` (ensure it's executable via `chmod +x build_app.sh`)

### Testing on a Physical Android Device
1. Build the release APK using the scripts above.
2. Locate the generated APK file at: `shuttle_flutter_app/build/app/outputs/flutter-apk/app-release.apk`.
3. Transfer the `.apk` file to your physical Android device (via USB cable, Google Drive, Telegram, etc.).
4. Open the file manager on your phone, tap the `.apk` file, and install it. 
   *(Note: You may need to enable **"Install from Unknown Sources"** or **"Allow installation from this source"** in your Android settings if prompted).*

---

## Web Deployment (Vercel)

The repository provides two ways to run and deploy on Vercel:

### Option 1: Instant Root Vercel Deployment (Recommended • Zero-Config)
The repository includes a ready-to-deploy root [`index.html`](file:///c:/Users/Rushi%20Raj%20Meher/shuttle%20app/vit-shuttle-system/index.html) and [`vercel.json`](file:///c:/Users/Rushi%20Raj%20Meher/shuttle%20app/vit-shuttle-system/vercel.json):
1. Import your GitHub repository directly into [Vercel](https://vercel.com/new).
2. Leave the Root Directory as `./` (default).
3. Click **Deploy**.
4. The web app goes live immediately with:
   - Built-in autonomous campus fleet simulator fallback (simulates all 3 shuttles driving around VIT campus seamlessly without requiring a running backend).
   - Real-time Supabase Auth with official Google OAuth and 1-click accounts.
   - Turn-by-turn walking directions to nearest campus stops.
   - Dual-tier digital QR boarding passes (₹20 General Bus vs Free Faculty Transit Pass).

### Option 2: Flutter Web Build on Vercel
1. Run [`.\build_web.ps1`](file:///c:/Users/Rushi%20Raj%20Meher/shuttle%20app/vit-shuttle-system/build_web.ps1) in PowerShell.
2. The production web bundle and [`vercel.json`](file:///c:/Users/Rushi%20Raj%20Meher/shuttle%20app/vit-shuttle-system/shuttle_flutter_app/vercel.json) will be generated in `shuttle_flutter_app/build/web`.
3. Drag and drop the `shuttle_flutter_app/build/web` folder to [vercel.com/new](https://vercel.com/new) or deploy via Vercel CLI (`vercel deploy --prod`).

---

## Backend Deployment (Node.js)
The `shuttle-backend` directory contains a containerized Node.js WebSocket and HTTP server ready for the cloud.

### Deploying to Render or Railway
1. **Push to GitHub**: Commit and push your entire `vit-shuttle-system` repository to GitHub.
2. **Create a New Web Service**: Log into Render or Railway and create a new "Web Service" linked to your GitHub repository.
3. **Configure the Service**:
   - **Root Directory**: `shuttle-backend`
   - **Environment/Build Type**: Docker (the platform will automatically detect and use the `Dockerfile` inside the directory).
4. **Set Environment Variables**: Add the following secrets in your deployment dashboard:
   - `SUPABASE_URL`: Your Supabase project URL.
   - `SUPABASE_ANON_KEY`: Your Supabase API key.
   - `REDIS_URL`: (Optional) URL for your Redis instance if utilized.
5. **Deploy**: Trigger the deployment. 
6. **Update the App**: Once your backend is live, update the WebSocket connections in `shuttle_flutter_app/lib/main.dart` from `ws://localhost:8080` to your new cloud URL (e.g., `wss://your-shuttle-backend.onrender.com`).
