#!/system/bin/sh

# From Celestial Game OPT (By: Kazuyoo)

miui_boost_feature() {
    POWER_MIUI=$(settings get system power_mode)
    if [[ "$POWER_MIUI" == "middle" ]]; then
        setprop debug.power.monitor_tools false

        write system POWER_BALANCED_MODE_OPEN 0
        write system POWER_PERFORMANCE_MODE_OPEN 1
        write system POWER_SAVE_MODE_OPEN 0
        write system power_mode middle
        write system POWER_SAVE_PRE_HIDE_MODE performance
        write system POWER_SAVE_PRE_SYNCHRONIZE_ENABLE 1
    fi
}

bypass_refresh_rate() {
    BBK_BRANDS="oppo vivo oneplus realme iqoo"
    BRAND=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
    FPS=$(dumpsys display | grep -oE 'fps=[0-9]+' | awk -F '=' '{print $2}' | head -n 1)

    if echo "$BBK_BRANDS" | grep -wq "$BRAND"; then
        if [ "$FPS" -le 1 ]; then
            FPS=1
        elif [ "$FPS" -le 2 ]; then
            FPS=2
        elif [ "$FPS" -le 3 ]; then
            FPS=3
        else
            FPS=4
        fi
    fi

    settings put system peak_refresh_rate "$FPS"
    settings put system user_refresh_rate "$FPS"
    settings put system max_refresh_rate "$FPS"
    settings put system min_refresh_rate "$FPS"
}

final_optimization() {
    setprop debug.performance.tuning 1
    setprop debug.sf.hw 1
    setprop debug.egl.hw 1

    CPU_OPTS=""
    for i in $(seq 1 8); do
        CPU_OPTS="${CPU_OPTS}power_check_max_cpu_${i}=0,"
    done
    write_sys global activity_manager_constants "${CPU_OPTS%,}"

    write global activity_starts_logging_enabled 0
    write secure high_priority 1

    cmd stats clear-puller-cache
    cmd display ab-logging-disable
    cmd display dwb-logging-disable
    cmd looper_stats disable
    am memory-factor set CRITICAL

    cmd display set-match-content-frame-rate-pref 2

    cmd power set-adaptive-power-saver-enabled false
    cmd power set-fixed-performance-mode-enabled true

    cmd thermalservice override-status 0

    simpleperf --log fatal --log-to-android-buffer 6

    write global window_animation_scale 0.8
    write global transition_animation_scale 0.8
    write global animator_duration_scale 0.8
}

main() {
    miui_boost_feature
    bypass_refresh_rate
    final_optimization
}

sync && main
