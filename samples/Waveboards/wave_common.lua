WAVE_COMMON = {}

WAVE_COMMON.TAU = 2.0 * math.pi

local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local abs = math.abs

function WAVE_COMMON.randf(min_v, max_v)
    return min_v + math.random() * (max_v - min_v)
end

function WAVE_COMMON.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function WAVE_COMMON.wrap01(v)
    local x = v - math.floor(v)
    if x < 0.0 then x = x + 1.0 end
    return x
end

function WAVE_COMMON.wrap_delta(v)
    return WAVE_COMMON.wrap01(v + 0.5) - 0.5
end

local function deep_copy(src)
    if type(src) ~= "table" then
        return src
    end

    local dst = {}
    for k, v in pairs(src) do
        dst[k] = deep_copy(v)
    end
    return dst
end



function WAVE_COMMON.copy_table(src)
    return deep_copy(src)
end

function WAVE_COMMON.merge_defaults(defaults, overrides)
    local result = deep_copy(defaults)
    if overrides ~= nil then
        for k, v in pairs(overrides) do
            if type(v) == "table" and type(result[k]) == "table" then
                result[k] = WAVE_COMMON.merge_defaults(result[k], v)
            else
                result[k] = v
            end
        end
    end
    return result
end

local function frange_count(min_v, max_v, count)
    local t = {}
    if count <= 1 then
        t[1] = min_v
        return t
    end
    local step = (max_v - min_v) / (count - 1)
    for i = 0, count - 1 do
        t[#t + 1] = min_v + i * step
    end
    return t
end

local function frange_step(min_v, max_v, step)
    local t = {}
    local v = min_v
    while v <= max_v + 1e-9 do
        t[#t + 1] = v
        v = v + step
    end
    if #t == 0 or abs(t[#t] - max_v) > 1e-9 then
        t[#t + 1] = max_v
    end
    return t
end

function WAVE_COMMON.build_axis(spec)
    if spec.count ~= nil then return frange_count(spec.min, spec.max, spec.count) end
    if spec.step ~= nil then return frange_step(spec.min, spec.max, spec.step) end
    error("axis spec needs either count or step")
end

local function signed_area_yz(poly)
    local area = 0.0
    local n = #poly
    if n < 3 then return 0.0 end
    for i = 1, n do
        local p1 = poly[i]
        local p2 = poly[(i % n) + 1]
        area = area + (p1[2] * p2[3] - p2[2] * p1[3])
    end
    return 0.5 * area
end

local function reverse_polygon(poly)
    local rev = {}
    for i = #poly, 1, -1 do
        rev[#rev + 1] = poly[i]
    end
    return rev
end

function WAVE_COMMON.ensure_ccw_yz(poly)
    if signed_area_yz(poly) < 0.0 then return reverse_polygon(poly) end
    return poly
end

function WAVE_COMMON.collect_bounds(sections)
    local min_x, min_y, min_z, max_x, max_y, max_z = nil, nil, nil, nil, nil, nil
    for i = 1, #sections do
        local sec = sections[i]
        for j = 1, #sec do
            local p = sec[j]
            local x, y, z = p[1], p[2], p[3]
            if min_x == nil or x < min_x then min_x = x end
            if min_y == nil or y < min_y then min_y = y end
            if min_z == nil or z < min_z then min_z = z end
            if max_x == nil or x > max_x then max_x = x end
            if max_y == nil or y > max_y then max_y = y end
            if max_z == nil or z > max_z then max_z = z end
        end
    end
    return {
        min_x = min_x or 0.0, min_y = min_y or 0.0, min_z = min_z or 0.0,
        max_x = max_x or 0.0, max_y = max_y or 0.0, max_z = max_z or 0.0
    }
end

function WAVE_COMMON.transform_point(x, y, z, origin, angle_deg, pivot_x, pivot_y, pivot_z)
    local a = (angle_deg or 0.0) * PI / 180.0
    local ca = cos(a)
    local sa = sin(a)
    local lx = x - pivot_x
    local ly = y - pivot_y
    local lz = z - pivot_z
    local rx = ca * lx - sa * ly
    local ry = sa * lx + ca * ly
    return { origin[1] + rx, origin[2] + ry, origin[3] + lz }
end

function WAVE_COMMON.combo_index_from_value(items, value, default_index)
    for i = 1, #items do
        if items[i] == value then return i end
    end
    return default_index or 1
end

function WAVE_COMMON.combo_value_from_index(items, index, default_value)
    if index ~= nil and items[index] ~= nil then return items[index] end
    return default_value or items[1]
end

function WAVE_COMMON.normalize2(x, y)
    local l = sqrt(x * x + y * y)
    if l < 1e-9 then return 1.0, 0.0 end
    return x / l, y / l
end

function WAVE_COMMON.rotate90(x, y)
    return -y, x
end
