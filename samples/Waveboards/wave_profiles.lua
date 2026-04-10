WAVE_PROFILES = {}

local TAU = WAVE_COMMON.TAU
local PI = math.pi
local cos = math.cos
local sqrt = math.sqrt
local abs = math.abs
local exp = math.exp
local sin = math.sin

local function smoothstep(t)
    if t <= 0.0 then return 0.0 end
    if t >= 1.0 then return 1.0 end
    return t * t * (3.0 - 2.0 * t)
end

local function local_smoothstep(edge0, edge1, x)
    local t = (x - edge0) / (edge1 - edge0)
    t = WAVE_COMMON.clamp(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
end

local function bounded_coord(d, width)
    local x = d / math.max(width or 0.1, 1e-6)
    return x, abs(x)
end

local function periodic_coord(d, width)
    local x = d / math.max(2.0 * (width or 0.1), 1e-6)
    local q = 2.0 * WAVE_COMMON.wrap_delta(x)
    return q, abs(q)
end

function WAVE_PROFILES.eval(profile_name, d, width, depth, aux)
    width = math.max(width or 0.1, 1e-6)
    depth = depth or 0.2
    aux = aux or 0.0

    local x, ax

    if profile_name == "ballnose" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * sqrt(1.0 - x * x)

    elseif profile_name == "ballnose_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * sqrt(1.0 - x * x)

    elseif profile_name == "round_groove" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * (1.0 - ax * ax)

    elseif profile_name == "round_groove_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * (1.0 - ax * ax)

    elseif profile_name == "soft_wave" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -0.5 * depth * (1.0 + cos(PI * x))

    elseif profile_name == "soft_wave_periodic" then
        x, ax = periodic_coord(d, width)
        return -0.5 * depth * (1.0 + cos(PI * x))

    elseif profile_name == "v_cut" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * (1.0 - ax)

    elseif profile_name == "v_cut_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * (1.0 - ax)

    elseif profile_name == "broad_round" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * smoothstep(1.0 - ax)

    elseif profile_name == "broad_round_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * smoothstep(1.0 - ax)

    elseif profile_name == "cloth_fold" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        local t = 1.0 - ax
        return -depth * (0.75 * smoothstep(t) + 0.25 * sin(PI * t))

    elseif profile_name == "cloth_fold_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        local t = 1.0 - ax
        return -depth * (0.75 * smoothstep(t) + 0.25 * sin(PI * t))

    elseif profile_name == "double_bead" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.25 then return 0.0 end
        return -0.65 * depth * exp(-((x - 0.38) * (x - 0.38)) / 0.09)
             - 0.65 * depth * exp(-((x + 0.38) * (x + 0.38)) / 0.09)

    elseif profile_name == "double_bead_periodic" then
        x, ax = periodic_coord(d, width)
        return -0.65 * depth * exp(-((x - 0.38) * (x - 0.38)) / 0.09)
             - 0.65 * depth * exp(-((x + 0.38) * (x + 0.38)) / 0.09)

    elseif profile_name == "dune" then
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        local t = 1.0 - ax
        return -depth * (0.55 * t + 0.45 * t * t)

    elseif profile_name == "dune_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        local t = 1.0 - ax
        return -depth * (0.55 * t + 0.45 * t * t)

    elseif profile_name == "sharp_step" then
        x, ax = bounded_coord(d, width)
        if ax >= 0.5 then return 0.0 end
        return -depth

    elseif profile_name == "sharp_step_periodic" then
        x, ax = periodic_coord(d, width)
        if ax >= 0.5 then return 0.0 end
        return -depth

    elseif profile_name == "smooth_step" then
        x, ax = bounded_coord(d, width)
        local edge = 0.1
        if ax >= 0.5 + edge then return 0.0 end
        if ax <= 0.5 - edge then return -depth end
        return -depth * (1.0 - local_smoothstep(0.5 - edge, 0.5 + edge, ax))

    elseif profile_name == "smooth_step_periodic" then
        x, ax = periodic_coord(d, width)
        local edge = 0.1
        if ax >= 0.5 + edge then return 0.0 end
        if ax <= 0.5 - edge then return -depth end
        return -depth * (1.0 - local_smoothstep(0.5 - edge, 0.5 + edge, ax))
    else
        x, ax = bounded_coord(d, width)
        if ax >= 1.0 then return 0.0 end
        return -depth * sqrt(1.0 - x * x)
    end
end