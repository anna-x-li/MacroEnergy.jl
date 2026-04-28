# Aluminum Integration Checklist

## Overview
Add aluminum to `Ver12_China_elec_multistage_288_7_v1107CO2cap-CO2cap1_CCS` following the approach used in `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum`.

**Key differences**:
- Source system: single node (Region15Shandong)
- Target system: 31 nodes (Chinese provinces)
- Data source: province-level data in `data/aluminum_demand/` (units: t Al/s)

---

## 1. Province name to node name mapping

### Mapping to verify (province name → node name)

| Province name in data | Node name format | Corresponding node ID | Status |
|-----------------------|------------------|------------------------|--------|
| Anhui | Region12Anhui | elec_Region12Anhui | ⚠️ To confirm |
| Chongqing | Region22Chongqing | elec_Region22Chongqing | ⚠️ To confirm |
| Fujian | Region13Fujian | elec_Region13Fujian | ⚠️ To confirm |
| Gansu | Region28Gansu | elec_Region28Gansu | ⚠️ To confirm |
| Guangdong | Region19Guangdong | elec_Region19Guangdong | ⚠️ To confirm |
| Guangxi | Region20Guangxi | elec_Region20Guangxi | ⚠️ To confirm |
| Guizhou | Region24Guizhou | elec_Region24Guizhou | ⚠️ To confirm |
| Hebei | Region3Hebei | elec_Region3Hebei | ⚠️ To confirm |
| Heilongjiang | Region8Heilongjiang | elec_Region8Heilongjiang | ⚠️ To confirm |
| Henan | Region16Henan | elec_Region16Henan | ⚠️ To confirm |
| Hubei | Region17Hubei | elec_Region17Hubei | ⚠️ To confirm |
| Hunan | Region18Hunan | elec_Region18Hunan | ⚠️ To confirm |
| InnerMongolia | Region5Innermongolia | elec_Region5Innermongolia | ⚠️ To confirm (note case) |
| Jiangsu | Region10Jiangsu | elec_Region10Jiangsu | ⚠️ To confirm |
| Jiangxi | Region14Jiangxi | elec_Region14Jiangxi | ⚠️ To confirm |
| Jilin | Region7Jilin | elec_Region7Jilin | ⚠️ To confirm |
| Liaoning | Region6Liaoning | elec_Region6Liaoning | ⚠️ To confirm |
| Ningxia | Region30Ningxia | elec_Region30Ningxia | ⚠️ To confirm |
| Qinghai | Region29Qinghai | elec_Region29Qinghai | ⚠️ To confirm |
| Shaanxi | Region27Shaanxi | elec_Region27Shaanxi | ⚠️ To confirm |
| Shandong | Region15Shandong | elec_Region15Shandong | ⚠️ To confirm |
| Shanxi | Region4Shanxi | elec_Region4Shanxi | ⚠️ To confirm |
| Sichuan | Region23Sichuan | elec_Region23Sichuan | ⚠️ To confirm |
| Tibet | Region26Tibet | elec_Region26Tibet | ⚠️ To confirm |
| Xinjiang | Region31Xinjiang | elec_Region31Xinjiang | ⚠️ To confirm |
| Yunnan | Region25Yunnan | elec_Region25Yunnan | ⚠️ To confirm |
| Zhejiang | Region11Zhejiang | elec_Region11Zhejiang | ⚠️ To confirm |

**Notes**:
- Data covers 28 provinces; the system has 31 nodes (including Beijing, Tianjin, Shanghai, Hainan)
- Confirm which provinces have aluminum capacity/demand and which do not
- InnerMongolia is "InnerMongolia" in data and "Innermongolia" in nodes (case difference)

---

## 2. Files to modify

### 2.1 System configuration

#### 2.1.1 `system/commodities.json`
**Action**: Add new commodity types  
**To add**:
- "Aluminum"
- "Alumina"
- "AluminumScrap"
- "Bauxite"
- "Graphite"

**Current state**: Only Electricity, NaturalGas, Coal, CO2, Uranium

---

#### 2.1.2 `system/nodes_1.json` through `system/nodes_7.json` (7 files)
**Action**: Add new node types for each period

**Node types to add**:

1. **Aluminum nodes** (demand)
   - `id`: "aluminum_produced"
   - `type`: "Aluminum"
   - `time_interval`: "Aluminum"
   - `constraints`: {"AggregatedDemandConstraint": true}
   - `rhs_policy`: {"AggregatedDemandConstraint": <computed from demand data>}
   - Note: demand values are aggregated by period and scenario from `aluminum_demand_by_province.csv`

2. **Alumina nodes** (demand)
   - `id`: "alumina_produced"
   - `type`: "Alumina"
   - `time_interval`: "Alumina"
   - `constraints`: {"AggregatedDemandConstraint": true}
   - `rhs_policy`: {"AggregatedDemandConstraint": 0} (or set from demand)

3. **AluminumScrap nodes** (resource, one per province / region)
   - `type`: "AluminumScrap"
   - `time_interval`: "AluminumScrap"
   - `constraints`: {"BalanceConstraint": true}
   - `instance_data`: one entry per province / region (including Beijing/Tianjin/Shanghai/Hainan with 0 if absent in data)
     - `id`: "aluminumscrap_source_Region{number}{province_name}"
     - `max_supply`: [<from data or default>]
     - `price_supply`: [0]

4. **Bauxite nodes** (resource, one per province / region)
   - `type`: "Bauxite"
   - `time_interval`: "Bauxite"
   - `constraints`: {"BalanceConstraint": true}
   - `instance_data`: one entry per province / region
     - `id`: "bauxite_source_Region{number}{province_name}"
     - `max_supply`: [100000] (or as needed)
     - `price_supply`: [0]

5. **Graphite nodes** (resource, one per province / region)
   - `type`: "Graphite"
   - `time_interval`: "Graphite"
   - `constraints`: {"BalanceConstraint": true}
   - `instance_data`: one entry per province / region
     - `id`: "graphite_source_Region{number}{province_name}"
     - `max_supply`: [100000] (or as needed)
     - `price_supply`: [0]

**Note**: Configure for each period (1–7) separately; demand may differ by period.

---

### 2.2 Asset files (3 files per period)

#### 2.2.1 `assets/assets_1/` through `assets/assets_7/` (7 folders)

Each folder should contain 3 new files:

1. **`aluminumsmelting.json`**
   - Copy `global_data` from single-node system (unchanged)
   - Populate `instance_data` with one instance per province / region (smelter capacity can be 0)
   - Each instance:
     - `id`: "aluminum_smelting_Region{number}{province_name}"
     - `location`: "Region{number}{province_name}"
     - `existing_capacity`: from `aluminum_capacity_by_province.csv`, units: t Al/s
     - `aluminum_constraints`: {"MinFlowConstraint": true}
     - `edges`: connect to corresponding nodes
       - `elec_edge`: to "elec_Region{number}{province_name}"
       - `aluminum_edge`: to "aluminum_produced"
       - `alumina_edge`: from "alumina_produced"
       - `graphite_edge`: from "graphite_source_Region{number}{province_name}"

2. **`aluminumrefining.json`**
   - Copy `global_data` from single-node system
   - Populate `instance_data` with one instance per province / region
   - Each instance:
     - `id`: "aluminum_refining_Region{number}{province_name}"
     - `location`: "Region{number}{province_name}"
     - `existing_capacity`: 0 (or as needed)
     - `edges`: connect to corresponding nodes

3. **`aluminaplant.json`**
   - Copy `global_data` from single-node system
   - Populate `instance_data` with one instance per province with capacity
   - Each instance:
     - `id`: "alumina_plant_Region{number}{province_name}"
     - `location`: "Region{number}{province_name}"
     - `existing_capacity`: 0 (or as needed)
     - `edges`: connect to corresponding nodes
       - `fuel_edge`: to "natgas_Region{number}{province_name}"

---

## 3. Data preparation

### 3.1 Data files to check
- ✅ `data/aluminum_demand/aluminum_capacity_by_province.csv` — exists
- ✅ `data/aluminum_demand/aluminum_demand_by_province.csv` — exists

### 3.2 Data to process
1. **Existing capacity** (`aluminum_capacity_by_province.csv`)
   - Columns: `Province`, `Capacity_10kt_per_year`, `Capacity_tons_per_second`
   - Use `Capacity_tons_per_second` as `existing_capacity`

2. **Demand** (`aluminum_demand_by_province.csv`)
   - Columns: `Province`, `Year`, `Scenario`, `Demand_tons_per_second`
   - Aggregate by period and scenario
   - Period mapping to confirm: Year 2025, 2030, 2035, 2040, 2045, 2050, 2055, 2060 → Period 1–7

---

## 4. Implementation steps

### Step 1: Verify province name mapping
- [ ] Confirm mapping for all 28 provinces (data name ↔ node name)
- [ ] Check InnerMongolia/Innermongolia case
- [ ] Identify provinces with aluminum capacity (from capacity file)
- [ ] Identify provinces with aluminum demand (from demand file)

### Step 2: Update commodities.json
- [ ] Add 5 new commodity types

### Step 3: Update nodes files (7 files)
- [ ] Add Aluminum demand node per period
- [ ] Add Alumina demand node per period
- [ ] Add AluminumScrap resource nodes (one per province with capacity)
- [ ] Add Bauxite resource nodes (one per province with capacity)
- [ ] Add Graphite resource nodes (one per province with capacity)
- [ ] Compute total Aluminum demand per period (from demand file)

### Step 4: Create asset files (21 files = 7 periods × 3 file types)
- [ ] Create `aluminumsmelting.json` per period
  - [ ] Copy global_data
  - [ ] Create instance_data per province with capacity
  - [ ] Set existing_capacity (from capacity file)
- [ ] Create `aluminumrefining.json` per period
- [ ] Create `aluminaplant.json` per period

### Step 5: Validation
- [ ] Verify all JSON files are valid
- [ ] Verify node IDs and edge connections
- [ ] Verify units (t Al/s)
- [ ] Verify period mapping

---

## 5. Notes

1. **Units**: All data use "t Al/s"; use as-is.

2. **Period mapping**:
   - Period 1 → Year 2025?
   - Period 2 → Year 2030?
   - Period 3 → Year 2035?
   - Period 4 → Year 2040?
   - Period 5 → Year 2045?
   - Period 6 → Year 2050?
   - Period 7 → Year 2055 or 2060?
   - **To be confirmed**

3. **Scenario choice**:
   - Demand file has low, mid, high scenarios
   - **To be confirmed which scenario to use**

4. **Province filter**:
   - Create assets only for provinces with capacity or demand
   - Capacity file indicates which provinces have capacity
   - Demand file indicates which provinces have demand

5. **Node naming consistency**:
   - Use the same node ID format everywhere
   - Ensure edges use correct node IDs

---

## 6. Open questions

1. ⚠️ **Period–year mapping**: Which years do Periods 1–7 correspond to?
2. ⚠️ **Scenario**: Use low, mid, or high?
3. ⚠️ **Province mapping**: InnerMongolia vs Innermongolia case
4. ⚠️ **Demand aggregation**: Is total Aluminum demand the sum over all provinces per period, or other?
5. ⚠️ **AluminumScrap supply**: Single-node uses 11; how to set for multi-node?
6. ⚠️ **Alumina demand**: Single-node uses 0; same for multi-node?

---

## 7. Reference files

### Source system (single node)
- `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum/assets/assets_1/aluminumsmelting.json`
- `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum/assets/assets_1/aluminumrefining.json`
- `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum/assets/assets_1/aluminaplant.json`
- `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum/system/commodities.json`
- `China_elec_multistage_288_7_v1107CO2cap_CCS_singleNode_aluminum/system/nodes_1.json`

### Target system (31 nodes)
- `Ver12_China_elec_multistage_288_7_v1107CO2cap-CO2cap1_CCS/data/aluminum_demand/aluminum_capacity_by_province.csv`
- `Ver12_China_elec_multistage_288_7_v1107CO2cap-CO2cap1_CCS/data/aluminum_demand/aluminum_demand_by_province.csv`
- `Ver12_China_elec_multistage_288_7_v1107CO2cap-CO2cap1_CCS/system/nodes_1.json`
