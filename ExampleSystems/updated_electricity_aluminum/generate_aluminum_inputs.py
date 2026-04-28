#!/usr/bin/env python
"""
generate_aluminum_inputs.py

Generates/updates aluminum-related inputs for Ver12 based on the single-node aluminum
case and Ver12 data layout. Updates:
- system/commodities.json
- system/nodes_1.json through system/nodes_7.json
- assets/assets_1 through assets/assets_7:
  aluminumsmelting.json, aluminumrefining.json, aluminaplant.json

Assumptions/conventions:
- Total aluminum demand uses primary_aluminum_demand["mid"][year] (units: 10kt/year)
- Year to period mapping:
    period 1 → 2025
    period 2 → 2030
    period 3 → 2035
    period 4 → 2040
    period 5 → 2045
    period 6 → 2050
    period 7 → 2055
- Year 2025 total demand is fixed at 4000 (10kt/year), not read from JSON
- Demand conversion: 10kt/year → total tons over 288 hours
    demand_288h = value_10kt_per_year * 10_000 * 288 / 8760
- Provinces with very small capacity are still included in assets, but existing_capacity is set to 0
"""

import json
import csv
import os
import argparse
from copy import deepcopy


BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Province-to-node name mapping (aligned with PROVINCE_MAPPING.md)
PROVINCE_TO_REGION = {
    "Beijing":       ("Region1Beijing",       1),
    "Tianjin":       ("Region2Tianjin",       2),
    "Anhui":         ("Region12Anhui",        12),
    "Shanghai":      ("Region9Shanghai",      9),
    "Chongqing":     ("Region22Chongqing",    22),
    "Fujian":        ("Region13Fujian",       13),
    "Gansu":         ("Region28Gansu",        28),
    "Guangdong":     ("Region19Guangdong",    19),
    "Guangxi":       ("Region20Guangxi",      20),
    "Guizhou":       ("Region24Guizhou",      24),
    "Hainan":        ("Region21Hainan",       21),
    "Hebei":         ("Region3Hebei",         3),
    "Heilongjiang":  ("Region8Heilongjiang",  8),
    "Henan":         ("Region16Henan",        16),
    "Hubei":         ("Region17Hubei",        17),
    "Hunan":         ("Region18Hunan",        18),
    "InnerMongolia": ("Region5Innermongolia", 5),  # Note case difference in node system
    "Jiangsu":       ("Region10Jiangsu",      10),
    "Jiangxi":       ("Region14Jiangxi",      14),
    "Jilin":         ("Region7Jilin",         7),
    "Liaoning":      ("Region6Liaoning",      6),
    "Ningxia":       ("Region30Ningxia",      30),
    "Qinghai":       ("Region29Qinghai",      29),
    "Shaanxi":       ("Region27Shaanxi",      27),
    "Shandong":      ("Region15Shandong",     15),
    "Shanxi":        ("Region4Shanxi",        4),
    "Sichuan":       ("Region23Sichuan",      23),
    "Tibet":         ("Region26Tibet",        26),
    "Xinjiang":      ("Region31Xinjiang",     31),
    "Yunnan":        ("Region25Yunnan",       25),
    "Zhejiang":      ("Region11Zhejiang",     11),
}


def convert_10kt_per_year_to_288h_tons(x_10kt_year: float) -> float:
    return x_10kt_year * 10_000.0 * 288.0 / 8760.0


def convert_mton_per_year_to_288h_tons(x_mton_year: float) -> float:
    return x_mton_year * 1_000_000.0 * 288.0 / 8760.0


def load_total_demand_per_period(demand_2025_10kt: float = 4000.0) -> dict:
    """Load primary_aluminum_demand['mid'] and convert to 288h total demand (tons) per period."""
    demand_json_path = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_demand_all_scenarios.json",
    )
    with open(demand_json_path, "r", encoding="utf-8") as f:
        demand_data = json.load(f)

    prim_d = demand_data["primary_aluminum_demand"]["mid"]

    period_year_map = {
        1: "2025",
        2: "2030",
        3: "2035",
        4: "2040",
        5: "2045",
        6: "2050",
        7: "2055",
    }

    total = {}
    for p, ystr in period_year_map.items():
        if ystr == "2025":
            v_10kt = float(demand_2025_10kt)
        else:
            if ystr not in prim_d:
                raise KeyError(f"Year {ystr} missing in primary_aluminum_demand['mid']")
            v_10kt = float(prim_d[ystr])
        total[p] = convert_10kt_per_year_to_288h_tons(v_10kt)
    return total


def load_province_capacity() -> dict:
    """Load existing_capacity (t/h) per province; values below threshold are set to 0.

    Only provinces present in the CSV are returned. Use merge_province_info_with_capacity()
    to ensure all provinces in PROVINCE_TO_REGION are represented.
    """
    cap_csv_path = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_capacity_by_province.csv",
    )
    capacity_eps = 1e-4  # t/h threshold
    info = {}
    with open(cap_csv_path, "r", encoding="utf-8-sig") as f:  # utf-8-sig 自动处理BOM
        reader = csv.DictReader(f)
        # Handle possible BOM or alternate column names
        fieldnames = [fn for fn in (reader.fieldnames or [])]
        def _match(colname: str, target: str) -> bool:
            return colname.strip().lstrip("\ufeff").lower() == target.lower()

        prov_key = None
        cap_key = None
        for fn in fieldnames:
            fn_clean = fn.strip().lstrip("\ufeff")
            if prov_key is None and _match(fn_clean, "Province"):
                prov_key = fn
            # Support multiple possible column names: Capacity_ton_per_h, Capacity_tons_per_hour, Capacity_tons_per_second
            if cap_key is None:
                if _match(fn_clean, "Capacity_ton_per_h") or \
                   _match(fn_clean, "Capacity_tons_per_hour") or \
                   _match(fn_clean, "Capacity_tons_per_second"):
                    cap_key = fn

        if prov_key is None or cap_key is None:
            raise KeyError(
                f"Column 'Province' or capacity column not found in {cap_csv_path} header; actual columns: {fieldnames}"
            )

        # Check if unit conversion is needed (if column is tons_per_second, convert to tons_per_hour)
        needs_conversion = "tons_per_second" in cap_key.lower() or "ton_per_second" in cap_key.lower()

        for row in reader:
            if not row:  # Skip empty rows
                continue
            prov = row.get(prov_key, "").strip()
            if not prov:
                continue
            if prov not in PROVINCE_TO_REGION:
                # Allow silent skip
                continue
            region_str, region_num = PROVINCE_TO_REGION[prov]
            cap_val = row.get(cap_key, "")
            if cap_val is None or cap_val == "":
                continue
            cap_value = float(cap_val)
            # If conversion needed (tons/s → tons/h)
            if needs_conversion:
                cap_value = cap_value * 3600.0  # 1 t/s = 3600 t/h
            existing_cap = 0.0 if cap_value < capacity_eps else cap_value
            info[prov] = {
                "province": prov,
                "region_str": region_str,
                "region_num": region_num,
                "existing_capacity": existing_cap,  # units: t/h
            }
    return info


def merge_province_info_with_capacity(capacity_info: dict) -> dict:
    """Ensure every province in PROVINCE_TO_REGION exists in province_info.

    Provinces missing in capacity CSV are included with existing_capacity = 0.
    """
    merged = {}
    for prov, (region_str, region_num) in PROVINCE_TO_REGION.items():
        base = {
            "province": prov,
            "region_str": region_str,
            "region_num": region_num,
            "existing_capacity": 0.0,
        }
        if prov in capacity_info:
            base["existing_capacity"] = float(capacity_info[prov].get("existing_capacity", 0.0))
        merged[prov] = base
    return merged


def load_demand_weights_by_province(year: int = 2025, scenario: str = "mid") -> dict:
    """Return weights per province based on aluminum_demand_by_province.csv.

    Weights are the per-province Demand_ton_per_h for the given year & scenario.
    Provinces absent in the CSV have weight 0.
    """
    demand_csv_path = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_demand_by_province.csv",
    )
    weights = {prov: 0.0 for prov in PROVINCE_TO_REGION.keys()}
    year_str = str(year)
    scenario_l = scenario.strip().lower()

    with open(demand_csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []
        def _col(name: str) -> str:
            for fn in fns:
                if fn.strip().lstrip("\ufeff").lower() == name.lower():
                    return fn
            raise KeyError(f"Column '{name}' not found in {demand_csv_path}; columns={fns}")

        prov_k = _col("Province")
        year_k = _col("Year")
        scen_k = _col("Scenario")
        dem_k = _col("Demand_ton_per_h")

        for row in reader:
            if not row:
                continue
            prov = (row.get(prov_k) or "").strip()
            if prov not in PROVINCE_TO_REGION:
                continue
            if (row.get(year_k) or "").strip() != year_str:
                continue
            if (row.get(scen_k) or "").strip().lower() != scenario_l:
                continue
            v = row.get(dem_k)
            if v is None or v == "":
                continue
            weights[prov] = float(v)

    return weights


def load_scrap_share_weights_from_csv(path: str) -> dict:
    """Load province weights from a simple abbr→weight CSV."""
    abbr_to_province = {
        "bj": "Beijing",
        "tj": "Tianjin",
        "he": "Hebei",
        "sx": "Shanxi",
        "nm": "InnerMongolia",
        "ln": "Liaoning",
        "jl": "Jilin",
        "hl": "Heilongjiang",
        "sh": "Shanghai",
        "js": "Jiangsu",
        "zj": "Zhejiang",
        "ah": "Anhui",
        "fj": "Fujian",
        "jx": "Jiangxi",
        "sd": "Shandong",
        "ha": "Henan",
        "hb": "Hubei",
        "hn": "Hunan",
        "gd": "Guangdong",
        "gx": "Guangxi",
        "hi": "Hainan",
        "cq": "Chongqing",
        "sc": "Sichuan",
        "gz": "Guizhou",
        "yn": "Yunnan",
        "sn": "Shaanxi",
        "gs": "Gansu",
        "qh": "Qinghai",
        "nx": "Ningxia",
        "xj": "Xinjiang",
    }

    weights = {prov: 0.0 for prov in PROVINCE_TO_REGION.keys()}
    with open(path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []
        def _col(name: str) -> str:
            for fn in fns:
                if fn.strip().lstrip("\ufeff").lower() == name.lower():
                    return fn
            raise KeyError(f"Column '{name}' not found in {path}; columns={fns}")

        abbr_k = _col("abbr")
        weight_k = _col("weight")
        for row in reader:
            if not row:
                continue
            abbr = (row.get(abbr_k) or "").strip().lower()
            if not abbr:
                continue
            prov = abbr_to_province.get(abbr)
            if prov is None or prov not in PROVINCE_TO_REGION:
                continue
            v = row.get(weight_k)
            if v is None or v == "":
                continue
            weights[prov] = float(v)

    return weights


def compute_scrap_max_supply_by_province(
    scrap_mid_mton_per_year: float,
    weights_by_province: dict,
) -> dict:
    """Compute 288h scrap max_supply (tons) per province using weights.

    Total scrap is `scrap_mid_mton_per_year` (Mton/year), distributed by weights.
    """
    total_weight = sum(max(0.0, float(w)) for w in weights_by_province.values())
    total_scrap_288h_tons = convert_mton_per_year_to_288h_tons(float(scrap_mid_mton_per_year))

    caps = {}
    for prov in PROVINCE_TO_REGION.keys():
        w = max(0.0, float(weights_by_province.get(prov, 0.0)))
        share = (w / total_weight) if total_weight > 0 else 0.0
        caps[prov] = total_scrap_288h_tons * share
    return caps


def write_scrap_caps_csv(
    out_path: str,
    scrap_mid_mton_per_year: float,
    weights_by_province: dict,
    caps_by_province: dict,
    year: int,
    scenario: str,
):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    total_weight = sum(max(0.0, float(w)) for w in weights_by_province.values())
    total_scrap_288h_tons = convert_mton_per_year_to_288h_tons(float(scrap_mid_mton_per_year))

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "Province",
                "Region",
                "Year",
                "Scenario",
                "ScrapMid_Mton_per_year",
                "Weight_Demand_ton_per_h",
                "WeightShare",
                "MaxSupply_288h_tons",
            ]
        )
        for prov, (region_str, _region_num) in PROVINCE_TO_REGION.items():
            weight = float(weights_by_province.get(prov, 0.0))
            share = (max(0.0, weight) / total_weight) if total_weight > 0 else 0.0
            cap = float(caps_by_province.get(prov, 0.0))
            w.writerow(
                [
                    prov,
                    region_str,
                    int(year),
                    str(scenario),
                    float(scrap_mid_mton_per_year),
                    weight,
                    share,
                    cap,
                ]
            )

        # Totals row (for quick sanity check)
        w.writerow(
            [
                "TOTAL",
                "",
                int(year),
                str(scenario),
                float(scrap_mid_mton_per_year),
                float(total_weight),
                1.0 if total_weight > 0 else 0.0,
                float(total_scrap_288h_tons),
            ]
        )


def update_commodities():
    path = os.path.join(BASE_DIR, "system", "commodities.json")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "commodities" not in data or not isinstance(data["commodities"], list):
        raise ValueError("commodities.json does not contain list key 'commodities'")

    current = set(data["commodities"])
    to_add = ["Aluminum", "Alumina", "AluminumScrap", "Bauxite", "Graphite"]
    for c in to_add:
        if c not in current:
            data["commodities"].append(c)

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def aluminum_node_block(total_demand_288h: float) -> dict:
    return {
        "type": "Aluminum",
        "global_data": {
            "time_interval": "Aluminum",
            "constraints": {
                "AggregatedDemandConstraint": True,
            },
        },
        "instance_data": [
            {
                "id": "aluminum_produced",
                "rhs_policy": {
                    "AggregatedDemandConstraint": total_demand_288h,
                },
            }
        ],
    }


def alumina_node_block() -> dict:
    return {
        "type": "Alumina",
        "global_data": {
            "time_interval": "Alumina",
            "constraints": {
                "AggregatedDemandConstraint": True,
            },
        },
        "instance_data": [
            {
                "id": "alumina_produced",
                "rhs_policy": {
                    "AggregatedDemandConstraint": 0,
                },
            }
        ],
    }


def resource_node_block(res_type: str, id_prefix: str, province_info: dict, max_supply: float) -> dict:
    return {
        "type": res_type,
        "global_data": {
            "time_interval": res_type,
            "constraints": {
                "BalanceConstraint": True,
            },
        },
        "instance_data": [
            {
                "id": f"{id_prefix}_{info['region_str']}",
                "max_supply": [max_supply],
                "price_supply": [0],
            }
            for info in province_info.values()
        ],
    }


def resource_node_block_per_province_cap(res_type: str, id_prefix: str, province_info: dict, caps_by_prov: dict) -> dict:
    return {
        "type": res_type,
        "global_data": {
            "time_interval": res_type,
            "constraints": {
                "BalanceConstraint": True,
            },
        },
        "instance_data": [
            {
                "id": f"{id_prefix}_{info['region_str']}",
                "max_supply": [float(caps_by_prov.get(info["province"], 0.0))],
                "price_supply": [0],
            }
            for info in province_info.values()
        ],
    }


def update_nodes_files(total_demand: dict, province_info: dict, scrap_caps_by_prov: dict):
    for p in range(1, 8):
        path = os.path.join(BASE_DIR, "system", f"nodes_{p}.json")
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        nodes = data.get("nodes", [])

        # Remove existing aluminum-related nodes if present
        aluminum_types = {"Aluminum", "Alumina", "AluminumScrap", "Bauxite", "Graphite"}
        nodes = [n for n in nodes if n.get("type") not in aluminum_types]

        # Add new nodes
        nodes.append(aluminum_node_block(total_demand[p]))
        nodes.append(alumina_node_block())
        # Keep scrap max_supply disabled in nodes for now (set to 0 everywhere).
        nodes.append(resource_node_block("AluminumScrap", "aluminumscrap_source", province_info, max_supply=0.0))
        nodes.append(resource_node_block("Bauxite", "bauxite_source", province_info, max_supply=100_000.0))
        nodes.append(resource_node_block("Graphite", "graphite_source", province_info, max_supply=100_000.0))

        data["nodes"] = nodes
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)


def load_single_node_templates():
    """Load global_data templates for AluminumSmelting / Refining / AluminaPlant from single-node case."""
    single_base = os.path.join(
        BASE_DIR,
        "..",
        "China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum",
    )
    assets1 = os.path.join(single_base, "assets", "assets_1")

    def _load(path, top_key):
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        # Structure like: { "AluminumSmelting": [ { "type": "...", "global_data": {...}, ... } ] }
        return d[top_key][0]["global_data"]

    smelting_global = _load(os.path.join(assets1, "aluminumsmelting.json"), "AluminumSmelting")
    refining_global = _load(os.path.join(assets1, "aluminumrefining.json"), "AluminumRefining")
    plant_global = _load(os.path.join(assets1, "aluminaplant.json"), "AluminaPlant")
    return smelting_global, refining_global, plant_global


def build_smelting_instances(province_info: dict) -> list:
    inst = []
    for info in province_info.values():
        r = info["region_str"]
        inst.append(
            {
                "id": f"aluminum_smelting_{r}",
                "location": r,
                "existing_capacity": info["existing_capacity"],
                "aluminum_constraints": {
                    "MinFlowConstraint": True,
                },
                "edges": {
                    "elec_edge": {
                        "start_vertex": f"elec_{r}",
                        "end_vertex": f"aluminum_smelting_{r}",
                    },
                    "aluminum_edge": {
                        "start_vertex": f"aluminum_smelting_{r}",
                        "end_vertex": "aluminum_produced",
                    },
                    "alumina_edge": {
                        "start_vertex": "alumina_produced",
                        "end_vertex": f"aluminum_smelting_{r}",
                    },
                    "graphite_edge": {
                        "start_vertex": f"graphite_source_{r}",
                        "end_vertex": f"aluminum_smelting_{r}",
                    },
                },
            }
        )
    return inst


def build_refining_instances(province_info: dict) -> list:
    inst = []
    for info in province_info.values():
        r = info["region_str"]
        inst.append(
            {
                "id": f"aluminum_refining_{r}",
                "location": r,
                "existing_capacity": 0.0,
                "edges": {
                    "elec_edge": {
                        "start_vertex": f"elec_{r}",
                        "end_vertex": f"aluminum_refining_{r}",
                    },
                    "aluminum_edge": {
                        "start_vertex": f"aluminum_refining_{r}",
                        "end_vertex": "aluminum_produced",
                    },
                    "aluminumscrap_edge": {
                        "start_vertex": f"aluminumscrap_source_{r}",
                        "end_vertex": f"aluminum_refining_{r}",
                    },
                },
            }
        )
    return inst


def build_plant_instances(province_info: dict) -> list:
    inst = []
    for info in province_info.values():
        r = info["region_str"]
        inst.append(
            {
                "id": f"alumina_plant_{r}",
                "location": r,
                "existing_capacity": 0.0,
                "edges": {
                    "elec_edge": {
                        "start_vertex": f"elec_{r}",
                        "end_vertex": f"alumina_plant_{r}",
                    },
                    "alumina_edge": {
                        "start_vertex": f"alumina_plant_{r}",
                        "end_vertex": "alumina_produced",
                    },
                    "bauxite_edge": {
                        "start_vertex": f"bauxite_source_{r}",
                        "end_vertex": f"alumina_plant_{r}",
                    },
                    "fuel_edge": {
                        "start_vertex": f"natgas_{r}",
                        "end_vertex": f"alumina_plant_{r}",
                    },
                },
            }
        )
    return inst


def generate_assets(province_info: dict):
    smelting_global, refining_global, plant_global = load_single_node_templates()

    for p in range(1, 8):
        assets_dir = os.path.join(BASE_DIR, "assets", f"assets_{p}")
        os.makedirs(assets_dir, exist_ok=True)

        # AluminumSmelting
        smelting_obj = {
            "AluminumSmelting": [
                {
                    "type": "AluminumSmelting",
                    "global_data": deepcopy(smelting_global),
                    "instance_data": build_smelting_instances(province_info),
                }
            ]
        }
        with open(os.path.join(assets_dir, "aluminumsmelting.json"), "w", encoding="utf-8") as f:
            json.dump(smelting_obj, f, indent=2, ensure_ascii=False)

        # AluminumRefining
        refining_obj = {
            "AluminumRefining": [
                {
                    "type": "AluminumRefining",
                    "global_data": deepcopy(refining_global),
                    "instance_data": build_refining_instances(province_info),
                }
            ]
        }
        with open(os.path.join(assets_dir, "aluminumrefining.json"), "w", encoding="utf-8") as f:
            json.dump(refining_obj, f, indent=2, ensure_ascii=False)

        # AluminaPlant
        plant_obj = {
            "AluminaPlant": [
                {
                    "type": "AluminaPlant",
                    "global_data": deepcopy(plant_global),
                    "instance_data": build_plant_instances(province_info),
                }
            ]
        }
        with open(os.path.join(assets_dir, "aluminaplant.json"), "w", encoding="utf-8") as f:
            json.dump(plant_obj, f, indent=2, ensure_ascii=False)


def main():
    print("Generating aluminum inputs for Ver12 (Python script)...")
    parser = argparse.ArgumentParser()
    parser.add_argument("--demand-2025-10kt", type=float, default=4000.0)
    parser.add_argument("--aluminum-scrap-mid-mton", type=float, default=0.0)
    parser.add_argument("--scrap-share-year", type=int, default=2025)
    parser.add_argument("--scrap-share-scenario", type=str, default="mid")
    parser.add_argument("--scrap-share-weights-csv", type=str, default=None)
    args = parser.parse_args()

    total_demand = load_total_demand_per_period(demand_2025_10kt=float(args.demand_2025_10kt))
    print("  Total primary aluminum demand per period (288h tons):")
    for p in sorted(total_demand):
        print(f"    period {p}: {total_demand[p]:.5g}")

    capacity_info = load_province_capacity()
    province_info = merge_province_info_with_capacity(capacity_info)
    print(f"  Provinces in node system mapping: {len(province_info)}")

    if args.scrap_share_weights_csv:
        weights = load_scrap_share_weights_from_csv(args.scrap_share_weights_csv)
    else:
        weights = load_demand_weights_by_province(year=args.scrap_share_year, scenario=args.scrap_share_scenario)
    scrap_caps_by_prov = compute_scrap_max_supply_by_province(
        scrap_mid_mton_per_year=float(args.aluminum_scrap_mid_mton),
        weights_by_province=weights,
    )

    scrap_caps_out = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_scrap_max_supply_by_province.csv",
    )
    write_scrap_caps_csv(
        out_path=scrap_caps_out,
        scrap_mid_mton_per_year=float(args.aluminum_scrap_mid_mton),
        weights_by_province=weights,
        caps_by_province=scrap_caps_by_prov,
        year=args.scrap_share_year,
        scenario=args.scrap_share_scenario,
    )

    update_commodities()
    update_nodes_files(total_demand, province_info, scrap_caps_by_prov)
    generate_assets(province_info)

    # Also update time_data.json with time-step info for aluminum commodities
    time_data_path = os.path.join(BASE_DIR, "system", "time_data.json")
    if os.path.exists(time_data_path):
        with open(time_data_path, "r", encoding="utf-8") as f:
            td = json.load(f)
        # Same as single-node case: all new commodities use 1h time step, 24h per subperiod, 288h total
        hours_per_ts = td.get("HoursPerTimeStep", {})
        hours_per_sp = td.get("HoursPerSubperiod", {})
        for k in ["Aluminum", "Alumina", "AluminumScrap", "Bauxite", "Graphite"]:
            hours_per_ts.setdefault(k, 1)
            hours_per_sp.setdefault(k, 24)
        td["HoursPerTimeStep"] = hours_per_ts
        td["HoursPerSubperiod"] = hours_per_sp
        td.setdefault("NumberOfSubperiods", 12)
        td.setdefault("TotalHoursModeled", 288)
        with open(time_data_path, "w", encoding="utf-8") as f:
            json.dump(td, f, indent=2, ensure_ascii=False)

    print("Done. commodities.json, nodes_*.json, and assets_*/aluminum*.json have been updated/created.")


if __name__ == "__main__":
    main()


