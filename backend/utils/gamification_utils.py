from supabase_client import get_supabase
from datetime import datetime

supabase = get_supabase()

async def award_points_internal(user_id: str, points: int, action_type: str):
    """
    Internal function to award points and check for badges.
    """
    try:
        # 1. Get current stats
        stats_response = supabase.table("user_stats").select("*").eq("user_id", user_id).execute()
        
        current_points = 0
        current_stats = {}
        
        if stats_response.data:
            current_stats = stats_response.data[0]
            current_points = current_stats["total_points"]
        else:
            # Initialize if not exists
            init_data = {"user_id": user_id}
            supabase.table("user_stats").insert(init_data).execute()
            current_stats = init_data
            
        # 2. Update points
        new_points = current_points + points
        
        update_data = {"total_points": new_points}
        
        # Update specific counters based on action
        if action_type == 'check_in':
            current_checkins = current_stats.get("total_check_ins", 0)
            update_data["total_check_ins"] = current_checkins + 1
        elif action_type == 'route':
            current_routes = current_stats.get("total_routes_planned", 0)
            update_data["total_routes_planned"] = current_routes + 1
            
        supabase.table("user_stats").update(update_data).eq("user_id", user_id).execute()
        
        # Merge update_data into current_stats for badge checking
        current_stats.update(update_data)
        
        # 3. Check for badge unlocks
        await _check_badge_unlocks(user_id, current_stats)
        
        return new_points
    except Exception as e:
        print(f"Error awarding points: {e}")
        return None

async def _check_badge_unlocks(user_id: str, stats: dict):
    """Check if any badges should be unlocked based on new stats."""
    try:
        # Get all badges
        badges_response = supabase.table("badges").select("*").execute()
        badges = badges_response.data
        
        # Get earned badges
        earned_response = supabase.table("user_badges").select("badge_id").eq("user_id", user_id).execute()
        earned_ids = [b["badge_id"] for b in earned_response.data]
        
        for badge in badges:
            if badge["id"] in earned_ids:
                continue
                
            unlocked = False
            if badge["requirement_type"] == 'check_in' and "total_check_ins" in stats:
                if stats["total_check_ins"] >= badge["requirement_value"]:
                    unlocked = True
            elif badge["requirement_type"] == 'route' and "total_routes_planned" in stats:
                if stats["total_routes_planned"] >= badge["requirement_value"]:
                    unlocked = True
            
            if unlocked:
                supabase.table("user_badges").insert({
                    "user_id": user_id,
                    "badge_id": badge["id"]
                }).execute()
                print(f"Badge unlocked: {badge['name']} for user {user_id}")
    except Exception as e:
        print(f"Error checking badges: {e}")
