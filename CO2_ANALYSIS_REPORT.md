# CO2 Transportation & Storage Analysis Report
## Results_004: 25% Emissions Reduction Case

**Analysis Date:** April 29, 2026  
**Case:** 31 provinces, 1 period, 5-year horizon  
**Emissions Reduction Target:** ~25%

---

## Executive Summary

### 🔴 **CRITICAL FINDING: CO2 TRANSPORT & STORAGE ARE NOT FUNCTIONING**

The CO2 transportation and storage infrastructure you added is **completely unused**:
- **CO2 Pipeline flows: 0 Mt** (entire 5-year period)
- **CO2 Injection into storage: 0 Mt**
- **CO2 Captured by CCS technologies: 0 Mt**
- **CO2 Stored: 0 Mt**

**This is NOT a price problem** – the system does value CO2 capture (shadow prices of -$1,130 to -$1,170/Mt), indicating it would *like* to capture CO2. **This is a capacity/configuration problem** – there is NO CO2 capture capacity actually in the system.

---

## Detailed Findings

### 1. **CO2 Pipeline Transport: UNUSED**

**Data:**
- Total pipeline flow across all regions: **0 Mt**
- Pipeline edges defined: 31 (one per region)
- Status: All show zero flow in every time period

**Interpretation:**
The pipeline infrastructure is configured but not utilized. Possible reasons:
- No CO2 sources are capturing CO2 to send to the pipelines
- Pipeline capacity may be zero
- Cost of using pipelines exceeds benefits (unlikely given negative shadow prices)

### 2. **CO2 Injection & Storage: UNUSED**

**Data:**
- Total CO2 injected into storage: **0 Mt**
- Total CO2 stored: **0 Mt**
- Storage edges defined: 62 (31 regions × 2 edges per region for captured + storage)
- Status: All show zero storage activity

**Interpretation:**
Same as pipelines – the storage infrastructure exists but no CO2 is being captured to store.

### 3. **CO2 Capture: COMPLETELY ABSENT**

**Data:**
- Total CO2 captured by CCS: **0 Mt**
- CCS technologies defined: Multiple (cement/steel with CCS options, DRI+CCS, etc.)
- Total CO2 emissions (unabated): **~57 billion Mt**
- Percent of emissions being captured: **0%**

**This is the root cause** – No CO2 is being captured, so there's nothing to transport or store.

### 4. **CO2 Price Signals: PRESENT & VALUABLE** ✓

**Data:**
- CO2 captured shadow price (balance duals): **-$1,130 to -$1,170/Mt**
- Price signal uniformity: Yes, fairly consistent across regions
- Interpretation: Negative value means the system sees CO2 capture as valuable (worth paying for)

**Why this matters:**
If the model were *choosing* not to capture CO2, we'd see zero price (or positive prices reflecting costs). The negative prices tell us:
> "The model WANTS to capture CO2 for $1,130-1,170/Mt value, but something is PREVENTING it"

---

## Why Is CO2 Capture Not Happening?

### ❌ **Hypothesis 1: No CCS Capacity Installed**
**Most Likely**

The system may not have:
- CCS retrofit capacity for existing plants
- New CCS capacity allowed in the optimization
- Initial capacity of zero for all CCS technologies

**Check:**
```
system/nodes_1.json → Look for CO2 capture node capacities
assets/assets_1 → Check CCS component definitions and starting capacities
```

### ❌ **Hypothesis 2: CCS Costs Exceed System-Wide Benefit**
**Less Likely** (given the negative shadow prices)

If this were true, we'd see positive shadow prices. The negative prices contradict this.

### ❌ **Hypothesis 3: Model Configuration Error**  
**Possible**

- CO2 captured edges not properly connected to storage/transportation nodes
- CCS technologies disabled in configuration
- CO2 commodity not properly defined in system

---

## How Are Emissions Being Reduced (25%)?

Since CO2 capture is zero, the 25% reduction must come from:

1. **Fuel switching** (e.g., fossil fuels → renewables/nuclear)
2. **Efficiency improvements** (using less primary energy)
3. **Demand reduction** (if demand is flexible)
4. **Electrification** (replacing fossil fuels with electric alternatives)

The system is meeting the CO2 constraint through these mechanisms rather than through CCS + storage.

---

## Recommendations

### ✅ **Immediate Actions:**

1. **Verify CCS Capacity Configuration**
   ```
   Check: assets_1/CO2_Capture_* definitions
   Verify: Initial capacity > 0 for CCS technologies
   Confirm: Retrofit and new build capacities are allowed
   ```

2. **Check CO2 Capture Node Connectivity**
   - Ensure CO2 captured edge is properly connected
   - Verify CO2 commodity flows from capture → pipeline/storage
   - Confirm no missing links in the network

3. **Validate Node Definitions**
   - Check `system/nodes_1.json` for CO2 capture node configuration
   - Ensure CO2 capture nodes are NOT disabled
   - Verify shadow/captured commodity definitions

4. **Test with Forced CCS**
   - Run a sensitivity case where CO2 pipeline flow is required
   - This will show if the issue is economic (costs) or structural (capacity/connectivity)

### 📋 **Diagnostics to Run:**

**A. Check for CCS Capacity:**
```julia
# In Julia script, check if any CCS capacity exists
function check_ccs_capacity(case)
    for asset in case.assets
        if contains(asset.name, "CCS") || contains(asset.name, "capture")
            println("$(asset.name): capacity = $(asset.capacity)")
        end
    end
end
```

**B. Verify Network Connectivity:**
```julia
# Check if CO2 commodity flows are properly connected
for node in case.nodes
    if contains(node.name, "CO2")
        println("Node: $(node.name)")
        for (name, dict) in node.outputs
            println("  Output: $name")
        end
    end
end
```

**C. Run Shadow Price Analysis:**
```julia
# The negative CO2 captured duals already tell us a lot:
# Multiply by total potential CO2 → this is system's valuation of CCS
co2_value = abs(dual_co2_captured) * total_emissions_potential
# If this exceeds zero, CCS should be economical
```

---

## **CONCLUSION**

### **Status: CO2 System NOT FUNCTIONING PROPERLY** ❌

The CO2 transportation and storage infrastructure is *defined* but:
- **Not being used** (zero flows)
- **Has no CO2 sources** (no capture)
- **Model values CO2 capture** (negative shadow prices suggest +$1,130/Mt benefit)

### **Root Cause Hypothesis: NO CCS CAPACITY**

Most likely, your CCS technologies (`oxyfuel_cement`, `bfbofccs`, `drieaf+CCS`, etc.) have **zero initial capacity** or are not properly configured in the assets file.

### **Next Step:**
Check your `assets_1` directory for CCS components and verify they have non-zero capacity. If capacities are zero, either:
1. Add them manually in the assets definition
2. Ensure `new_capacity` is allowed in optimization (may need to check macro_settings.json)
3. Verify the CO2 captured nodes are connected to pipelines and injection points

---

## **Data Files Generated**
- `/Users/al3792/Documents_Local/MacroEnergy.jl/CO2_Results_Analysis.ipynb` - Interactive analysis notebook
- `/Users/al3792/Documents_Local/MacroEnergy.jl/CO2_ANALYSIS_REPORT.md` - This report

