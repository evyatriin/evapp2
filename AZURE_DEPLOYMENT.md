# Azure Deployment Guide - FastAPI Backend

## Prerequisites
- Azure account ([sign up for free](https://azure.microsoft.com/free/))
- Azure CLI installed ([installation guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- Git repository (GitHub, Azure DevOps, or local)

## Option 1: Deploy via Azure Portal (Easiest)

### Step 1: Create App Service

1. **Login to Azure Portal**: Go to [portal.azure.com](https://portal.azure.com)

2. **Create Resource**:
   - Click "Create a resource"
   - Search for "Web App"
   - Click "Create"

3. **Configure Basic Settings**:
   - **Subscription**: Select your subscription
   - **Resource Group**: Create new (e.g., `ev-router-rg`)
   - **Name**: Choose unique name (e.g., `ev-router-backend`)
   - **Publish**: Code
   - **Runtime stack**: Python 3.11
   - **Operating System**: Linux
   - **Region**: Choose closest to you (e.g., East US, West Europe)

4. **Choose Pricing Tier**:
   - Click "Change size"
   - **Free (F1)**: Good for testing (1GB RAM, 60 min/day)
   - **Basic (B1)**: $13/month (1.75GB RAM, always on)
   - Select **F1** for free tier

5. **Review + Create**: Click "Create" and wait for deployment

### Step 2: Configure Deployment

1. **Go to Deployment Center**:
   - Navigate to your App Service
   - Click "Deployment Center" in left menu

2. **Choose Source**:
   - **GitHub**: Connect your GitHub account and select repository
   - **Local Git**: Use Azure's built-in Git
   - Select `backend` as the root directory

3. **Configure Build**:
   - Build provider: App Service build service
   - Click "Save"

### Step 3: Configure Environment Variables

1. **Go to Configuration**:
   - In your App Service, click "Configuration"
   - Click "Application settings"

2. **Add Settings**:
   Click "+ New application setting" for each:
   - `SUPABASE_URL`: Your Supabase URL
   - `SUPABASE_KEY`: Your Supabase key
   - `HERE_API_KEY`: Your HERE Maps key
   - `GOOGLE_MAPS_API_KEY`: Your Google Maps key
   - `SCM_DO_BUILD_DURING_DEPLOYMENT`: true
   - `WEBSITE_HTTPLOGGING_RETENTION_DAYS`: 7

3. **Save**: Click "Save" at the top

### Step 4: Configure Startup Command

1. **Go to Configuration** → **General settings**
2. **Startup Command**: Enter:
   ```
   gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000
   ```
3. **Save**

### Step 5: Deploy

If using GitHub:
- Push code to your repository
- Azure will automatically deploy

If using Local Git:
```bash
cd /Users/kk/apps/ev_router_app2/backend
git remote add azure <your-azure-git-url>
git push azure main
```

### Step 6: Verify Deployment

1. Go to your App Service overview
2. Click the URL (e.g., `https://ev-router-backend.azurewebsites.net`)
3. You should see: `{"message": "EV Router Backend is running"}`

---

## Option 2: Deploy via Azure CLI (Advanced)

### Step 1: Install and Login

```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Login
az login

# Set subscription (if you have multiple)
az account set --subscription "Your Subscription Name"
```

### Step 2: Create Resource Group

```bash
az group create --name ev-router-rg --location eastus
```

### Step 3: Create App Service Plan

```bash
# Free tier
az appservice plan create \
  --name ev-router-plan \
  --resource-group ev-router-rg \
  --sku F1 \
  --is-linux

# Or Basic tier ($13/month)
# az appservice plan create \
#   --name ev-router-plan \
#   --resource-group ev-router-rg \
#   --sku B1 \
#   --is-linux
```

### Step 4: Create Web App

```bash
az webapp create \
  --resource-group ev-router-rg \
  --plan ev-router-plan \
  --name ev-router-backend \
  --runtime "PYTHON:3.11"
```

### Step 5: Configure App Settings

```bash
az webapp config appsettings set \
  --resource-group ev-router-rg \
  --name ev-router-backend \
  --settings \
    SUPABASE_URL="your-supabase-url" \
    SUPABASE_KEY="your-supabase-key" \
    HERE_API_KEY="your-here-api-key" \
    GOOGLE_MAPS_API_KEY="your-google-maps-key" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true
```

### Step 6: Configure Startup Command

```bash
az webapp config set \
  --resource-group ev-router-rg \
  --name ev-router-backend \
  --startup-file "gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8000"
```

### Step 7: Deploy Code

```bash
cd /Users/kk/apps/ev_router_app2/backend

# Deploy from local directory
az webapp up \
  --resource-group ev-router-rg \
  --name ev-router-backend \
  --runtime "PYTHON:3.11"
```

---

## Option 3: Deploy via GitHub Actions (CI/CD)

Create `.github/workflows/azure-deploy.yml` in your repository:

```yaml
name: Deploy to Azure

on:
  push:
    branches: [ main ]
    paths:
      - 'backend/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: |
        cd backend
        pip install -r requirements.txt
    
    - name: Deploy to Azure Web App
      uses: azure/webapps-deploy@v2
      with:
        app-name: 'ev-router-backend'
        publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
        package: ./backend
```

---

## Update Flutter App

After deployment, update your Flutter app:

```dart
// lib/src/core/backend_service.dart
static String get baseUrl {
  // Production - Azure
  return 'https://ev-router-backend.azurewebsites.net';
  
  // Development - Local
  // if (Platform.isAndroid) {
  //   return 'http://10.0.2.2:8000';
  // } else {
  //   return 'http://127.0.0.1:8000';
  // }
}
```

---

## Azure Pricing Tiers

| Tier | Price | RAM | Features |
|------|-------|-----|----------|
| **F1 (Free)** | Free | 1GB | 60 min/day compute, sleeps when idle |
| **B1 (Basic)** | ~$13/month | 1.75GB | Always on, custom domains |
| **S1 (Standard)** | ~$70/month | 1.75GB | Auto-scaling, staging slots |

**Recommendation**: Start with **F1 (Free)** for testing, upgrade to **B1** for production.

---

## Troubleshooting

### App not starting?
1. Check logs: Azure Portal → App Service → Log stream
2. Or via CLI: `az webapp log tail --resource-group ev-router-rg --name ev-router-backend`

### Environment variables not working?
- Verify in Configuration → Application settings
- Restart app after changes

### Build failing?
- Check `requirements.txt` is in backend folder
- Ensure Python version matches (3.11)

---

## Cost Optimization Tips

1. **Use Free Tier**: F1 tier is free but has limitations
2. **Auto-shutdown**: Configure to stop when not in use
3. **Monitor Usage**: Set up cost alerts in Azure Portal
4. **Use Azure for Students**: $100 free credit if you're a student

---

## Next Steps

1. Deploy backend to Azure
2. Test API endpoints
3. Update Flutter app with Azure URL
4. Monitor logs and performance
5. Set up custom domain (optional)
