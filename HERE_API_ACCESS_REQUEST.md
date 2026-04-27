## HERE API Access Request Draft

Company: EVraahein  
Product: EVraahein mobile app and backend  
Primary market: India  
Contact: hey@evraahein.app  
Website: https://www.evraahein.app/

### Requested HERE capabilities

We are requesting production access for HERE APIs used in our EV driver application:

1. HERE Routing API v8  
Use case: EV-aware route planning with charging stops, consumption-aware routing, and route recalculation.

2. HERE Search / Browse API with EV enrichment  
Use case: Discover nearby charging stations, retrieve charger metadata, connector information, provider data, and EV-related attributes for map and trip-planning workflows.

### Product use case

EVraahein helps electric-vehicle drivers in India:

- plan long-distance routes with realistic charging stops
- discover nearby charging stations
- compare charging options across multiple sources
- contribute charger check-ins and community updates

The app merges charger information from:

- EVraahein canonical/Supabase data
- Google Places
- HERE EV-enriched search results

When HERE returns a charger that is not already present in our canonical dataset, we normalize and write that record into our Supabase-backed canonical charger store for future reuse and deduplication.

### Geographic scope

- India-first launch
- major metro, highway, and intercity EV corridors
- future expansion to additional markets after initial production rollout

### Expected request pattern

- mobile clients call our backend, not HERE directly
- HERE is accessed server-to-server from our backend
- requests are triggered by route planning and nearby charger discovery
- expected early-stage production traffic is moderate and bursty around commute and travel windows

### Dependency-reduction and caching policy

To reduce repeated dependency on HERE for similar locations, EVraahein uses the following backend strategy:

1. Charger records from HERE are normalized and stored in our canonical data layer.
2. Raw HERE source records are also stored with source identity and last-seen timestamps.
3. When a user requests chargers for a nearby or similar location, the backend first reuses fresh HERE source records already stored in Supabase.
4. The backend only calls the live HERE API when nearby cached HERE source records are missing or stale.
5. Merged responses are deduplicated across EVraahein, Google, and HERE before being returned to the app.

This lowers repeated calls for overlapping map areas while still allowing fresh retrieval when coverage is incomplete or outdated.

### Compliance and attribution

- HERE data is consumed by our backend and used for EV route planning and charger discovery
- we will follow HERE attribution, caching, and usage requirements applicable to the licensed products
- we do not expose raw HERE credentials in the mobile client

### Support request summary

We would like confirmation that our intended use of:

- EV route planning through Routing API v8
- nearby charger discovery through HERE Search / Browse with EV enrichment
- backend-side caching and canonical deduplication for nearby repeated lookups

is supported under the appropriate HERE production plan, and we would appreciate any guidance on recommended limits, attribution expectations, and best practices for EV charging-station caching in an India-focused mobile application.
