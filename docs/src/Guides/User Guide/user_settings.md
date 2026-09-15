# Configuring Settings

Macro provides various settings that allow the user to customize model runs and control specific features.

These are the steps to configure settings:

1. Create a new settings JSON file (e.g., `macro_settings.json`) in the preferred location (we recommend creating a `settings` folder in the case directory).
2. Customize the JSON file to enable or disable features as needed.
3. Add the path to the settings JSON file in the `system_data.json` file. The user can use either a relative path (from the `system_data.json` location) or an absolute path.

!!! note "system_data.json"
    For more information about the `system_data.json` file, please see the [Inputs](@ref) section.

Here's an example of a `macro_settings.json` file:

```json
{
    "ConstraintScaling": true,
    "AllowImplicitTopLevelCommodities": true,
    "OverwriteResults": true,
    "AutoCreateNodes": true,
    "OutputLayout": {
        "Capacity": "wide",
        "Costs": "long",
        "Flow": "long"
  }
}
```

If the user created the `macro_settings.json` file in a `settings` folder, the `system_data.json` file should include this entry:

```json
{
    "settings": {
        "path": "settings/macro_settings.json"
    }
}
```

In this example, the user has enabled:
- scaling the constraints in the model during the optimization.
- allowing unknown plain commodity names to be created automatically as top-level commodities.
- overwriting the results folder if it already exists.
- creating nodes automatically from locations.
- setting the layout for the results files to "wide" for the capacity variables, and to "long" for costs and flow variables.

For a complete list of available settings, their default values, and detailed descriptions, please refer to the [Inputs](@ref) section.


## Parallel MGA

Set `Parallel` and `Workers` inside `MGA` in `settings/macro_settings.json`:

```json
"MGA": {
    "Enabled": true,
    "Epsilon": 0.1,
    "MGAAlgorithm": "RandomVector",
    "NumIterations": 50,
    "Groupings": ["location", "technology"],
    "Quantity": "capacity",
    "Parallel": true,
    "Workers": 4
}
```

Use `"Parallel": false` for serial execution (the default). `Workers` defaults
to 1 and limits concurrent individual solves. Each minimum and maximum can run
on a separate worker. `MGAAlgorithm` selects the objectives:

- `"RandomVector"` (default): `NumIterations` random vectors, each minimized and
  maximized with the same weights, for `2 * NumIterations` solves.
- `"VariableMinMax"`: each MGA group minimized and maximized once, for twice the
  number of groups in solves. `NumIterations` is ignored. Outputs append
  `_group_<index>` to the iteration directory; `mga_summary.csv` identifies the
  group and planning period.

New algorithms can subtype `MacroEnergy.MGASolutionAlgorithm` and implement
`MacroEnergy.mga_jobs`; string settings also require a corresponding mapping in
`mga_solution_algorithm`. Both execution modes consume the same jobs.

`run_case` reads these settings automatically. When calling `run_mga` directly,
provide `case_path` in parallel mode:

```julia
run_mga(case, model, output_path; case_path=case_directory)
```

Parallel MGA reuses Benders' process startup, including SLURM detection. The
main process makes one solver-free copy of the existing case and model,
including remapped JuMP references, and sends it once to each active worker.
Each worker starts taking jobs from a shared queue as soon as its initialization
finishes, without waiting for other workers. Summaries retain the original job order.
Workers attach their own solver and reuse the received model across jobs;
they do not reload inputs, regenerate the MACRO model, or repeat the least-cost
solve. In-memory case and mathematical model changes are included in the copy.
Solver state, custom solver environments, optimize hooks, and model extension
data are not transferred. Each worker still needs time and memory to receive
the model and initialize its solver; the main process also holds the copy.

`case_path` is used to load user additions during worker startup. All workers
need access to the same project, user additions, and
output directory. Set solver thread counts through the usual
`optimizer_attributes` to match the allocated CPUs, and budget memory for one
full model per active worker. The existing SLURM launcher may start all allocated
tasks, but only up to `Workers` participate in MGA. The existing LSF launcher
uses local `addprocs`; multi-node LSF support is not provided by this change.

Iteration output paths are the same as serial MGA. Parallel execution leaves
the returned main-process model at the least-cost solution; serial execution
leaves it at the final MGA solution. Random coefficients are generated on the
main process, so a fixed RNG seed selects the same objectives regardless of
worker scheduling, although degenerate optimal portfolios can differ.

For a local integration check, run `julia --project test/test_mga_parallel.jl`.
