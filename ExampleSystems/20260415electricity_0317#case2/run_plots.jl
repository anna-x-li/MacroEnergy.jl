using MacroEnergy
using Gurobi
using Dates
using Printf

# ===============================
# Windows API 结构体（必须在顶层）
# ===============================
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

# ===============================
# 读取当前进程 Working Set (MB)
# ===============================
function current_workingset_mb()
    @static if Sys.iswindows()
        pmc = PROCESS_MEMORY_COUNTERS(0,0,0,0,0,0,0,0,0,0)
        pmc.cb = UInt32(sizeof(PROCESS_MEMORY_COUNTERS))

        hproc = ccall(:GetCurrentProcess, Ptr{Cvoid}, ())
        ok = ccall((:GetProcessMemoryInfo, "Psapi.dll"), Int32,
                   (Ptr{Cvoid}, Ref{PROCESS_MEMORY_COUNTERS}, UInt32),
                   hproc, pmc, pmc.cb)

        ok == 0 && return NaN
        return pmc.WorkingSetSize / 1024^2
    else
        return NaN
    end
end

# ===============================
# 后台监控任务
# ===============================
function monitor_memory(dt::Float64, stopflag::Base.RefValue{Bool})
    t0 = time()
    ts = Float64[]
    rss = Float64[]
    while !stopflag[]
        push!(ts, time() - t0)
        push!(rss, current_workingset_mb())
        sleep(dt)
    end
    push!(ts, time() - t0)
    push!(rss, current_workingset_mb())
    return ts, rss
end

# ===============================
# 主程序开始
# ===============================
dt = 1.0  # 每秒采样一次
stopflag = Ref(false)

GC.gc()  # 清理一下，让曲线起点干净

println("Starting memory monitor...")
mem_task = @async monitor_memory(dt, stopflag)

t0_wall = time()

(system, model) = run_case(@__DIR__;
    optimizer=Gurobi.Optimizer,
    optimizer_attributes=("Method" => 4, "Crossover" => 0, "BarConvTol" => 1e-3)
)

t_wall = time() - t0_wall
stopflag[] = true
ts, rss = fetch(mem_task)

@printf("\nRun finished. Wall time = %.2f s\n", t_wall)
@printf("Memory: start=%.1f MB, peak=%.1f MB, end=%.1f MB\n",
        rss[1], maximum(rss), rss[end])

# ===============================
# 保存 CSV
# ===============================
open("macro_memory_trace.csv", "w") do io
    println(io, "t_sec,working_set_mb")
    for (t, m) in zip(ts, rss)
        @printf(io, "%.3f,%.3f\n", t, m)
    end
end
println("Saved CSV.")

# ===============================
# 画图（需要 Plots）
# ===============================
try
    using Plots
    p = plot(ts, rss,
        xlabel="Time (s)",
        ylabel="Working Set (MB)",
        title="MacroEnergy Memory Usage (Windows)",
        legend=false)
    savefig(p, "macro_memory_trace.png")
    println("Saved PNG plot.")
catch
    println("Plots not installed. Install with: ] add Plots")
end
