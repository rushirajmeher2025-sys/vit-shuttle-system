# Deployment Guide

## 1. Backend (Node.js) Deployment - Render / Railway
Your backend can be seamlessly deployed to platforms like **Render** or **Railway**.
Since we created a `Dockerfile`, you can simply deploy via Docker mode.

**Environment Variables Required:**
- `SUPABASE_URL`: Your Supabase Project URL.
- `SUPABASE_ANON_KEY`: Your Supabase Project API Key.
- `REDIS_URL`: URL for your Redis instance (e.g. Upstash or Render's Redis addon).
- `PORT`: (Optional) Render sets this to 10000 automatically; map it as needed if not using Docker defaults.

## 2. Database (Supabase)
Your `public.stops` table should have the following columns at minimum:
- `id` (uuid or int)
- `name` (text)
- `lat` (double precision / numeric)
- `lng` (double precision / numeric)

Make sure you've enabled Row Level Security (RLS) properly if you expose the API, or grant read access.

## 3. Local Docker Compose
To run everything locally using `docker-compose`:
1. Ensure Docker Desktop is running.
2. In the `vit-shuttle-system` root folder, run:
   ```bash
   docker-compose up --build
   ```
This will start both the Node.js backend and a local Redis container on port 6379.
