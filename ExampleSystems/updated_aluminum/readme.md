# Ver12 China electricity multi-stage (288h × 7 periods) with CO2 cap and CCS

This example is a **31-node** China provincial electricity model with **7 planning periods**, **288-hour** subperiod representation, a **CO2 cap**, and **CCS** (carbon capture and storage). It extends the electricity-only grid with **aluminum sector integration**: primary aluminum demand, smelting, refining, and alumina production are represented at the provincial level.

## Modeling scope note (multi-sector)

This case includes inputs for **primary aluminum smelting**, **secondary aluminum (refining / recycled aluminum)**, and **alumina plants**. In a broader **multi-sector** setting, you can choose to **omit** secondary aluminum and alumina plant modeling because their electricity use is typically **much lower** than primary aluminum smelting. As a result, electricity price is a relatively **minor** operating-cost driver for those facilities compared with electrolysis-based smelting.

For multi-sector decision analysis, the dominant choices are usually around **primary aluminum smelter** location / migration, new build, and operation, where electricity cost is critical.

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
| **data/aluminum_demand/aluminum_sales_mid.csv** | National total aluminum demand trajectory by year (`VALUE`, Mton/year). Used directly for `Aluminum.AggregatedDemandConstraint` after annual→288h conversion. |
| **data/aluminum_demand/aluminum_scrap_mid.csv** | National scrap availability trajectory by year (`VALUE`, Mton/year). Converted to `scrap × 0.7 × 1.05`, then distributed by province as **hourly** `AluminumScrap.max_supply` (t/h). |
| **data/aluminum_demand/aluminum_scrap_share_weights.csv** | Province share weights (`abbr,weight`) used to distribute national scrap availability to provinces. |
| **data/aluminum_demand/aluminum_refining_capacity_by_province.csv** *(optional)* | Existing secondary aluminum (refining) capacity by province (`Capacity_ton_per_h`), used for `AluminumRefining.existing_capacity`. Current provided version allocates national 2025 total 1800 (10kt/year) to provinces using regional assumptions (East 42%, South 22%, Central 16%, North 10%, Southwest 5%, Northwest 3%, Northeast 2%) with within-region weighting by scrap-share weights. |
| **data/aluminum_demand/alumina_plant_production_2025.csv** | 2025 provincial alumina production (`Production_10kt_2025`, 万吨/年). Used as proxy for `AluminaPlant.existing_capacity` after conversion to t/h. |
| **data/aluminum_demand/aluminum_scrap_max_supply_by_province.csv** *(generated)* | Per-period, per-province scrap `max_supply` written by the generator for validation/checking (`MaxSupply_ton_per_h`, plus `ImpliedTotal_288h_tons`). |

### Generator script

| File | Description |
|------|-------------|
| **generate_aluminum_inputs.py** | Python script that updates/creates aluminum-related inputs: adds commodities (Aluminum, Alumina, AluminumScrap, Bauxite, Graphite), updates **system/nodes_1.json** … **nodes_7.json** with aluminum demand and resource nodes, and writes **aluminumsmelting.json**, **aluminumrefining.json**, and **aluminaplant.json** in **assets/assets_1/** … **assets_7/**. Demand is loaded from `aluminum_sales_mid.csv`, then distributed to provinces using `aluminum_scrap_share_weights.csv`. Scrap supply is loaded from `aluminum_scrap_mid.csv`, multiplied by fixed factor `0.7 × 1.05`, and also distributed by `aluminum_scrap_share_weights.csv`. |

### System configuration (updated by script)

- **system/commodities.json** — Adds: Aluminum, Alumina, AluminumScrap, Bauxite, Graphite.
- **system/nodes_1.json** … **system/nodes_7.json** — One Aluminum node (with province-level demand instances), one Alumina node (with province-level balance instances), and AluminumScrap/Bauxite/Graphite resource nodes per province/region (per period; includes Beijing/Tianjin/Shanghai/Hainan with zero capacity/supply if absent in data). `AluminumScrap.max_supply` is populated as **hourly cap (t/h)** from yearly scrap trajectory × conversion factor and province weights.
- **system/time_data.json** — Updated with time-step settings for the new commodities when the script is run.

### Asset files (created by script, 3 per period × 7 periods = 21 files)

| Asset file | Folder | Description |
|------------|--------|-------------|
| **aluminumsmelting.json** | assets_1/ … assets_7/ | Aluminum smelting assets per province; `existing_capacity` from capacity CSV; edges to electricity, aluminum_produced, alumina_produced, graphite sources. |
| **aluminumrefining.json** | assets_1/ … assets_7/ | Secondary aluminum (refining) per province; scrap input from aluminumscrap_source nodes; `existing_capacity` can be loaded from optional refining-capacity CSV. |
| **aluminaplant.json** | assets_1/ … assets_7/ | Alumina plants per province; bauxite and natural gas inputs; output to alumina_produced; `existing_capacity` is loaded from alumina production CSV when provided. |

---

## Quick start

1. From this folder, run:  
   `python generate_aluminum_inputs.py`  
   to (re)generate aluminum commodities, nodes, and asset JSONs from the CSV/JSON data.
2. Optional arguments (examples):
   - `--scrap-share-weights-csv data/aluminum_demand/aluminum_scrap_share_weights.csv`
   - `--refining-capacity-csv data/aluminum_demand/aluminum_refining_capacity_by_province.csv`
   - `--alumina-capacity-csv data/aluminum_demand/alumina_plant_production_2025.csv`
   - `--aluminum-scrap-mid-mton 20` (override CSV scrap trajectory with one constant Mt/year for all periods)
3. Quick checks after generation:
   - `system/nodes_*.json`: `Aluminum` RHS follows `aluminum_sales_mid.csv` period years (2025, 2030, ..., 2055)
   - `system/nodes_*.json`: `AluminumScrap.max_supply` is nonzero and period-specific
   - `data/aluminum_demand/aluminum_scrap_max_supply_by_province.csv`: per-period totals equal annual `scrap×0.7×1.05` converted to 288h tons
   - `assets/assets_*/aluminumrefining.json`: `existing_capacity` matches optional refining-capacity CSV when provided
   - `assets/assets_*/aluminaplant.json`: `existing_capacity` matches alumina production CSV after conversion (10kt/year → t/h)
4. Run the MacroEnergy model as usual (e.g. `run.jl` or your chosen entry point).

## 2025 Raw Material Price Assumptions (current defaults)

The generator now writes `price_supply` for aluminum raw-material source nodes in `system/nodes_*.json` (all in **USD/t**):

- `AluminumScrap` default `price_supply = 2131.94` USD/t (from 15350 RMB/t using assumed FX `7.2 CNY/USD`)
- `Bauxite` default `price_supply = 67.5` USD/t (reference from SMM Guinea-import bauxite quote page)
- `Graphite` (used as prebaked anode proxy in smelting) default `price_supply = 750.00` USD/t (from 5400 RMB/t using assumed FX `7.2 CNY/USD`)

Data sources (2025 reference):

- Scrap aluminum market references: [SMM scrap aluminum portal](https://hq.smm.cn/aluminum/1050)
- Guinea imported bauxite quote reference: [SMM Guinea bauxite quote](https://hq.smm.cn/h5/guinea-bauxite-price)
- Prebaked anode (anode carbon) references:
  - [SMM prebaked anode coverage](https://hq.smm.cn/aluminum/list/446)
  - [Mysteel prebaked anode market page](https://lv.mysteel.com/market/p-293--------------2.html)
  - [Aladdiny prebaked anode weekly](https://www.aladdiny.com/news/article/202512044252400.html)

To override defaults when running the script:

- `--scrap-price <value>`
- `--bauxite-price <value>`
- `--graphite-price <value>`

For province naming and mapping details, see **PROVINCE_MAPPING.md**. For integration steps and references, see **ALUMINUM_INTEGRATION_CHECKLIST.md**.
