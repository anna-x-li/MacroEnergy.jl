# CO2 Balance Constraint Configuration Issue - DIAGNOSIS

## Executive Summary
**Root Cause Found**: The `CO2Captured` nodes are configured with `"BalanceConstraint": true`, which forces **immediate discharge** of all captured CO2. This creates an infeasibility pressure that discourages capture, explaining why zero CO2 capture occurs despite the system valuing it (shadow price: -$1,130/Mt).

---

## How Balance Constraints Work in MacroEnergy.jl

### BalanceConstraint=true
When `"BalanceConstraint": true` is set on a node:
- A balance equation is **enforced**: `inflows = outflows + demand`
- All flows in and out of the node must balance in every timestep
- **There is no accumulation allowed** - inputs must equal outputs (plus demand)

### BalanceConstraint=false
When `"BalanceConstraint": false` is set on a node:
- **No balance equation** is added to the model
- The node can accumulate material over time
- Only flow bounds and capacity constraints apply
- Material can be held locally or transported according to economics

### Implementation Details
From `src/load_inputs/process_data.jl`:
```julia
function check_and_convert_constraints!(data::AbstractDict{Symbol,Any})
    for (name, flag) in data[:constraints]
        if flag == true
            push!(constraints, BalanceConstraint())  # Added to model
        end
    end
    data[:constraints] = constraints
end
```

A `BalanceConstraint=false` means the constraint object is **NOT instantiated**, so no balance equation is created.

---

## Current CO2 System Configuration

### nodes_1.json Current Settings:

**co2_sink** (line 922):
```json
{
  "type": "CO2",
  "instance_data": [{
    "id": "co2_sink",
    "constraints": {
      "CO2CapConstraint": true,
      "BalanceConstraint": false  ← No balance equation
    },
    "rhs_policy": {
      "CO2CapConstraint": 2e8  // 200 Mt/year cap
    }
  }]
}
```

**co2_captured_Region[X]** nodes (line 2444):
```json
{
  "type": "CO2Captured",
  "global_data": {
    "constraints": {
      "BalanceConstraint": true  ← ENFORCED balance equation
    }
  },
  "instance_data": [
    { "id": "co2_captured_Region1Beijing", "location": "Region1Beijing" },
    // ... 30 more regions
  ]
}
```

---

## The Problem: Forced Discharge Flow

### System Flow with Current Configuration:

```
CCS Asset (e.g., Cement Plant)
    ↓ produces CO2Captured commodity
    ↓
co2_captured_Region[X] Node
    ├─ BalanceConstraint=true
    ├─ Balance Eq: captured_CO2_in = pipeline_outflow + demand
    └─ Since demand=0: captured_CO2_in = pipeline_outflow (FORCED)
    ↓ MUST flow out
CO2 Pipeline (with transport cost, capacity)
    ↓
co2_sink Node
    ├─ BalanceConstraint=false (no balance equation)
    ├─ CO2CapConstraint=true (enforces cap)
    └─ Can accumulate without limit (subject to cap)
```

### Why This Prevents Capture:

1. **The Constraint Creates Infeasibility Pressure**:
   - If CCS asset captures CO2 → it MUST flow into co2_captured node
   - co2_captured node balance equation FORCES it out through pipeline
   - But pipeline has cost and capacity constraints
   - System prefers to **NOT capture** rather than be forced to pay transport costs

2. **Mathematical Mechanism**:
   - Without balance constraint: captured CO2 can sit at node with zero cost
   - With balance constraint: captured CO2 MUST flow out (pays pipeline cost)
   - Optimizer chooses: no capture > capture & forced transport > capture

3. **Why Shadow Prices Still Show Value**:
   - Shadow price of -$1,130/Mt shows "IF we forced capture, value would be this"
   - But the system avoids it because the balance constraint forces unwanted costs
   - It's like asking "how much would you pay for this?" → "I'd accept $1,130 loss"
   - But why pay that loss? Answer: the forced discharge constraint

---

## Diagnosis: Configuration vs. Physics

### What the Config Currently Says:
- CO2Captured is an **intermediate flowing commodity** (BalanceConstraint=true)
- Like Hydrogen, Graphite, DRI - stuff that flows through transformations
- "Process this immediately, can't hold it"

### What the Physics Actually Needs:
- CO2Captured is a **storage-capable commodity**
- It's produced by CCS, can be:
  - Transported via pipeline to storage/utilization
  - **Held locally** waiting for economic opportunity
  - Subject to pipeline capacity and economics, not forced flow

### Comparison to Other Intermediate Nodes:

| Node Type | BalanceConstraint | Physical Meaning |
|-----------|-------------------|------------------|
| Hydrogen | true | Flows through electrolysis → power gen |
| Graphite | true | Flows through anode production → battery |
| DRI | true | Flows through steel conversion → products |
| Alumina | true | Flows through reduction → aluminum |
| **CO2Captured** | **true** | ❌ **WRONG** - Should accumulate like storage |
| CO2 (sink) | false | Can accumulate under cap (correct) |

---

## Solution: Change CO2Captured Balance Constraint

### Recommended Fix:

Change in `nodes_1.json` (line ~2448):
```json
{
  "type": "CO2Captured",
  "global_data": {
    "constraints": {
      "BalanceConstraint": false  ← CHANGE FROM: true
    }
  },
  "instance_data": [...]
}
```

### Why This Fixes It:

1. **Allows Capture Without Forced Transport**:
   - CCS asset captures CO2 → flows to co2_captured node
   - CO2Captured node has no balance constraint → can accumulate
   - CO2 can sit locally at zero additional cost

2. **Economics-Driven Transport**:
   - Pipeline flow determined by economics, not constraints
   - If transport cost < shadow price value, CO2 flows
   - If capacity is expensive, optimizer reduces capture
   - **Optimization** determines optimal system, not forced flow

3. **Allows Storage Flexibility**:
   - CO2 can be held at capture point
   - Transported when economically justified
   - System can optimize capture + transport + storage together

4. **Matches System Design**:
   - CO2Captured is the **source** of transported CO2 (like fuel nodes)
   - Should behave like fuel source nodes (BalanceConstraint=false)
   - Compare: hydro_source(false), coal_source(false), CO2Captured(should be false)

---

## Verification Plan

After making the change:

1. **Re-run case**: `run_case()` on results_004 configuration
2. **Check for CO2 capture**: Should see non-zero flows from CCS assets
3. **Verify shadow prices**: Should become zero (or near-zero) when constraint is satisfied
4. **Check pipeline flows**: CO2 should flow based on economics
5. **Validate costs**: Total costs should decrease (no forced transport)

Expected results:
- CO2 captured: likely substantial (given 25% reduction target)
- CO2 transported: significant to CO2 sink
- System cost: decreased vs. current (no forced pipeline costs)
- Emissions: ≤ 25% of baseline

---

## Code Reference

**File**: `/Users/al3792/Documents_Local/MacroEnergy.jl/ExampleSystems/31_provinces_1_period_updatedelec_steel_cement_aluminum_288/system/nodes_1.json`

**Location**: Line 2448 (in "CO2Captured" global_data section)

**Current**:
```json
"constraints": {
  "BalanceConstraint": true
}
```

**Proposed**:
```json
"constraints": {
  "BalanceConstraint": false
}
```

---

## Impact Assessment

| Aspect | Current | After Fix |
|--------|---------|-----------|
| CO2 capture | 0 Mt | Expected: 100+ Mt |
| Pipeline flows | 0 | Expected: 100+ Mt |
| System cost | Higher (inefficient) | Lower (optimized) |
| Emissions reduction | 25% (fuel switching only) | 25% (+ CCS contribution) |
| Model feasibility | ✓ (but economically warped) | ✓ (true optimization) |

---

## Next Steps

1. **Make the change** to nodes_1.json (BalanceConstraint: true → false)
2. **Re-run the case** to generate new results
3. **Analyze CO2 flows** in the new results
4. **Verify feasibility** and solution quality
5. **Document findings** in updated analysis report
