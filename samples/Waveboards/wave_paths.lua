WAVE_PATHS = {}

local TAU = WAVE_COMMON.TAU
local sin = math.sin
local cos = math.cos
local exp = math.exp

local function angle_to_dir(angle_deg)
    local a = math.rad(angle_deg or 0.0)
    return cos(a), sin(a)
end

local function point_line_distance(x, y, px, py, dx, dy)
    local rx = x - px
    local ry = y - py
    return rx * (-dy) + ry * dx
end

local function point_line_along(x, y, px, py, dx, dy)
    local rx = x - px
    local ry = y - py
    return rx * dx + ry * dy
end

local function feature_defaults(feature)
    feature.profile_name = feature.profile_name or "soft_wave"
    feature.angle_deg = feature.angle_deg or 0.0
    feature.amplitude = feature.amplitude or 100
    feature.width = feature.width or 12
    feature.frequency = feature.frequency or 2.0
    feature.phase = feature.phase or 0.0
    feature.center_u = feature.center_u or 50
    feature.center_v = feature.center_v or 50
    feature.size_u = feature.size_u or 20
    feature.size_v = feature.size_v or feature.size_u
    feature.path_mode = feature.path_mode or "global"
    feature.shift_amp = feature.shift_amp or 0.0
    feature.width_var = feature.width_var or 0.0
    feature.amp_var = feature.amp_var or 0.0
    return feature
end

local function local_coords_planar(u, v, feature)
    local dx, dy = angle_to_dir(feature.angle_deg)
    local cu = feature.center_u / 100
    local cv = feature.center_v / 100
    local s = point_line_along(u, v, cu, cv, dx, dy)
    local t = point_line_distance(u, v, cu, cv, dx, dy)
    return s, t
end

local function local_coords_cylinder(u, v, feature)
    local a = math.rad(feature.angle_deg or 0.0)
    local du = u - feature.center_u / 100
    local dv = WAVE_COMMON.wrap_delta(v - feature.center_v / 100)
    local s = du * cos(a) + dv * sin(a)
    local t = -du * sin(a) + dv * cos(a)
    return s, t
end
local function path_envelope(feature, s, t)
    local su = math.max((feature.size_u or 20) / 100, 1e-6)
    local sv = math.max((feature.size_v or feature.size_u or 20) / 100, 1e-6)

    if feature.path_mode == "packet" then
        return exp(-0.5 * (s * s) / (su * su)) * exp(-0.5 * (t * t) / (sv * sv))
    elseif feature.path_mode == "drop" then
        local r2 = (s * s) / (su * su) + (t * t) / (sv * sv)
        return exp(-0.5 * r2)
    end

    return 1.0
end

local function eval_feature(feature, u, v, cylindrical)
    feature = feature_defaults(feature)

    local s, t
    if cylindrical then
        s, t = local_coords_cylinder(u, v, feature)
    else
        s, t = local_coords_planar(u, v, feature)
    end

    local omega = TAU * (feature.frequency or 2.0) * s + (feature.phase or 0.0) / 100 * TAU
    local env = path_envelope(feature, s, t)

    local amp = (feature.amplitude or 100) * env * (1.0 + (feature.amp_var or 0.0) / 100 * sin(omega))
    local width = math.max((feature.width or 12) / 100 * (1.0 + (feature.width_var or 0.0) / 100 * sin(omega)), 1e-6)

    if feature.path_mode == "drop" then
        local rs = s
        local rt = t
        local d = math.sqrt(rs * rs + rt * rt)
        return WAVE_PROFILES.eval(feature.profile_name, d, width, amp, d)
    end

    local center_shift = (feature.shift_amp or 0.0) / 100 * sin(omega)
    local d = t - center_shift

    return WAVE_PROFILES.eval(feature.profile_name, d, width, amp, s)
end

function WAVE_PATHS.eval_features(u, v, cfg, cylindrical)
    local total = 0.0
    local features = cfg.features or {}
    for i = 1, #features do
        total = total + eval_feature(features[i], u, v, cylindrical)
    end
    return total
end
