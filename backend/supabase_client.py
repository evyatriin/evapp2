from supabase import create_client, Client
from config import settings

def get_supabase() -> Client:
    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        print("Warning: Supabase credentials not found.")
        # Return a dummy or handle error appropriately in production
        return None 
    try:
        return create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
    except Exception as e:
        print(f"Warning: Failed to initialize Supabase client: {e}")
        return None

supabase = get_supabase()
