# VIT Shuttle Tracking System

## Mobile App (Flutter)
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
6. **Update the App**: Once your backend is live, don't forget to update the WebSocket connections in `shuttle_flutter_app/lib/main.dart` from `ws://localhost:8080` to your new cloud URL (e.g., `wss://your-shuttle-backend.onrender.com`).
