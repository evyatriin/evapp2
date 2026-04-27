import json
import re
from pathlib import Path
from urllib import error, parse, request


def _read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def _seed_rows(path: Path) -> list[dict[str, object]]:
    pattern = re.compile(
        r"\('([^']*)', '([^']*)', '([^']*)', '([^']*)', ([0-9.]+), '([^']*)', array\[(.*?)\]::text\[], ([0-9]+)\)"
    )
    rows: list[dict[str, object]] = []
    for match in pattern.finditer(path.read_text()):
        networks = [
            item.strip().strip("'")
            for item in match.group(7).split(",")
            if item.strip()
        ]
        rows.append(
            {
                "seed_id": match.group(1),
                "brand": match.group(2),
                "model": match.group(3),
                "variant": match.group(4),
                "range_km": float(match.group(5)),
                "image_url": match.group(6) or None,
                "preferred_networks": networks,
                "sort_order": int(match.group(8)),
            }
        )
    if not rows:
        raise RuntimeError("No seed rows found in migration file.")
    return rows


def _template_key(brand: str, model: str, variant: str) -> str:
    return f"{brand}|{model}|{variant}".lower()


def _connectors_for(brand: str, model: str) -> list[str]:
    key = f"{brand}|{model}".lower()
    if key == "mg|comet ev":
        return ["Type 2"]
    if key == "nissan|leaf":
        return ["CHAdeMO"]
    return ["CCS2"]


def _image_url_or_placeholder(image_url: object, brand: str, model: str) -> str:
    if isinstance(image_url, str) and image_url.strip():
        return image_url
    label = parse.quote(f"{brand} {model}")
    return f"https://placehold.co/1200x800/png?text={label}"


_TEMPLATE_SPECS: dict[str, dict[str, object]] = {
    "tata|nexon ev|creative mr": {"battery_capacity_kwh": 30.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|nexon ev|creative lr": {"battery_capacity_kwh": 40.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|nexon ev|fearless mr": {"battery_capacity_kwh": 30.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|nexon ev|fearless lr": {"battery_capacity_kwh": 40.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|punch ev|smart mr": {"battery_capacity_kwh": 25.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|punch ev|empowered lr": {"battery_capacity_kwh": 35.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|tiago ev|xe mr": {"battery_capacity_kwh": 19.2, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|tiago ev|xz+ lr": {"battery_capacity_kwh": 24.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|tigor ev|xe": {"battery_capacity_kwh": 26.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|tigor ev|xz+": {"battery_capacity_kwh": 26.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|curvv ev|creative": {"battery_capacity_kwh": 45.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|curvv ev|accomplished lr": {"battery_capacity_kwh": 55.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|harrier ev|adventure": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|harrier ev|empowered awd": {"battery_capacity_kwh": 65.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|sierra ev|smart": {"battery_capacity_kwh": 50.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|sierra ev|adventure": {"battery_capacity_kwh": 55.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tata|sierra ev|accomplished awd": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "mg|comet ev|executive": {"battery_capacity_kwh": 17.3, "max_charging_power_kw": 7, "connectors": ["Type 2"]},
    "mg|comet ev|excite": {"battery_capacity_kwh": 17.3, "max_charging_power_kw": 7, "connectors": ["Type 2"]},
    "mg|comet ev|exclusive": {"battery_capacity_kwh": 17.3, "max_charging_power_kw": 7, "connectors": ["Type 2"]},
    "mg|zs ev|executive": {"battery_capacity_kwh": 50.3, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mg|zs ev|exclusive": {"battery_capacity_kwh": 50.3, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mg|cyberster|rwd": {"battery_capacity_kwh": 77.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mg|cyberster|awd performance": {"battery_capacity_kwh": 77.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mahindra|xuv400|ec": {"battery_capacity_kwh": 34.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mahindra|xuv400|el": {"battery_capacity_kwh": 39.4, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mahindra|be 6|pack one": {"battery_capacity_kwh": 59.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mahindra|be 6|pack three": {"battery_capacity_kwh": 79.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "mahindra|xev 9e|pack one": {"battery_capacity_kwh": 59.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mahindra|xev 9e|pack three awd": {"battery_capacity_kwh": 79.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "hyundai|ioniq 5|long range": {"battery_capacity_kwh": 72.6, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "hyundai|kona electric|premium": {"battery_capacity_kwh": 39.2, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "hyundai|creta ev|base": {"battery_capacity_kwh": 45.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "byd|atto 3|dynamic": {"battery_capacity_kwh": 60.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "byd|atto 3|superior": {"battery_capacity_kwh": 60.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "byd|sealion 7|premium": {"battery_capacity_kwh": 82.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "byd|sealion 7|performance awd": {"battery_capacity_kwh": 82.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "citroen|ec3|feel": {"battery_capacity_kwh": 29.2, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "bmw|i4|edrive35": {"battery_capacity_kwh": 70.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "bmw|ix|xdrive50": {"battery_capacity_kwh": 105.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "mercedes-benz|eqa|250+": {"battery_capacity_kwh": 70.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mercedes-benz|eqb|300 4matic": {"battery_capacity_kwh": 66.5, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mercedes-benz|eqs|580": {"battery_capacity_kwh": 107.8, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "audi|q8 e-tron|55 quattro": {"battery_capacity_kwh": 114.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "audi|e-tron gt|quattro": {"battery_capacity_kwh": 93.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "audi|e-tron gt|rs": {"battery_capacity_kwh": 93.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "volvo|xc40 recharge|ultimate awd": {"battery_capacity_kwh": 78.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "volvo|c40 recharge|ultimate awd": {"battery_capacity_kwh": 78.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "kia|ev6|gt line awd": {"battery_capacity_kwh": 77.4, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "kia|ev9|gt line awd": {"battery_capacity_kwh": 99.8, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "vinfast|vf 6|eco": {"battery_capacity_kwh": 59.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf 7|plus awd": {"battery_capacity_kwh": 75.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf 8|eco": {"battery_capacity_kwh": 87.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf 8|plus awd": {"battery_capacity_kwh": 87.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf 9|plus awd": {"battery_capacity_kwh": 123.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "vinfast|vf mpv 7|eco": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf mpv 7|plus": {"battery_capacity_kwh": 70.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "vinfast|vf3|base": {"battery_capacity_kwh": 18.6, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "mini|cooper se|3-door": {"battery_capacity_kwh": 32.6, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "porsche|taycan|rwd": {"battery_capacity_kwh": 79.2, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "porsche|taycan|turbo s": {"battery_capacity_kwh": 93.4, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "rolls-royce|spectre|coupe": {"battery_capacity_kwh": 102.0, "max_charging_power_kw": 150, "connectors": ["CCS2"]},
    "lexus|ux300e|luxury": {"battery_capacity_kwh": 54.3, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "tesla|model 3|rwd": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 170, "connectors": ["CCS2"]},
    "tesla|model 3|performance": {"battery_capacity_kwh": 75.0, "max_charging_power_kw": 170, "connectors": ["CCS2"]},
    "tesla|model y|long range awd": {"battery_capacity_kwh": 84.0, "max_charging_power_kw": 170, "connectors": ["CCS2"]},
    "nissan|leaf|e+": {"battery_capacity_kwh": 62.0, "max_charging_power_kw": 50, "connectors": ["CHAdeMO"]},
    "jaguar|i-pace|hse": {"battery_capacity_kwh": 90.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "maruti suzuki|e vitara|delta 49kwh": {"battery_capacity_kwh": 49.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "maruti suzuki|e vitara|zeta 60kwh": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "maruti suzuki|e vitara|alpha 60kwh": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
    "toyota|urban cruiser ev|standard": {"battery_capacity_kwh": 60.0, "max_charging_power_kw": 50, "connectors": ["CCS2"]},
}


def _api_request(
    *,
    method: str,
    url: str,
    service_role: str,
    payload: dict[str, object] | None = None,
) -> str:
    data = None if payload is None else json.dumps(payload).encode()
    req = request.Request(
        url,
        data=data,
        headers={
            "apikey": service_role,
            "Authorization": f"Bearer {service_role}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        method=method,
    )
    with request.urlopen(req, timeout=60) as response:
        return response.read().decode()


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    env_values = _read_env(repo_root / "backend" / ".env")
    supabase_url = env_values["SUPABASE_URL"]
    service_role = env_values["SUPABASE_SERVICE_ROLE_KEY"]

    seed_rows = _seed_rows(repo_root / "backend" / "migrations" / "014_expand_vehicle_templates.sql")

    existing_raw = _api_request(
        method="GET",
        url=f"{supabase_url}/rest/v1/vehicle_templates?select=id,brand,model,variant",
        service_role=service_role,
    )
    existing_rows = json.loads(existing_raw)
    existing_by_key = {
        _template_key(row["brand"], row["model"], row["variant"]): row["id"]
        for row in existing_rows
    }

    created = 0
    updated = 0
    for row in seed_rows:
        payload = {
            "brand": row["brand"],
            "model": row["model"],
            "variant": row["variant"],
            "real_world_range_km": int(round(float(row["range_km"]))),
            "range_wltp_km": int(round(float(row["range_km"]))),
            "image_url": _image_url_or_placeholder(
                row["image_url"],
                str(row["brand"]),
                str(row["model"]),
            ),
        }
        key = _template_key(
            str(row["brand"]),
            str(row["model"]),
            str(row["variant"]),
        )
        specs = _TEMPLATE_SPECS.get(key)
        if specs is None:
            raise RuntimeError(f"Missing battery/connector spec for {key}")
        payload["battery_capacity_kwh"] = specs["battery_capacity_kwh"]
        payload["max_charging_power_kw"] = specs["max_charging_power_kw"]
        payload["connectors"] = specs.get(
            "connectors",
            _connectors_for(str(row["brand"]), str(row["model"])),
        )
        payload["efficiency_wh_km"] = int(
            round(
                float(specs["battery_capacity_kwh"]) * 1000.0 / float(row["range_km"])
            )
        )

        existing_id = existing_by_key.get(key)
        if existing_id:
            encoded_id = parse.quote(str(existing_id), safe="")
            _api_request(
                method="PATCH",
                url=f"{supabase_url}/rest/v1/vehicle_templates?id=eq.{encoded_id}",
                service_role=service_role,
                payload=payload,
            )
            updated += 1
            continue

        _api_request(
            method="POST",
            url=f"{supabase_url}/rest/v1/vehicle_templates",
            service_role=service_role,
            payload=payload,
        )
        created += 1

    print(f"Updated {updated} existing templates.")
    print(f"Created {created} new templates.")
    print(f"Processed {len(seed_rows)} total templates.")


if __name__ == "__main__":
    try:
        main()
    except error.HTTPError as exc:
        body = exc.read().decode()
        print(f"HTTP {exc.code}")
        print(body)
        raise
