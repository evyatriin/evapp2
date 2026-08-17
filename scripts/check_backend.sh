#!/usr/bin/env bash
#
# EVraahein backend health check.
#
# Hits every important API endpoint and prints a pass/fail report.
# Public endpoints are expected to return 2xx; auth-protected endpoints are
# expected to return 401 UNLESS you supply a bearer token, in which case they
# are expected to return 2xx.
#
# Usage:
#   scripts/check_backend.sh                        # uses the live prod URL below
#   BASE_URL=https://my-backend.run.app scripts/check_backend.sh
#   TOKEN="eyJ..." scripts/check_backend.sh         # also exercises protected routes
#
# Exit code is non-zero if any endpoint fails its expectation.

set -uo pipefail

# Live production service (verified working). Override with BASE_URL=...
BASE_URL="${BASE_URL:-https://evraahein-backend-187759131948.asia-south1.run.app}"
TOKEN="${TOKEN:-}"
TIMEOUT="${TIMEOUT:-90}"
CURL="$(command -v curl || echo /usr/bin/curl)"

# Colors (disabled if not a tty)
if [[ -t 1 ]]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else G=""; R=""; Y=""; B=""; N=""; fi

pass=0; fail=0; auth_hdr=()
[[ -n "$TOKEN" ]] && auth_hdr=(-H "Authorization: Bearer $TOKEN")

echo "${B}EVraahein backend health check${N}"
echo "Target : $BASE_URL"
echo "Token  : $([[ -n "$TOKEN" ]] && echo "provided (protected routes expect 2xx)" || echo "none (protected routes expect 401)")"
echo "-------------------------------------------------------------------------"
printf "%-6s %-38s %-10s %s\n" "METHOD" "PATH" "STATUS" "RESULT"
echo "-------------------------------------------------------------------------"

# check METHOD PATH EXPECT_PUBLIC [BODY]
#   EXPECT_PUBLIC: "public" (want 2xx), "auth" (want 401, or 2xx w/ token),
#                  "redirect" (want 3xx), or an explicit code like "200"
check() {
  local method="$1" path="$2" kind="$3" body="${4:-}"
  local url="$BASE_URL$path"
  local args=(-s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -X "$method" ${auth_hdr[@]+"${auth_hdr[@]}"})
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")
  local code; code="$("$CURL" "${args[@]}" "$url" 2>/dev/null)"

  local ok=0
  case "$kind" in
    public)   [[ "$code" =~ ^2 ]] && ok=1 ;;
    redirect) [[ "$code" =~ ^3 ]] && ok=1 ;;
    auth)
      if [[ -n "$TOKEN" ]]; then [[ "$code" =~ ^2 ]] && ok=1
      else [[ "$code" == "401" ]] && ok=1; fi ;;
    *) [[ "$code" == "$kind" ]] && ok=1 ;;
  esac

  local tag
  if [[ $ok -eq 1 ]]; then
    if [[ "$kind" == "auth" && -z "$TOKEN" ]]; then tag="${Y}PROTECTED${N}"; else tag="${G}PASS${N}"; fi
    pass=$((pass+1))
  else
    tag="${R}FAIL (wanted $kind)${N}"; fail=$((fail+1))
  fi
  printf "%-6s %-38s %-10s %b\n" "$method" "${path:0:38}" "$code" "$tag"
}

# ---- Process/static endpoints (want 2xx; do NOT touch the database) ----
check GET  "/health"                                       public
check GET  "/"                                             public
check GET  "/docs"                                         public
check GET  "/openapi.json"                                 public
check GET  "/api/vehicles/templates"                       public
check GET  "/api/content/resources"                        public
check GET  "/api/news/"                                    public

# ---- DATABASE HEALTH (want 2xx). These hit Supabase; if the DB is down they
#      surface it: /ready -> 503, gamification -> 500. Treat any FAIL here as
#      "database/Supabase connection broken", not an app-code bug. ----
check GET  "/ready"                                        public
check GET  "/api/gamification/leaderboard"                 public
check GET  "/api/gamification/badges"                      public
check GET  "/api/chargers/checkins/public"                 public

# ---- Auth-protected (want 401, or 2xx with TOKEN) ----
check GET  "/api/auth/user"                                auth
check GET  "/api/places/autocomplete?input=Hyderabad"      auth
check GET  "/api/chargers/aggregate?lat=17.45&lng=78.42&radius=10" auth
check POST "/api/route/"                                   auth \
  '{"origin":{"latitude":17.385,"longitude":78.486},"destination":{"latitude":12.972,"longitude":77.594},"current_soc":80,"target_soc":20,"soh":100}'
check GET  "/api/routes/"                                  auth

echo "-------------------------------------------------------------------------"
echo "${B}Summary:${N} ${G}${pass} ok${N}, ${R}${fail} failed${N}"
[[ $fail -eq 0 ]] && echo "${G}Backend looks healthy.${N}" || echo "${R}Some endpoints failed — investigate above.${N}"
exit $(( fail > 0 ? 1 : 0 ))
