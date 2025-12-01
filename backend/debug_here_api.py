import httpx
import asyncio

async def debug_here_api():
    url = "https://router.hereapi.com/v8/routes"
    params = {
        "apiKey": "iXm1_kM1ODV-2TsY14jcvQ4gDF8nQ9Ond7hD4D1LFO0",
        "transportMode": "car",
        "origin": "17.406498,78.47724389999999",
        "destination": "17.6704896,80.89377789999999",
        "return": "polyline,summary,actions,instructions",
        "ev[makeReachable]": "true",
        "ev[freeFlowSpeedTable]": "0,200,140,300",
        "ev[trafficSpeedTable]": "0,200,140,300",
        "ev[auxiliaryConsumption]": "0.1",
        "ev[initialCharge]": "10",
        "ev[maxCharge]": "100",
        "ev[connectorTypes]": "iec62196Type2Combo",
        "ev[chargingCurve]": "0,30,80,30,100,5",
        "ev[maxChargeAfterChargingStation]": "80",
        "ev[minChargeAtDestination]": "10",
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(url, params=params)
            print(f"Status Code: {response.status_code}")
            data = response.json()
            
            if "routes" in data:
                for i, route in enumerate(data["routes"]):
                    print(f"Route {i+1} Summary:")
                    for section in route["sections"]:
                        print(f" - Section Length: {section['summary']['length']} m")
                        print(f" - Section Duration: {section['summary']['duration']} s")
                        if "consumption" in section["summary"]:
                            print(f" - Consumption: {section['summary']['consumption']} kWh")
                        
                        if "actions" in section:
                            for action in section["actions"]:
                                if action['action'] == 'chargingStation':
                                    print(f" *** CHARGING STATION FOUND ***")
                                    print(f" - Duration: {action['duration']} s")
            else:
                print("No routes found in response.")
                print(data)

        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(debug_here_api())
