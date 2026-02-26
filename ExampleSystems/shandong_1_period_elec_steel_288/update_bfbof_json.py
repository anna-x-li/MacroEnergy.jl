import json

# Province to region mapping
province_mapping = {
    "Beijing": "Region1Beijing",
    "Tianjin": "Region2Tianjin",
    "Hebei": "Region3Hebei",
    "Shanxi": "Region4Shanxi",
    "InnerMongolia": "Region5InnerMongolia",
    "Liaoning": "Region6Liaoning",
    "Jilin": "Region7Jilin",
    "Heilongjiang": "Region8Heilongjiang",
    "Shanghai": "Region9Shanghai",
    "Jiangsu": "Region10Jiangsu",
    "Zhejiang": "Region11Zhejiang",
    "Anhui": "Region12Anhui",
    "Fujian": "Region13Fujian",
    "Jiangxi": "Region14Jiangxi",
    "Shandong": "Region15Shandong",
    "Henan": "Region16Henan",
    "Hubei": "Region17Hubei",
    "Hunan": "Region18Hunan",
    "Guangdong": "Region19Guangdong",
    "Guangxi": "Region20Guangxi",
    "Hainan": "Region21Hainan",
    "Chongqing": "Region22Chongqing",
    "Sichuan": "Region23Sichuan",
    "Guizhou": "Region24Guizhou",
    "Yunnan": "Region25Yunnan",
    "Tibet": "Region26Tibet",
    "Shaanxi": "Region27Shaanxi",
    "Gansu": "Region28Gansu",
    "Qinghai": "Region29Qinghai",
    "Ningxia": "Region30Ningxia",
    "Xinjiang": "Region31Xinjiang"
}

# BOF Operating Steel Capacity (tons per hour)
bof_capacity = {
    "Anhui": 3705,
    "Chongqing": 1301,
    "Fujian": 2883,
    "Gansu": 1142,
    "Guangdong": 3305,
    "Guangxi": 4325,
    "Guizhou": 400,
    "Hebei": 23967,
    "Heilongjiang": 1045,
    "Henan": 3302,
    "Hubei": 3251,
    "Hunan": 2078,
    "InnerMongolia": 3135,
    "Jiangsu": 11727,
    "Jiangxi": 2300,
    "Jilin": 1506,
    "Liaoning": 7668,
    "Ningxia": 605,
    "Qinghai": 103,
    "Shandong": 6370,
    "Shaanxi": 1381,
    "Shanghai": 1849,
    "Shanxi": 6700,
    "Sichuan": 2072,
    "Tianjin": 1558,
    "Xinjiang": 1667,
    "Yunnan": 1478,
    "Zhejiang": 1027
}

def create_instance_template(province, region_id, capacity):
    """Create an instance template for a province"""
    instance = {
        "id": f"bfbof_{region_id}",
        "edges": {
            "crudesteel_edge": {
                "end_vertex": f"crudesteel_{region_id}",
                "existing_capacity": capacity * 1e3  # Convert to match scale (tons/hour to base unit)
            },
            "metcoal_edge": {
                "start_vertex": f"coal_{region_id}"
            },
            "thermalcoal_edge": {
                "start_vertex": f"coal_{region_id}"
            },
            "elec_edge": {
                "start_vertex": f"elec_{region_id}"
            },
            "natgas_edge": {
                "start_vertex": f"natgas_{region_id}"
            },
            "ironore_edge": {
                "start_vertex": "ironore_source"
            },
            "steelscrap_edge": {
                "start_vertex": f"steelscrap_source_{region_id}"
            }
        },
        "retrofit_options": [
            {
                "template_id": f"bfbofccs_{region_id}",
                "id": f"bfbofccs_retrofit_{region_id}",
                "edges": {
                    "crudesteel_edge": {
                        "investment_cost": 3278693,
                        "is_retrofit": True,
                        "retrofit_efficiency": 1,
                        "can_expand": True
                    }
                }
            }
        ]
    }
    return instance

def load_json(filepath):
    """Load the JSON file"""
    with open(filepath, 'r') as f:
        return json.load(f)

def save_json(data, filepath):
    """Save the JSON file"""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=4)

def add_province_instance(data, province, region_id, capacity):
    """Add a single province instance to the JSON"""
    instance = create_instance_template(province, region_id, capacity)
    data["BfBof"][0]["instance_data"].append(instance)
    print(f"✓ Added instance for {province} ({region_id}) with capacity {capacity} tons/hour")

def update_all_provinces(filepath):
    """Update the JSON file with all provinces"""
    data = load_json(filepath)
    
    # Track which provinces were added
    added_provinces = []
    
    for province, region_id in sorted(province_mapping.items()):
        if province in bof_capacity:
            capacity = bof_capacity[province]
            add_province_instance(data, province, region_id, capacity)
            added_provinces.append(province)
        else:
            print(f"⚠ Skipped {province} - no capacity data available")
    
    # Save the updated JSON
    save_json(data, filepath)
    
    print(f"\n✓ Successfully added {len(added_provinces)} provinces")
    print(f"File saved to: {filepath}")
    
    return len(added_provinces)

def verify_instances(filepath):
    """Verify the instances in the JSON file"""
    data = load_json(filepath)
    instances = data["BfBof"][0]["instance_data"]
    
    print(f"\nTotal instances: {len(instances)}\n")
    print("Instance Summary:")
    print("-" * 80)
    for instance in instances:
        instance_id = instance["id"]
        capacity = instance["edges"]["crudesteel_edge"].get("existing_capacity", "N/A")
        print(f"  {instance_id}: capacity = {capacity}")

if __name__ == "__main__":
    filepath = "/Users/al3792/Documents_Local/MacroEnergy.jl/ExampleSystems/shandong_1_period_elec_steel_288/assets/assets_1/bfbof.json"
    
    # Uncomment the function you want to run:
    
    # To add all provinces:
    # update_all_provinces(filepath)
    
    # To verify current instances:
    # verify_instances(filepath)
    
    print("Script ready. Uncomment the desired function in the __main__ section to run.")
