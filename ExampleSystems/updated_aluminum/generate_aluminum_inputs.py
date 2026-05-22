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
- Total aluminum demand uses aluminum_sales_mid.csv (VALUE in Mton/year)
- Year to period mapping:
    period 1 → 2025
    period 2 → 2030
    period 3 → 2035
    period 4 → 2040
    period 5 → 2045
    period 6 → 2050
    period 7 → 2055
- Demand conversion: annual volume → total tons over 288 hours
- Scrap max_supply uses aluminum_scrap_mid.csv * (0.7 * 1.05)
- Provinces with very small capacity are still included in assets, but existing_capacity is set to 0
"""

import json
import csv
import os
import argparse
from copy import deepcopy


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SCRAP_TO_ALUMINUM_FACTOR = 0.7 * 1.05
DEFAULT_CNY_PER_USD_2025 = 7.2
DEFAULT_SCRAP_PRICE = 15350.0 / DEFAULT_CNY_PER_USD_2025
DEFAULT_BAUXITE_PRICE = 67.5
DEFAULT_GRAPHITE_ANODE_PRICE = 5400.0 / DEFAULT_CNY_PER_USD_2025
PERIOD_YEAR_MAP = {
    1: 2025,
    2: 2030,
    3: 2035,
    4: 2040,
    5: 2045,
    6: 2050,
    7: 2055,
}

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


def convert_mton_per_year_to_288h_tons(x_mton_year: float) -> float:
    return x_mton_year * 1_000_000.0 * 288.0 / 8760.0


def convert_mton_per_year_to_ton_per_hour(x_mton_year: float) -> float:
    return x_mton_year * 1_000_000.0 / 8760.0


def convert_10kt_per_year_to_ton_per_hour(x_10kt_year: float) -> float:
    return x_10kt_year * 10_000.0 / 8760.0


def _build_period_values_from_year_map(year_map: dict, converter) -> dict:
    out = {}
    for period, year in PERIOD_YEAR_MAP.items():
        year_str = str(year)
        if year_str not in year_map:
            raise KeyError(f"Year {year_str} missing in source data")
        out[period] = converter(float(year_map[year_str]))
    return out


def load_total_demand_per_period_from_sales_csv() -> dict:
    """Load total aluminum demand from aluminum_sales_mid.csv (VALUE in Mton/year)."""
    sales_csv_path = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_sales_mid.csv",
    )
    with open(sales_csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []

        def _col(name: str) -> str:
            for fn in fns:
                if fn.strip().lstrip("\ufeff").lower() == name.lower():
                    return fn
            raise KeyError(f"Column '{name}' not found in {sales_csv_path}; columns={fns}")

        year_k = _col("YEAR")
        value_k = _col("VALUE")
        demand_mton_by_year = {}
        for row in reader:
            if not row:
                continue
            year_raw = (row.get(year_k) or "").strip()
            value_raw = (row.get(value_k) or "").strip()
            if not year_raw or not value_raw:
                continue
            demand_mton_by_year[year_raw] = float(value_raw)

    return _build_period_values_from_year_map(demand_mton_by_year, convert_mton_per_year_to_288h_tons)


def load_total_demand_per_period() -> dict:
    """Load total aluminum demand from aluminum_sales_mid.csv."""
    total = load_total_demand_per_period_from_sales_csv()
    print("  Loaded total aluminum demand from aluminum_sales_mid.csv")
    return total


def load_scrap_mton_per_year_by_period_from_csv() -> dict:
    """Load scrap availability and apply fixed scrap-to-aluminum factor."""
    scrap_csv_path = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_scrap_mid.csv",
    )
    with open(scrap_csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []

        def _col(name: str) -> str:
            for fn in fns:
                if fn.strip().lstrip("\ufeff").lower() == name.lower():
                    return fn
            raise KeyError(f"Column '{name}' not found in {scrap_csv_path}; columns={fns}")

        year_k = _col("YEAR")
        value_k = _col("VALUE")
        scrap_mton_by_year = {}
        for row in reader:
            if not row:
                continue
            year_raw = (row.get(year_k) or "").strip()
            value_raw = (row.get(value_k) or "").strip()
            if not year_raw or not value_raw:
                continue
            scrap_mton_by_year[year_raw] = float(value_raw) * float(SCRAP_TO_ALUMINUM_FACTOR)

    period_scrap = {}
    for period, year in PERIOD_YEAR_MAP.items():
        year_str = str(year)
        if year_str not in scrap_mton_by_year:
            raise KeyError(f"Year {year_str} missing in aluminum_scrap_mid.csv")
        period_scrap[period] = float(scrap_mton_by_year[year_str])
    return period_scrap


def load_refining_existing_capacity(path: str = None) -> dict:
    """Load optional existing_capacity (t/h) for AluminumRefining by province."""
    if path is None:
        path = os.path.join(
            BASE_DIR,
            "data",
            "aluminum_demand",
            "aluminum_refining_capacity_by_province.csv",
        )
    if not os.path.exists(path):
        return {}

    caps = {prov: 0.0 for prov in PROVINCE_TO_REGION.keys()}
    with open(path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []

        def _col(options) -> str:
            for opt in options:
                for fn in fns:
                    if fn.strip().lstrip("\ufeff").lower() == opt.lower():
                        return fn
            raise KeyError(f"None of columns {options} found in {path}; columns={fns}")

        prov_k = _col(["Province"])
        cap_k = _col(["Capacity_ton_per_h", "Capacity_tons_per_hour", "Capacity_tons_per_second"])
        needs_conversion = "tons_per_second" in cap_k.lower() or "ton_per_second" in cap_k.lower()

        for row in reader:
            if not row:
                continue
            prov = (row.get(prov_k) or "").strip()
            if prov not in PROVINCE_TO_REGION:
                continue
            cap_raw = (row.get(cap_k) or "").strip()
            if not cap_raw:
                continue
            cap_val = float(cap_raw)
            if needs_conversion:
                cap_val *= 3600.0
            caps[prov] = max(0.0, cap_val)
    return caps


def load_alumina_plant_existing_capacity(path: str = None) -> dict:
    """Load optional alumina plant existing_capacity (t/h) from annual output table."""
    if path is None:
        path = os.path.join(
            BASE_DIR,
            "data",
            "aluminum_demand",
            "alumina_plant_production_2025.csv",
        )
    if not os.path.exists(path):
        return {}

    cn_to_province = {
        "山东": "Shandong",
        "山西": "Shanxi",
        "广西": "Guangxi",
        "河南": "Henan",
        "贵州": "Guizhou",
        "重庆": "Chongqing",
        "云南": "Yunnan",
        "内蒙古": "InnerMongolia",
        "甘肃": "Gansu",
        "湖北": "Hubei",
        "江西": "Jiangxi",
        "广东": "Guangdong",
        "浙江": "Zhejiang",
        "河北": "Hebei",
    }

    caps = {prov: 0.0 for prov in PROVINCE_TO_REGION.keys()}
    with open(path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fns = reader.fieldnames or []

        def _col(options) -> str:
            for opt in options:
                for fn in fns:
                    if fn.strip().lstrip("\ufeff").lower() == opt.lower():
                        return fn
            raise KeyError(f"None of columns {options} found in {path}; columns={fns}")

        prov_k = _col(["Province", "ProvinceCN", "地区"])
        prod_k = _col(["Production_10kt_2025", "产量_万吨", "量"])

        for row in reader:
            if not row:
                continue
            prov_raw = (row.get(prov_k) or "").strip()
            if not prov_raw:
                continue
            if prov_raw in PROVINCE_TO_REGION:
                prov = prov_raw
            else:
                prov = cn_to_province.get(prov_raw)
            if prov is None or prov not in PROVINCE_TO_REGION:
                continue

            v_raw = (row.get(prod_k) or "").strip()
            if not v_raw:
                continue
            production_10kt = float(v_raw)
            caps[prov] = max(0.0, convert_10kt_per_year_to_ton_per_hour(production_10kt))
    return caps


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
    """Compute hourly scrap max_supply (t/h) per province using weights.

    Total scrap is `scrap_mid_mton_per_year` (Mton/year), distributed by weights.
    """
    total_weight = sum(max(0.0, float(w)) for w in weights_by_province.values())
    total_scrap_ton_per_h = convert_mton_per_year_to_ton_per_hour(float(scrap_mid_mton_per_year))

    caps = {}
    for prov in PROVINCE_TO_REGION.keys():
        w = max(0.0, float(weights_by_province.get(prov, 0.0)))
        share = (w / total_weight) if total_weight > 0 else 0.0
        caps[prov] = total_scrap_ton_per_h * share
    return caps


def allocate_total_to_provinces(total_value: float, weights_by_province: dict) -> dict:
    """Allocate a total value to provinces proportionally to weights."""
    total_weight = sum(max(0.0, float(w)) for w in weights_by_province.values())
    out = {}
    for prov in PROVINCE_TO_REGION.keys():
        w = max(0.0, float(weights_by_province.get(prov, 0.0)))
        share = (w / total_weight) if total_weight > 0 else 0.0
        out[prov] = float(total_value) * share
    return out


def write_scrap_caps_csv(
    out_path: str,
    scrap_mid_mton_per_year_by_period: dict,
    weights_by_province_by_period: dict,
    caps_by_province_by_period: dict,
    weight_source: str,
):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "Province",
                "Region",
                "Period",
                "Year",
                "WeightSource",
                "ScrapMid_Mton_per_year",
                "Weight_ScrapShareInput",
                "WeightShare",
                "MaxSupply_ton_per_h",
                "ImpliedTotal_288h_tons",
            ]
        )
        for period, year in PERIOD_YEAR_MAP.items():
            scrap_mid_mton_per_year = float(scrap_mid_mton_per_year_by_period.get(period, 0.0))
            total_scrap_ton_per_h = convert_mton_per_year_to_ton_per_hour(scrap_mid_mton_per_year)
            total_scrap_288h_tons = convert_mton_per_year_to_288h_tons(scrap_mid_mton_per_year)
            weights_by_province = weights_by_province_by_period.get(period, {})
            total_weight = sum(max(0.0, float(v)) for v in weights_by_province.values())
            caps_by_province = caps_by_province_by_period.get(period, {})

            for prov, (region_str, _region_num) in PROVINCE_TO_REGION.items():
                weight = float(weights_by_province.get(prov, 0.0))
                share = (max(0.0, weight) / total_weight) if total_weight > 0 else 0.0
                cap = float(caps_by_province.get(prov, 0.0))
                w.writerow(
                    [
                        prov,
                        region_str,
                        int(period),
                        int(year),
                        str(weight_source),
                        scrap_mid_mton_per_year,
                        weight,
                        share,
                        cap,
                        cap * 288.0,
                    ]
                )

            # Totals row (for quick sanity check)
            w.writerow(
                [
                    "TOTAL",
                    "",
                    int(period),
                    int(year),
                    str(weight_source),
                    scrap_mid_mton_per_year,
                    float(total_weight),
                    1.0 if total_weight > 0 else 0.0,
                    float(total_scrap_ton_per_h),
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


def aluminum_node_block(demand_by_province_288h: dict, province_info: dict) -> dict:
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
                "id": f"aluminum_produced_{info['region_str']}",
                "rhs_policy": {
                    "AggregatedDemandConstraint": float(demand_by_province_288h.get(info["province"], 0.0)),
                },
            }
            for info in province_info.values()
        ],
    }


def alumina_node_block(province_info: dict) -> dict:
    return {
        "type": "Alumina",
        "global_data": {
            "time_interval": "Alumina",
            "constraints": {
                "BalanceConstraint": True,
            },
        },
        "instance_data": [
            {
                "id": f"alumina_produced_{info['region_str']}",
            }
            for info in province_info.values()
        ],
    }


def resource_node_block(
    res_type: str,
    id_prefix: str,
    province_info: dict,
    max_supply: float,
    price_supply: float = 0.0,
) -> dict:
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
                "price_supply": [float(price_supply)],
            }
            for info in province_info.values()
        ],
    }


def resource_node_block_per_province_cap(
    res_type: str,
    id_prefix: str,
    province_info: dict,
    caps_by_prov: dict,
    price_supply: float = 0.0,
) -> dict:
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
                "price_supply": [float(price_supply)],
            }
            for info in province_info.values()
        ],
    }


def update_nodes_files(
    demand_by_prov_by_period: dict,
    province_info: dict,
    scrap_caps_by_prov_by_period: dict,
    scrap_price: float,
    bauxite_price: float,
    graphite_price: float,
):
    for p in range(1, 8):
        path = os.path.join(BASE_DIR, "system", f"nodes_{p}.json")
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        nodes = data.get("nodes", [])

        # Remove existing aluminum-related nodes if present
        aluminum_types = {"Aluminum", "Alumina", "AluminumScrap", "Bauxite", "Graphite"}
        nodes = [n for n in nodes if n.get("type") not in aluminum_types]

        # Add new nodes
        nodes.append(aluminum_node_block(demand_by_province_288h=demand_by_prov_by_period[p], province_info=province_info))
        nodes.append(alumina_node_block(province_info))
        nodes.append(
            resource_node_block_per_province_cap(
                "AluminumScrap",
                "aluminumscrap_source",
                province_info,
                caps_by_prov=scrap_caps_by_prov_by_period.get(p, {}),
                price_supply=scrap_price,
            )
        )
        nodes.append(
            resource_node_block(
                "Bauxite",
                "bauxite_source",
                province_info,
                max_supply=100_000.0,
                price_supply=bauxite_price,
            )
        )
        nodes.append(
            resource_node_block(
                "Graphite",
                "graphite_source",
                province_info,
                max_supply=100_000.0,
                price_supply=graphite_price,
            )
        )

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
                        "end_vertex": f"aluminum_produced_{r}",
                    },
                    "alumina_edge": {
                        "start_vertex": f"alumina_produced_{r}",
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


def build_refining_instances(province_info: dict, refining_capacity_by_province: dict = None) -> list:
    refining_capacity_by_province = refining_capacity_by_province or {}
    inst = []
    for info in province_info.values():
        r = info["region_str"]
        prov = info["province"]
        inst.append(
            {
                "id": f"aluminum_refining_{r}",
                "location": r,
                "existing_capacity": float(refining_capacity_by_province.get(prov, 0.0)),
                "edges": {
                    "elec_edge": {
                        "start_vertex": f"elec_{r}",
                        "end_vertex": f"aluminum_refining_{r}",
                    },
                    "aluminum_edge": {
                        "start_vertex": f"aluminum_refining_{r}",
                        "end_vertex": f"aluminum_produced_{r}",
                    },
                    "aluminumscrap_edge": {
                        "start_vertex": f"aluminumscrap_source_{r}",
                        "end_vertex": f"aluminum_refining_{r}",
                    },
                },
            }
        )
    return inst


def build_plant_instances(province_info: dict, alumina_capacity_by_province: dict = None) -> list:
    alumina_capacity_by_province = alumina_capacity_by_province or {}
    inst = []
    for info in province_info.values():
        r = info["region_str"]
        prov = info["province"]
        inst.append(
            {
                "id": f"alumina_plant_{r}",
                "location": r,
                "existing_capacity": float(alumina_capacity_by_province.get(prov, 0.0)),
                "edges": {
                    "elec_edge": {
                        "start_vertex": f"elec_{r}",
                        "end_vertex": f"alumina_plant_{r}",
                    },
                    "alumina_edge": {
                        "start_vertex": f"alumina_plant_{r}",
                        "end_vertex": f"alumina_produced_{r}",
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


def generate_assets(
    province_info: dict,
    refining_capacity_by_province: dict = None,
    alumina_capacity_by_province: dict = None,
):
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
                    "instance_data": build_refining_instances(
                        province_info, refining_capacity_by_province=refining_capacity_by_province
                    ),
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
                    "instance_data": build_plant_instances(
                        province_info,
                        alumina_capacity_by_province=alumina_capacity_by_province,
                    ),
                }
            ]
        }
        with open(os.path.join(assets_dir, "aluminaplant.json"), "w", encoding="utf-8") as f:
            json.dump(plant_obj, f, indent=2, ensure_ascii=False)


def main():
    print("Generating aluminum inputs for Ver12 (Python script)...")
    parser = argparse.ArgumentParser()
    parser.add_argument("--aluminum-scrap-mid-mton", type=float, default=None)
    parser.add_argument(
        "--scrap-share-weights-csv",
        type=str,
        default=os.path.join(BASE_DIR, "data", "aluminum_demand", "aluminum_scrap_share_weights.csv"),
    )
    parser.add_argument("--scrap-price", type=float, default=DEFAULT_SCRAP_PRICE)
    parser.add_argument("--bauxite-price", type=float, default=DEFAULT_BAUXITE_PRICE)
    parser.add_argument("--graphite-price", type=float, default=DEFAULT_GRAPHITE_ANODE_PRICE)
    parser.add_argument("--refining-capacity-csv", type=str, default=None)
    parser.add_argument(
        "--alumina-capacity-csv",
        type=str,
        default=os.path.join(BASE_DIR, "data", "aluminum_demand", "alumina_plant_production_2025.csv"),
    )
    args = parser.parse_args()

    total_demand = load_total_demand_per_period()
    print("  Total primary aluminum demand per period (288h tons):")
    for p in sorted(total_demand):
        print(f"    period {p}: {total_demand[p]:.5g}")

    capacity_info = load_province_capacity()
    province_info = merge_province_info_with_capacity(capacity_info)
    print(f"  Provinces in node system mapping: {len(province_info)}")

    shared_weights = load_scrap_share_weights_from_csv(args.scrap_share_weights_csv)
    weights_by_period = {p: dict(shared_weights) for p in PERIOD_YEAR_MAP}
    print(f"  Using scrap share weights from: {args.scrap_share_weights_csv}")
    demand_by_prov_by_period = {
        p: allocate_total_to_provinces(total_demand[p], weights_by_period[p])
        for p in PERIOD_YEAR_MAP
    }
    print("  Distributed Aluminum demand by province using scrap share weights.")

    if args.aluminum_scrap_mid_mton is not None:
        scrap_mton_by_period = {p: float(args.aluminum_scrap_mid_mton) for p in PERIOD_YEAR_MAP}
        print("  Using CLI aluminum_scrap_mid_mton for all periods.")
    else:
        scrap_mton_by_period = load_scrap_mton_per_year_by_period_from_csv()
        print(f"  Loaded aluminum scrap supply from aluminum_scrap_mid.csv with factor={SCRAP_TO_ALUMINUM_FACTOR}")

    scrap_caps_by_prov_by_period = {}
    for p in PERIOD_YEAR_MAP:
        scrap_caps_by_prov_by_period[p] = compute_scrap_max_supply_by_province(
            scrap_mid_mton_per_year=float(scrap_mton_by_period[p]),
            weights_by_province=weights_by_period[p],
        )

    scrap_caps_out = os.path.join(
        BASE_DIR,
        "data",
        "aluminum_demand",
        "aluminum_scrap_max_supply_by_province.csv",
    )
    write_scrap_caps_csv(
        out_path=scrap_caps_out,
        scrap_mid_mton_per_year_by_period=scrap_mton_by_period,
        weights_by_province_by_period=weights_by_period,
        caps_by_province_by_period=scrap_caps_by_prov_by_period,
        weight_source=os.path.basename(args.scrap_share_weights_csv),
    )

    refining_caps = load_refining_existing_capacity(path=args.refining_capacity_csv)
    if refining_caps:
        print(f"  Loaded refining existing capacities for {sum(1 for v in refining_caps.values() if v > 0)} provinces.")
    else:
        print("  No refining capacity CSV found/provided; keeping AluminumRefining existing_capacity=0.0.")

    alumina_caps = load_alumina_plant_existing_capacity(path=args.alumina_capacity_csv)
    if alumina_caps:
        print(f"  Loaded alumina plant capacities for {sum(1 for v in alumina_caps.values() if v > 0)} provinces.")
    else:
        print("  No alumina capacity CSV found/provided; keeping AluminaPlant existing_capacity=0.0.")
    print(
        "  Resource price_supply defaults "
        f"(Scrap/Bauxite/Graphite) = {args.scrap_price}/{args.bauxite_price}/{args.graphite_price}"
    )

    update_commodities()
    update_nodes_files(
        demand_by_prov_by_period,
        province_info,
        scrap_caps_by_prov_by_period,
        scrap_price=float(args.scrap_price),
        bauxite_price=float(args.bauxite_price),
        graphite_price=float(args.graphite_price),
    )
    generate_assets(
        province_info,
        refining_capacity_by_province=refining_caps,
        alumina_capacity_by_province=alumina_caps,
    )

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


