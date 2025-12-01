# Backend Deployment Guide

## Railway Deployment (Recommended - Free Tier Available)

### Prerequisites
- GitHub account
- Railway account (sign up at [railway.app](https://railway.app))
- Supabase project with schema applied

### Step 1: Prepare Your Repository

1. **Initialize Git** (if not already done):
   ```bash
   cd /Users/kk/apps/ev_router_app2
   git init
   git add .
   git commit -m "Initial commit"
   ```

2. **Push to GitHub**:
   - Create a new repository on GitHub
   - Follow GitHub's instructions to push your code

### Step 2: Deploy to Railway

1. **Go to Railway**: Visit [railway.app](https://railway.app) and sign in with GitHub

2. **Create New Project**:
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Choose your `ev_router_app2` repository
   - Railway will auto-detect it's a Python project

3. **Configure Root Directory**:
   - In project settings, set **Root Directory** to `backend`
   - This tells Railway where your FastAPI app is located

4. **Add Environment Variables**:
   - Go to your project's "Variables" tab
   - Add the following variables:
     - `SUPABASE_URL`: Your Supabase project URL
     - `SUPABASE_KEY`: Your Supabase anon/service key
     - `HERE_API_KEY`: Your HERE Maps API key (if using routing)
     - `PORT`: 8000 (Railway will override this automatically)

5. **Deploy**:
   - Railway will automatically deploy your app
   - You'll get a public URL like `https://your-app.railway.app`

### Step 3: Update Flutter App

Update the `baseUrl` in your Flutter app to use the Railway URL:

```dart
// lib/src/core/backend_service.dart
static String get baseUrl {
  // For production, use Railway URL
  return 'https://your-app.railway.app';
  
  // For local development
  // if (Platform.isAndroid) {
  //   return 'http://10.0.2.2:8000';
  // } else {
  //   return 'http://127.0.0.1:8000';
  // }
}
```

### Railway Free Tier Limits
- **$5 free credit per month**
- **500 hours of usage** (enough for small projects)
- Automatic sleep after inactivity (wakes up on request)

---

## Alternative: Render (Also Free Tier)

### Steps:
1. Go to [render.com](https://render.com)
2. Create a new "Web Service"
3. Connect your GitHub repository
4. Configure:
   - **Root Directory**: `backend`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
5. Add environment variables (same as Railway)

### Render Free Tier Limits
- Free tier available
- Spins down after 15 minutes of inactivity
- Slower cold starts than Railway

---

## Alternative: Fly.io (Free Tier)

### Steps:
1. Install Fly CLI: `brew install flyctl` (macOS)
2. Sign up: `fly auth signup`
3. Navigate to backend: `cd backend`
4. Launch: `fly launch`
5. Deploy: `fly deploy`

### Fly.io Free Tier
- 3 shared-cpu VMs with 256MB RAM each
- 3GB persistent volume storage
- 160GB outbound data transfer

---

## Cost Comparison

| Platform | Free Tier | Best For |
|----------|-----------|----------|
| **Railway** | $5/month credit | Easy setup, good performance |
| **Render** | Yes (with sleep) | Simple projects, low traffic |
| **Fly.io** | 3 VMs free | Always-on, global deployment |

**Recommendation**: Start with **Railway** for the best balance of ease and performance.
