using MacroEnergy
using Gurobi
using Printf

@static if Sys.iswindows()
    mutable struct PROCESS_MEMORY_COUNTERS
        cb::UInt32
        PageFaultCount::UInt32
        PeakWorkingSetSize::UInt
        WorkingSetSize::UInt
        QuotaPeakPagedPoolUsage::UInt
        QuotaPagedPoolUsage::UInt
        QuotaPeakNonPagedPoolUsage::UInt
        QuotaNonPagedPoolUsage::UInt
        PagefileUsage::UInt
        PeakPagefileUsage::UInt
    end
end

function proc_memory_mb()
    @static if Sys.iswindows()
        pmc = PROCESS_MEMORY_COUNTERS(0,0,0,0,0,0,0,0,0,0)
        pmc.cb = UInt32(sizeof(PROCESS_MEMORY_COUNTERS))
        hproc = ccall(:GetCurrentProcess, Ptr{Cvoid}, ())
        ok = ccall((:GetProcessMemoryInfo, "Psapi.dll"), Int32,
                   (Ptr{Cvoid}, Ref{PROCESS_MEMORY_COUNTERS}, UInt32),
                   hproc, pmc, pmc.cb)
        ok == 0 && return (NaN, NaN)
        cur  = pmc.WorkingSetSize     / 1024^2
        peak = pmc.PeakWorkingSetSize / 1024^2
        return (cur, peak)
    else
        return (NaN, NaN)
    end
end

# （可选）让起点更“干净”，减少上一次操作残留
GC.gc()

(cur0, peak0) = proc_memory_mb()

t0 = time()
(system, model) = run_case(@__DIR__;
    optimizer=Gurobi.Optimizer,
    optimizer_attributes=("Method" => 4, "Crossover" => 0, "BarConvTol" => 1e-3)
)
t_wall = time() - t0

(cur1, peak1) = proc_memory_mb() 

@printf("Run finished. Wall time = %.2f s\n", t_wall)
@printf("Working Set: start=%.1f MB, end=%.1f MB\n", cur0, cur1)
@printf("Peak Working Set (since process start) = %.1f MB\n", peak1)
