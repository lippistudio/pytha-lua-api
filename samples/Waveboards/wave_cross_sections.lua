function generate_cross_sections(cfg, two_sided)
    local as = WAVE_COMMON.build_axis(cfg.a_axis)
    local zs = WAVE_COMMON.build_axis(cfg.z_axis)
    local sx = cfg.scales.x or 1.0
    local sy = cfg.scales.y or 1.0
    local sz = cfg.scales.z or 1.0

    local ar = cfg.a_axis.max - cfg.a_axis.min
    if ar == 0.0 then ar = 1.0 end
    local zr = cfg.z_axis.max - cfg.z_axis.min
    if zr == 0.0 then zr = 1.0 end

    local sections = {}

    for ia = 1, #as do
        local a = as[ia]
        local u = (a - cfg.a_axis.min) / ar
        local front, back = {}, {}

        for iz = 1, #zs do
            local z = zs[iz]
            local v = (z - cfg.z_axis.min) / zr
            local total = WAVE_PATHS.eval_features(u, v, cfg.feature_cfg, false)
            

            if two_sided then
                front[#front + 1] = { a * sx, 2 * sy - total, z * sz }
            else
                front[#front + 1] = { a * sx, 2 * sy , z * sz }
            end
                back[#back + 1] = { a * sx, total, z * sz }
        end

        local section = {}
        for i = 1, #front do section[#section + 1] = front[i] end
        for i = #back, 1, -1 do section[#section + 1] = back[i] end

        section = WAVE_COMMON.ensure_ccw_yz(section)
        sections[#sections + 1] = section
    end

    return sections
end

function generate_parametric_sections(cfg)
    local as = WAVE_COMMON.build_axis(cfg.a_axis)
    local theta_count = math.max(12, math.floor(cfg.segment_count_per_turn + 0.5))

    local sx = cfg.scales.x or 1.0
    local sy = cfg.scales.y or 1.0
    local sz = cfg.scales.z or 1.0

    local ar = cfg.a_axis.max - cfg.a_axis.min
    if ar == 0.0 then ar = 1.0 end

    local sections = {}

    for ia = 1, #as do
        local a = as[ia]
        local u = (a - cfg.a_axis.min) / ar
        local section = {}

        for i = 0, theta_count - 1 do
            local theta = 2.0 * PI * i / theta_count
            local v = theta / (2.0 * PI)
            local radial_mod = WAVE_PATHS.eval_features(u, v, cfg.feature_cfg, true)
            local r = math.max(0.01, (cfg.base_radius or 0.65) + radial_mod)

            section[#section + 1] = {
                a * sx,
                r * math.cos(theta) * sy,
                r * math.sin(theta) * sz
            }
        end

        section = WAVE_COMMON.ensure_ccw_yz(section)
        sections[#sections + 1] = section
    end

    return sections
end

