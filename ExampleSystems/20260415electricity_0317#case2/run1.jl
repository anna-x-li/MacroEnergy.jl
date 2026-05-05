using MacroEnergy
using Gurobi
using Dates

# =========================
# 0) 生成 log 文件名（由 PowerShell transcript 写入）
# =========================
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
log_file = joinpath(@__DIR__, "macro_run_log_$timestamp.txt")

# =========================
# 1) Windows：读取进程峰值 Working Set（RSS）——零采样、几乎零开销
# =========================
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

function peak_working_set_bytes()
    if Sys.iswindows()
        hproc = ccall((:GetCurrentProcess, "kernel32"), Ptr{Cvoid}, ())
        pmc = Ref(PROCESS_MEMORY_COUNTERS(UInt32(sizeof(PROCESS_MEMORY_COUNTERS)),
                                          0,0,0,0,0,0,0,0,0))
        ok = ccall((:GetProcessMemoryInfo, "psapi"), Cint,
                   (Ptr{Cvoid}, Ref{PROCESS_MEMORY_COUNTERS}, UInt32),
                   hproc, pmc, UInt32(sizeof(PROCESS_MEMORY_COUNTERS)))
        ok == 0 && return missing
        return Int(pmc[].PeakWorkingSetSize)
    else
        try
            return Sys.maxrss()
        catch
            return missing
        end
    end
end

# =========================
# 2) 正常运行（不改 stdout/stderr，不影响终端打印）
# =========================
println("[Info] Start time: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
println("[Info] Running case at: ", @__DIR__)
println("[Info] Transcript log will be: ", log_file)
println("------------------------------------------------------------")

t0 = time()

(system, model) = run_case(@__DIR__;
    optimizer=Gurobi.Optimizer,
    optimizer_attributes=("Method" => 4, "Crossover" => 0, "BarConvTol" => 1e-3)
)

runtime_s = time() - t0
peak_bytes = peak_working_set_bytes()
peak_gb = peak_bytes === missing ? missing : peak_bytes / 1024^3

println("------------------------------------------------------------")
println("[Info] Finished time: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))

# =========================
# 3) 终端最后一行：只打印 时间 + 峰值内存 + log 路径
# =========================
if peak_gb === missing
    println("Run completed. Runtime(s)=$(round(runtime_s, digits=3)), PeakRSS(GB)=(missing). Log: $log_file")
else
    println("Run completed. Runtime(s)=$(round(runtime_s, digits=3)), PeakRSS(GB)=$(round(peak_gb, digits=3)). Log: $log_file")
end