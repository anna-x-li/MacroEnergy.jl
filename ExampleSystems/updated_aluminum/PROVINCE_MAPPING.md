# Province Name Mapping Reference

## Data File Province Names → Node System Node Names

| Province name in data | Node name in system | Node ID format | Has capacity | Capacity (t Al/s) |
|----------------------|---------------------|----------------|--------------|------------------|
| Anhui | Region12Anhui | elec_Region12Anhui | ✅ | 0.05120898401826484 |
| Chongqing | Region22Chongqing | elec_Region22Chongqing | ✅ | 0.01191494149543379 |
| Fujian | Region13Fujian | elec_Region13Fujian | ✅ | 0.019812835331050226 |
| Gansu | Region28Gansu | elec_Region28Gansu | ✅ | 0.0951675399543379 |
| Guangdong | Region19Guangdong | elec_Region19Guangdong | ✅ | 0.013000630707762558 |
| Guangxi | Region20Guangxi | elec_Region20Guangxi | ✅ | 0.09779885416666667 |
| Guizhou | Region24Guizhou | elec_Region24Guizhou | ✅ | 0.037187805365296804 |
| Hebei | Region3Hebei | elec_Region3Hebei | ✅ | 0.001642351598173516 |
| Heilongjiang | Region8Heilongjiang | elec_Region8Heilongjiang | ✅ | 0.004786900684931507 |
| Henan | Region16Henan | elec_Region16Henan | ✅ | 0.09442137557077626 |
| Hubei | Region17Hubei | elec_Region17Hubei | ✅ | 0.023077798230593607 |
| Hunan | Region18Hunan | elec_Region18Hunan | ✅ | 0.03915981164383562 |
| InnerMongolia | Region5Innermongolia | elec_Region5Innermongolia | ✅ | 0.16037204052511414 |
| Jiangsu | Region10Jiangsu | elec_Region10Jiangsu | ✅ | 0.018573176369863015 |
| Jiangxi | Region14Jiangxi | elec_Region14Jiangxi | ✅ | 0.05098987157534247 |
| Jilin | Region7Jilin | elec_Region7Jilin | ✅ | 0.0026293407534246577 |
| Liaoning | Region6Liaoning | elec_Region6Liaoning | ✅ | 0.017880308219178083 |
| Ningxia | Region30Ningxia | elec_Region30Ningxia | ✅ | 0.028814182363013696 |
| Qinghai | Region29Qinghai | elec_Region29Qinghai | ✅ | 0.05904568350456621 |
| Shaanxi | Region27Shaanxi | elec_Region27Shaanxi | ✅ | 0.03934536529680365 |
| Shandong | Region15Shandong | elec_Region15Shandong | ✅ | 0.16708357163242007 |
| Shanxi | Region4Shanxi | elec_Region4Shanxi | ✅ | 0.02944585616438356 |
| Sichuan | Region23Sichuan | elec_Region23Sichuan | ✅ | 0.03364253710045662 |
| Tibet | Region26Tibet | elec_Region26Tibet | ✅ | 8.290525114155251e-05 |
| Xinjiang | Region31Xinjiang | elec_Region31Xinjiang | ✅ | 0.16993992009132422 |
| Yunnan | Region25Yunnan | elec_Region25Yunnan | ✅ | 0.14626005850456622 |
| Zhejiang | Region11Zhejiang | elec_Region11Zhejiang | ✅ | 0.013655991723744293 |

## Important Notes

### 1. Case differences
- **Data files**: `InnerMongolia` (camelCase)
- **Node system**: `Innermongolia` (all lowercase)
- **Handling**: Use `Innermongolia` when creating node IDs

### 2. Nodes in system but not in data
The following nodes exist in the system but have no entries in the aluminum data files:
- Region1Beijing (Beijing)
- Region2Tianjin (Tianjin)
- Region9Shanghai (Shanghai)
- Region21Hainan (Hainan)

**Handling**: Include these nodes in aluminum sector inputs; set smelter `existing_capacity = 0` and assign `AluminumScrap` upper bound based on the demand-share rule (typically 0 if the province is absent from the demand CSV).

### 3. Node ID naming rules
When creating aluminum-related nodes, use these formats:
- `aluminum_smelting_Region{number}{province_name}`
- `aluminum_refining_Region{number}{province_name}`
- `alumina_plant_Region{number}{province_name}`
- `aluminumscrap_source_Region{number}{province_name}`
- `bauxite_source_Region{number}{province_name}`
- `graphite_source_Region{number}{province_name}`

**Examples**:
- Shandong: `aluminum_smelting_Region15Shandong`
- Inner Mongolia: `aluminum_smelting_Region5Innermongolia` (note: use Innermongolia)

### 4. Capacity thresholds
- Minimum capacity: Tibet has only 8.29e-05 t Al/s (very small)
- Maximum capacity: Xinjiang has 0.1699 t Al/s
- **Suggestion**: Consider a minimum threshold; provinces below it may skip asset creation

## Quick reference: region numbers

| Region # | Province (in nodes) | Province (in data) | Match |
|----------|---------------------|--------------------|-------|
| Region1 | Beijing | - | ❌ No data |
| Region2 | Tianjin | - | ❌ No data |
| Region3 | Hebei | Hebei | ✅ |
| Region4 | Shanxi | Shanxi | ✅ |
| Region5 | Innermongolia | InnerMongolia | ✅ (note case) |
| Region6 | Liaoning | Liaoning | ✅ |
| Region7 | Jilin | Jilin | ✅ |
| Region8 | Heilongjiang | Heilongjiang | ✅ |
| Region9 | Shanghai | - | ❌ No data |
| Region10 | Jiangsu | Jiangsu | ✅ |
| Region11 | Zhejiang | Zhejiang | ✅ |
| Region12 | Anhui | Anhui | ✅ |
| Region13 | Fujian | Fujian | ✅ |
| Region14 | Jiangxi | Jiangxi | ✅ |
| Region15 | Shandong | Shandong | ✅ |
| Region16 | Henan | Henan | ✅ |
| Region17 | Hubei | Hubei | ✅ |
| Region18 | Hunan | Hunan | ✅ |
| Region19 | Guangdong | Guangdong | ✅ |
| Region20 | Guangxi | Guangxi | ✅ |
| Region21 | Hainan | - | ❌ No data |
| Region22 | Chongqing | Chongqing | ✅ |
| Region23 | Sichuan | Sichuan | ✅ |
| Region24 | Guizhou | Guizhou | ✅ |
| Region25 | Yunnan | Yunnan | ✅ |
| Region26 | Tibet | Tibet | ✅ |
| Region27 | Shaanxi | Shaanxi | ✅ |
| Region28 | Gansu | Gansu | ✅ |
| Region29 | Qinghai | Qinghai | ✅ |
| Region30 | Ningxia | Ningxia | ✅ |
| Region31 | Xinjiang | Xinjiang | ✅ |

**Total**: 28 provinces have data; 27 provinces are used for aluminum assets (Tibet has very small capacity and may be excluded).
