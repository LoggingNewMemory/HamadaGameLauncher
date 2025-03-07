#!/system/bin/sh

# From Celestial Game OPT (By: Kazuyoo)- Modified Balanced ny: Kanagawa Yamada

reset_miui_power() {
    # Reset MIUI power mode settings
    settings put system power_mode default
    setprop debug.power.monitor_tools true

    # Reset power mode flags (assuming default is balanced mode)
    write system POWER_BALANCED_MODE_OPEN 1
    write system POWER_PERFORMANCE_MODE_OPEN 0
    write system POWER_SAVE_MODE_OPEN 0
    write system POWER_SAVE_PRE_HIDE_MODE balanced
    write system POWER_SAVE_PRE_SYNCHRONIZE_ENABLE 0
}

reset_refresh_rate() {
    # Reset refresh rate settings to system defaults
    settings delete system peak_refresh_rate
    settings delete system user_refresh_rate
    settings delete system max_refresh_rate
    settings delete system min_refresh_rate
}

reset_performance_tuning() {
    # Reset debug performance flags
    setprop debug.performance.tuning 0
    setprop debug.sf.hw 0
    setprop debug.egl.hw 0

    # Reset CPU optimization flags
    write global activity_manager_constants ""

    # Reset animation settings
    write global window_animation_scale 1.0
    write global transition_animation_scale 1.0
    write global animator_duration_scale 1.0

    # Reset power management
    cmd power set-adaptive-power-saver-enabled true
    cmd power set-fixed-performance-mode-enabled false

    # Reset thermal override
    cmd thermalservice override-status -1

    # Re-enable logging and stats
    cmd stats enable-puller-cache
    cmd display ab-logging-enable
    cmd display dwb-logging-enable
    cmd looper_stats enable

    # Reset memory factor
    am memory-factor set NORMAL

    # Reset display frame rate matching
    cmd display set-match-content-frame-rate-pref 0
}

main() {
    reset_miui_power
    reset_refresh_rate
    reset_performance_tuning
}

sync && main
