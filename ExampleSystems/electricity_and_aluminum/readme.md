# Ver12 China electricity multi-stage (288h × 7 periods) with CO2 cap and CCS

This example is a **31-node** China provincial electricity model with **7 planning periods**, **288-hour** subperiod representation, a **CO2 cap**, and **CCS** (carbon capture and storage). It extends the electricity-only grid with **aluminum sector integration**: primary aluminum demand, smelting, refining, and alumina production are represented at the provincial level.

---

## Aluminum-related files added

The following files were added or updated to integrate the aluminum sector. Use them together when sharing or re-running the case.

### Documentation (English)

| File | Description |
|------|-------------|
| **PROVINCE_MAPPING.md** | Province name ↔ node name mapping (data files vs. node system). Includes capacity (t Al/s) per province, naming rules, and notes on InnerMongolia/Innermongolia and nodes without aluminum data. |
| **ALUMINUM_INTEGRATION_CHECKLIST.md** | Step-by-step checklist for adding aluminum to this system: commodities, nodes, assets, data prep, and open questions. Reference for maintenance or similar builds. |

### Data

| Path | Description |
|------|-------------|
| **data/aluminum_demand/aluminum_capacity_by_province.csv** | Existing primary aluminum capacity by Chinese province (used for `existing_capacity` in smelting assets). |
| **data/aluminum_demand/aluminum_demand_by_province.csv** | Aluminum demand by province, year, and scenario. |
| **data/aluminum_demand/aluminum_demand_all_scenarios.json** | Aggregated demand by scenario and year (used by the generator script; “mid” scenario and period–year mapping as in the script). |

### Generator script

| File | Description |
|------|-------------|
| **generate_aluminum_inputs.py** | Python script that updates/creates aluminum-related inputs: adds commodities (Aluminum, Alumina, AluminumScrap, Bauxite, Graphite), updates **system/nodes_1.json** … **nodes_7.json** with aluminum demand and resource nodes, and writes **aluminumsmelting.json**, **aluminumrefining.json**, and **aluminaplant.json** in **assets/assets_1/** … **assets_7/**. Run from the example folder: `python generate_aluminum_inputs.py`. |

### System configuration (updated by script)

- **system/commodities.json** — Adds: Aluminum, Alumina, AluminumScrap, Bauxite, Graphite.
- **system/nodes_1.json** … **system/nodes_7.json** — One Aluminum demand node, one Alumina node, and AluminumScrap/Bauxite/Graphite resource nodes per province (per period).
- **system/time_data.json** — Updated with time-step settings for the new commodities when the script is run.

### Asset files (created by script, 3 per period × 7 periods = 21 files)

| Asset file | Folder | Description |
|------------|--------|-------------|
| **aluminumsmelting.json** | assets_1/ … assets_7/ | Aluminum smelting assets per province; `existing_capacity` from capacity CSV; edges to electricity, aluminum_produced, alumina_produced, graphite sources. |
| **aluminumrefining.json** | assets_1/ … assets_7/ | Secondary aluminum (refining) per province; scrap input from aluminumscrap_source nodes. |
| **aluminaplant.json** | assets_1/ … assets_7/ | Alumina plants per province; bauxite and natural gas inputs; output to alumina_produced. |

---

## Quick start

1. From this folder, run:  
   `python generate_aluminum_inputs.py`  
   to (re)generate aluminum commodities, nodes, and asset JSONs from the CSV/JSON data.
2. Run the MacroEnergy model as usual (e.g. `run.jl` or your chosen entry point).

For province naming and mapping details, see **PROVINCE_MAPPING.md**. For integration steps and references, see **ALUMINUM_INTEGRATION_CHECKLIST.md**.
