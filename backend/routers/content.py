import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from supabase_client import supabase

router = APIRouter()
logger = logging.getLogger(__name__)


class ResourceItem(BaseModel):
    id: str
    title: str
    subtitle: str
    url: str


class ResourceSection(BaseModel):
    id: str
    title: str
    icon: str
    tone: str
    description: Optional[str] = None
    sort_order: int = 0
    items: List[ResourceItem]


_FALLBACK_RESOURCES = [
    ResourceSection(
        id="before-you-charge",
        title="Before You Charge",
        icon="lightning",
        tone="amber",
        description="Quick prep before you pull into a station.",
        sort_order=1,
        items=[
            ResourceItem(
                id="connector-types",
                title="Understanding Connector Types",
                subtitle="CCS, CHAdeMO, Type 2 explained",
                url="https://evraahein.app/charging-connectors",
            ),
            ResourceItem(
                id="charging-etiquette",
                title="Charging Etiquette",
                subtitle="Best practices at public chargers",
                url="https://evraahein.app/charging-etiquette",
            ),
            ResourceItem(
                id="ac-dc",
                title="AC vs DC Charging",
                subtitle="Speed differences and when to use",
                url="https://evraahein.app/ac-vs-dc",
            ),
        ],
    ),
    ResourceSection(
        id="battery-care",
        title="Battery & Ownership",
        icon="car",
        tone="blue",
        description="Habits that keep range and battery health strong.",
        sort_order=2,
        items=[
            ResourceItem(
                id="battery-care-guide",
                title="Battery Care Guide",
                subtitle="Maximize battery life and health",
                url="https://evraahein.app/battery-care",
            ),
            ResourceItem(
                id="range-optimization",
                title="Range Optimization",
                subtitle="Get the most out of every charge",
                url="https://evraahein.app/range-tips",
            ),
            ResourceItem(
                id="seasonal-driving",
                title="Seasonal Driving Tips",
                subtitle="Winter and summer best practices",
                url="https://evraahein.app/seasonal-tips",
            ),
        ],
    ),
    ResourceSection(
        id="policies",
        title="Policies & Incentives",
        icon="bank",
        tone="green",
        description="Subsidies, policies, and tax benefits worth checking.",
        sort_order=3,
        items=[
            ResourceItem(
                id="fame-ii",
                title="FAME II Subsidy",
                subtitle="Central government EV incentives",
                url="https://fame2.heavyindustries.gov.in/",
            ),
            ResourceItem(
                id="state-policies",
                title="State EV Policies",
                subtitle="State-specific benefits and subsidies",
                url="https://evraahein.app/state-policies",
            ),
            ResourceItem(
                id="tax-benefits",
                title="Tax Benefits",
                subtitle="Income tax deductions for EV owners",
                url="https://evraahein.app/tax-benefits",
            ),
        ],
    ),
    ResourceSection(
        id="emergency-help",
        title="Emergency Help",
        icon="phone",
        tone="red",
        description="Brand hotlines you can call when a trip goes sideways.",
        sort_order=4,
        items=[
            ResourceItem(
                id="tata-support",
                title="Tata Motors EV Support",
                subtitle="Tap to call: 1800-209-7979",
                url="tel:18002097979",
            ),
            ResourceItem(
                id="mg-support",
                title="MG Motor Support",
                subtitle="Tap to call: 1800-102-4644",
                url="tel:18001024644",
            ),
            ResourceItem(
                id="hyundai-support",
                title="Hyundai EV Helpline",
                subtitle="Tap to call: 1800-11-4645",
                url="tel:1800114645",
            ),
        ],
    ),
]


def _fallback_resources() -> List[ResourceSection]:
    return _FALLBACK_RESOURCES


@router.get("/resources", response_model=List[ResourceSection])
async def get_resources(limit: int = Query(12, ge=1, le=50)):
    if not supabase:
        return _fallback_resources()

    try:
        sections_response = (
            supabase.table("app_resource_sections")
            .select("*")
            .order("sort_order")
            .limit(limit)
            .execute()
        )
        sections = sections_response.data or []
        if not sections:
            return _fallback_resources()

        section_ids = [section["id"] for section in sections]
        items_response = (
            supabase.table("app_resources")
            .select("*")
            .in_("section_id", section_ids)
            .order("sort_order")
            .execute()
        )
        items = items_response.data or []

        items_by_section = {}
        for item in items:
            items_by_section.setdefault(item["section_id"], []).append(
                ResourceItem(
                    id=item["id"],
                    title=item["title"],
                    subtitle=item.get("subtitle") or "",
                    url=item["url"],
                )
            )

        return [
            ResourceSection(
                id=section["id"],
                title=section["title"],
                icon=section.get("icon") or "book-open",
                tone=section.get("tone") or "primary",
                description=section.get("description"),
                sort_order=section.get("sort_order") or 0,
                items=items_by_section.get(section["id"], []),
            )
            for section in sections
        ]
    except Exception as exc:
        logger.warning("Falling back to seeded app resources: %s", exc)
        return _fallback_resources()
