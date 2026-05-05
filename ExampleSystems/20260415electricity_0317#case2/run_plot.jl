using MacroEnergy
using Gurobi
using Logging
using LoggingExtras
using Dates
using JuMP
using CSV, DataFrames
using Plots

# ====== 关键修复：struct 必须在顶层 ======
if Sys.iswindows()
    struct PROCESS_MEMORY_COUNTERS
        cb::UInt32
        PageFaultCount::UInt32
        PeakWorkingSetSize::UInt64
        WorkingSetSize::UInt64
        QuotaPeakPagedPoolUsage::UInt64
        QuotaPagedPoolUsage::UInt64
        QuotaPeakNonPagedPoolUsage::UInt64
        QuotaNonPagedPoolUsage::UInt64
        PagefileUsage::UInt64
        PeakPagefileUsage::UInt64
    end
end

function working_set_bytes()
    if Sys.iswindows()
        hproc = ccall((:GetCurrentProcess, "kernel32"), Ptr{Cvoid}, ())
        pmc = Ref(PROCESS_MEMORY_COUNTERS(
            UInt32(sizeof(PROCESS_MEMORY_COUNTERS)),
            0, 0, 0, 0, 0, 0, 0, 0, 0
        ))
        ok = ccall((:GetProcessMemoryInfo, "psapi"), Cint,
                   (Ptr{Cvoid}, Ref{PROCESS_MEMORY_COUNTERS}, UInt32),
                   hproc, pmc, UInt32(sizeof(PROCESS_MEMORY_COUNTERS)))
        ok == 0 && return missing
        return Int(pmc[].WorkingSetSize)
    else
        # 非 Windows：兜底（不保证是“随时间序列”，但至少不会报错）
        try
            return Sys.maxrss()
        catch
            return missing
        end
    end
end