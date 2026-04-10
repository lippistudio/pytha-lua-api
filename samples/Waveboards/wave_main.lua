local wave_feature_init = {
    profile_name = "soft_wave",
    angle_deg = 0.0,
    amplitude = 100,    -- object units (mm)
    width = 12,         -- percent of normalized extent
    frequency = 2.0,
    phase = 0.0,        -- percent of full cycle (100 = 2π)
    center_u = 50,      -- percent
    center_v = 50,      -- percent
    size_u = 20,        -- percent
    size_v = 20,        -- percent
    path_mode = "global",
    shift_amp = 0.0,    -- percent of normalized extent
    width_var = 0.0,    -- percent variation (±%)
    amp_var = 0.0       -- percent variation (±%)
}

local function ensure_feature_defaults(feature)
    for k, v in pairs(wave_feature_init) do
        if feature[k] == nil then feature[k] = v end
    end
end

local function ensure_data_defaults(data)
    data.features = data.features or { WAVE_COMMON.copy_table(wave_feature_init) }
    for i = 1, #data.features do ensure_feature_defaults(data.features[i]) end
    if data.active_feature == nil then
        data.active_feature = (#data.features > 0) and 1 or 0
    end
    if data.base_radius == nil then data.base_radius = 0.65 end
    if data.origin == nil then data.origin = { 0.0, 0.0, 0.0 } end
end

local function feature_summary(feature)
    local profile_labels = {
        soft_wave                = pyloc "Soft wave",
        soft_wave_periodic       = pyloc "Soft wave (periodic)",
        round_groove             = pyloc "Round groove",
        round_groove_periodic    = pyloc "Round groove (periodic)",
        ballnose                 = pyloc "Ballnose",
        ballnose_periodic        = pyloc "Ballnose (periodic)",
        v_cut                    = pyloc "V-cut",
        v_cut_periodic           = pyloc "V-cut (periodic)",
        broad_round              = pyloc "Broad round",
        broad_round_periodic     = pyloc "Broad round (periodic)",
        cloth_fold               = pyloc "Cloth fold",
        cloth_fold_periodic      = pyloc "Cloth fold (periodic)",
        double_bead              = pyloc "Double bead",
        double_bead_periodic     = pyloc "Double bead (periodic)",
        dune                     = pyloc "Dune",
        dune_periodic            = pyloc "Dune (periodic)",
        sharp_step               = pyloc "Sharp step",
        sharp_step_periodic      = pyloc "Sharp step (periodic)",
        smooth_step              = pyloc "Smooth step",
        smooth_step_periodic     = pyloc "Smooth step (periodic)",
    }
    local path_labels = {
        global = pyloc "Global",
        packet = pyloc "Packet",
        drop   = pyloc "Drop",
    }
    local pname = feature.profile_name or "soft_wave"
    local pmode = feature.path_mode or "global"
    return string.format("%s | %s",
        profile_labels[pname] or pname,
        path_labels[pmode] or pmode)
end

local function build_generator_options(data)
    return {
        scales = {
            x = data.length or 1600.0,
            y = 0.5 * (data.width or 600.0),
            z = data.height or 900.0
        },
        a_axis = { min = 0.0, max = 1.0, count = math.max(2, data.section_count or 72) },
        z_axis = { min = 0.0, max = 1.0, count = math.max(4, data.point_count or 96) },
        segment_count_per_turn = math.max(12, data.point_count or 96),
        feature_cfg = { features = WAVE_COMMON.copy_table(data.features) },
        base_half_depth = 0.55,
        base_radius = data.base_radius or 0.65
    }
end

local function create_sections_from_data(data)
    local options = build_generator_options(data)
    if data.base_shape == "cylinder" then
        return generate_parametric_sections(options)
    elseif data.base_shape == "one_sided_block" then
        return generate_cross_sections(options, false)
    else
        return generate_cross_sections(options, true)
    end
end

local function delete_current_geometry(data)
    if data.main_group ~= nil then
        pytha.delete_element(data.main_group)
        data.main_group = nil
    elseif data.current_elements ~= nil and #data.current_elements > 0 then
        pytha.delete_element(data.current_elements)
    end
    data.current_elements = nil
end

local function copy_poly(poly)
    local dst = {}
    for i = 1, #poly do
        dst[i] = { poly[i][1], poly[i][2], poly[i][3] }
    end
    return dst
end

local function reverse_poly(poly)
    local dst = {}
    for i = #poly, 1, -1 do
        dst[#dst + 1] = { poly[i][1], poly[i][2], poly[i][3] }
    end
    return dst
end

local function add_named_element(created, element, base_name, name_prefix)
    if element ~= nil then
        local idx = #created + 1
        pytha.set_element_name(element, string.format("%s %s %03d", base_name, name_prefix, idx))
        created[#created + 1] = element
    end
end

local function add_polygon(created, poly, base_name, name_prefix)
    if poly ~= nil and #poly >= 3 then
        local element = pytha.create_polygon(poly)
        add_named_element(created, element, base_name, name_prefix)
    end
end

local function build_transformed_sections(sections, data, bounds)
    local transformed = {}
    local ox = (data.origin and data.origin[1]) or 0.0
    local oy = (data.origin and data.origin[2]) or 0.0
    local oz = (data.origin and data.origin[3]) or 0.0

    for i = 1, #sections do
        local src = sections[i]
        local poly = {}

        for j = 1, #src do
            poly[#poly + 1] = WAVE_COMMON.transform_point(
                src[j][1], src[j][2], src[j][3],
                { ox, oy, oz }, 0.0,
                0, 0, 0
            )
        end

        if #poly >= 3 then
            poly = WAVE_COMMON.ensure_ccw_yz(poly)
            transformed[#transformed + 1] = poly
        end
    end

    return transformed
end

local function create_solid_from_sections(section_polys, data, created)
    if #section_polys < 2 then
        return nil
    end

    local function vec_sub(a, b)
        return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
    end

    local function vec_dot(a, b)
        return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
    end

    local function vec_cross(a, b)
        return {
            a[2] * b[3] - a[3] * b[2],
            a[3] * b[1] - a[1] * b[3],
            a[1] * b[2] - a[2] * b[1]
        }
    end

    local function vec_len(v)
        return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    end

    local function vec_normalize(v)
        local l = vec_len(v)
        if l < 1.0e-9 then
            return { 0.0, 0.0, 0.0 }
        end
        return { v[1] / l, v[2] / l, v[3] / l }
    end

    local function tri_normal(p1, p2, p3)
        local u = vec_sub(p2, p1)
        local v = vec_sub(p3, p1)
        return vec_normalize(vec_cross(u, v))
    end

    local function point_dist2(a, b)
        local dx = a[1] - b[1]
        local dy = a[2] - b[2]
        local dz = a[3] - b[3]
        return dx * dx + dy * dy + dz * dz
    end

    local function choose_quad_split(a1, a2, b1, b2)
        local n1a = tri_normal(a1, a2, b2)
        local n2a = tri_normal(a1, b2, b1)
        local score_a = vec_dot(n1a, n2a)

        local n1b = tri_normal(a1, a2, b1)
        local n2b = tri_normal(a2, b2, b1)
        local score_b = vec_dot(n1b, n2b)

        local eps = 1.0e-6
        if score_a > score_b + eps then
            return 1
        elseif score_b > score_a + eps then
            return 2
        end

        local d1 = point_dist2(a1, b2)
        local d2 = point_dist2(a2, b1)
        if d1 <= d2 then
            return 1
        end
        return 2
    end

    local base_name = data.name or "Wave Shape"
    local face_prefix = "SolidFace"

    for i = 1, #section_polys - 1 do
        local a = section_polys[i]
        local b = section_polys[i + 1]
        local n = math.min(#a, #b)

        if n >= 2 then
            for j = 1, n do
                local j2 = (j % n) + 1

                local a1 = a[j]
                local a2 = a[j2]
                local b1 = b[j]
                local b2 = b[j2]

                local split = choose_quad_split(a1, a2, b1, b2)

                if split == 1 then
                    add_polygon(created, { a1, a2, b2 }, base_name, face_prefix)
                    add_polygon(created, { a1, b2, b1 }, base_name, face_prefix)
                else
                    add_polygon(created, { a1, a2, b1 }, base_name, face_prefix)
                    add_polygon(created, { a2, b2, b1 }, base_name, face_prefix)
                end
            end
        end
    end

    add_polygon(created, reverse_poly(section_polys[1]), base_name, face_prefix)
    add_polygon(created, copy_poly(section_polys[#section_polys]), base_name, face_prefix)

    local first = section_polys[1]
    local last = section_polys[#section_polys]
    local n = math.min(#first, #last)



    local merged = nil
    if #created > 0 then
        merged = pytha.merge_parts(created)
    end

    if merged ~= nil then
        pytha.set_element_name(merged, base_name)
        pytha.delete_element(created)
        return { merged }, merged
    end

    return created, nil
end

function recreate_geometry(data)
    ensure_data_defaults(data)
    delete_current_geometry(data)

    local sections = create_sections_from_data(data)
    local created = {}
    local bounds = WAVE_COMMON.collect_bounds(sections)

    local output_mode = string.lower(data.output_mode or "face")
    local profile_thickness = data.profile_thickness or 19.0
    local base_name = data.name or "Wave Shape"
    local name_prefix =
        output_mode == "profile" and "Profile" or
        output_mode == "solid" and "SolidFace" or
        "Face"

    local section_polys = build_transformed_sections(sections, data, bounds)

    if output_mode == "solid" then
        local solid_elements, merged = create_solid_from_sections(section_polys, data, created)
        data.current_elements = solid_elements or {}
        data.main_group = merged

        if merged ~= nil then
            pytha.set_element_history(merged, data, "wave_shape_history")
        elseif data.current_elements ~= nil and #data.current_elements > 0 then
            data.main_group = pytha.create_group(data.current_elements, { name = data.name })
            if data.main_group ~= nil then
                pytha.set_element_history(data.main_group, data, "wave_shape_history")
            else
                pytha.set_element_history(data.current_elements[1], data, "wave_shape_history")
            end
        end
        return
    end

    for i = 1, #section_polys do
        local poly = section_polys[i]

        if #poly >= 3 then
            if output_mode == "profile" then
                local base_part = pytha.create_polygon(poly)
                if base_part ~= nil then
                    local profile_parts = pytha.create_profile(base_part, profile_thickness)
                    pytha.delete_element(base_part)
                    if profile_parts ~= nil then
                        for k = 1, #profile_parts do
                            if profile_parts[k] ~= nil then
                                local idx = #created + 1
                                pytha.set_element_name(profile_parts[k], string.format("%s %s %03d", base_name, name_prefix, idx))
                                created[#created + 1] = profile_parts[k]
                            end
                        end
                    end
                end
            else
                local element = pytha.create_polygon(poly)
                if element ~= nil then
                    local idx = #created + 1
                    pytha.set_element_name(element, string.format("%s %s %03d", base_name, name_prefix, idx))
                    created[#created + 1] = element
                end
            end
        end
    end

    data.current_elements = created
    data.main_group = nil

    if #created > 0 then
        data.main_group = pytha.create_group(data.current_elements, { name = data.name })
        if data.main_group ~= nil then
            pytha.set_element_history(data.main_group, data, "wave_shape_history")
        else
            pytha.set_element_history(created[1], data, "wave_shape_history")
        end
    end
end

local function update_feature_list(data, ui)
    ui.feature_select:reset_content()
    for i = 1, #data.features do
        ui.feature_select:insert_control_item(feature_summary(data.features[i]))
    end

    local has_features = (#data.features > 0)
    ui.feature_select:enable_control(has_features)

    if has_features and data.active_feature > 0 and data.active_feature <= #data.features then
        ui.feature_select:set_control_selection(data.active_feature)
    end
end

local function update_feature_ui_enabled(data, ui)
    local enabled = (#data.features > 0 and data.active_feature > 0 and data.active_feature <= #data.features)

    ui.button_delete:enable_control(enabled)
    ui.profile_name:enable_control(enabled)
    ui.amplitude:enable_control(enabled)
    ui.width:enable_control(enabled)
    ui.path_mode:enable_control(enabled)

    if not enabled then
        ui.angle_deg:enable_control(false)
        ui.frequency:enable_control(false)
        ui.phase:enable_control(false)
        ui.center_u:enable_control(false)
        ui.center_v:enable_control(false)
        ui.size_u:enable_control(false)
        ui.size_v:enable_control(false)
        ui.shift_amp:enable_control(false)
        ui.width_var:enable_control(false)
        ui.amp_var:enable_control(false)
        return
    end

    ui.center_u:enable_control(true)
    ui.center_v:enable_control(true)

    local f = data.features[data.active_feature]
    local mode = f.path_mode or "global"

    local use_center_size = (mode == "packet" or mode == "drop")
    local use_direction = (mode ~= "drop")
    local use_oscillation = (mode ~= "drop")

    ui.angle_deg:enable_control(use_direction)
    ui.frequency:enable_control(use_oscillation)
    ui.phase:enable_control(use_oscillation)
    ui.shift_amp:enable_control(use_oscillation)
    ui.width_var:enable_control(use_oscillation)
    ui.amp_var:enable_control(use_oscillation)

    ui.size_u:enable_control(use_center_size)
    ui.size_v:enable_control(use_center_size)
end

local function update_feature_ui_values(data, ui)
    local enabled = (#data.features > 0 and data.active_feature > 0 and data.active_feature <= #data.features)
    if not enabled then
        return
    end

    local f = data.features[data.active_feature]
    ui.profile_name:set_control_selection(WAVE_COMMON.combo_index_from_value(ui.profile_items, f.profile_name, 1))
    ui.angle_deg:set_control_text(pyui.format_number(f.angle_deg))
    ui.amplitude:set_control_text(pyui.format_number(f.amplitude))
    ui.width:set_control_text(pyui.format_number(f.width))
    ui.frequency:set_control_text(pyui.format_number(f.frequency))
    ui.phase:set_control_text(pyui.format_number(f.phase))
    ui.center_u:set_control_text(pyui.format_number(f.center_u))
    ui.center_v:set_control_text(pyui.format_number(f.center_v))
    ui.size_u:set_control_text(pyui.format_number(f.size_u))
    ui.size_v:set_control_text(pyui.format_number(f.size_v))
    ui.path_mode:set_control_selection(WAVE_COMMON.combo_index_from_value(ui.path_mode_items, f.path_mode, 1))
    ui.shift_amp:set_control_text(pyui.format_number(f.shift_amp))
    ui.width_var:set_control_text(pyui.format_number(f.width_var))
    ui.amp_var:set_control_text(pyui.format_number(f.amp_var))
end

local function update_base_shape_ui(data, ui)
    ui.base_radius:enable_control(data.base_shape == "cylinder")
    ui.profile_thickness:enable_control(data.output_mode == "profile")
end

function wave_dialog(dialog, data)
    ensure_data_defaults(data)

    local ui = {}
    dialog:set_window_title(pyloc "Wave Shape")

    ui.path_mode_items  = { "global", "packet", "drop" }
    local path_mode_labels = { pyloc "Global", pyloc "Packet", pyloc "Drop" }

    ui.profile_items = {
        "soft_wave",             "soft_wave_periodic",
        "round_groove",          "round_groove_periodic",
        "ballnose",              "ballnose_periodic",
        "v_cut",                 "v_cut_periodic",
        "broad_round",           "broad_round_periodic",
        "cloth_fold",            "cloth_fold_periodic",
        "double_bead",           "double_bead_periodic",
        "dune",                  "dune_periodic",
        "sharp_step",            "sharp_step_periodic",
        "smooth_step",           "smooth_step_periodic",
    }
    ui.profile_labels = {
        pyloc "Soft wave",             pyloc "Soft wave (periodic)",
        pyloc "Round groove",          pyloc "Round groove (periodic)",
        pyloc "Ballnose",              pyloc "Ballnose (periodic)",
        pyloc "V-cut",                 pyloc "V-cut (periodic)",
        pyloc "Broad round",           pyloc "Broad round (periodic)",
        pyloc "Cloth fold",            pyloc "Cloth fold (periodic)",
        pyloc "Double bead",           pyloc "Double bead (periodic)",
        pyloc "Dune",                  pyloc "Dune (periodic)",
        pyloc "Sharp step",            pyloc "Sharp step (periodic)",
        pyloc "Smooth step",           pyloc "Smooth step (periodic)",
    }

    local base_shape_items  = { "one_sided_block", "two_sided_block" }   --, "cylinder"
    local base_shape_labels = { pyloc "One sided block", pyloc "Two sided block" }
    local output_items  = { "face", "profile", "solid" }
    local output_labels = { pyloc "Face", pyloc "Profile", pyloc "Solid" }

    dialog:create_label(1, pyloc "Name")
    ui.name = dialog:create_text_box({2, 4}, data.name)

    dialog:create_label(1, pyloc "Origin")
    local origin_text = pyui.format_length(data.origin[1]) .. "," ..
                        pyui.format_length(data.origin[2]) .. "," ..
                        pyui.format_length(data.origin[3])
    ui.origin = dialog:create_text_box({2, 3}, origin_text)
    ui.pick = dialog:create_button(4, pyloc "Pick")

    dialog:create_label(1, pyloc "Base shape")
    ui.base_shape = dialog:create_drop_list({2, 4}, nil)
    for i = 1, #base_shape_items do
        ui.base_shape:insert_control_item(base_shape_labels[i])
    end
    ui.base_shape:set_control_selection(WAVE_COMMON.combo_index_from_value(base_shape_items, data.base_shape, 2))

    dialog:create_group_box({1,4}, pyloc "Dimensions")
    dialog:create_label(1, pyloc "Length")
    ui.length = dialog:create_text_box(2, pyui.format_length(data.length))
    dialog:create_label(3, pyloc "Width")
    ui.width_dim = dialog:create_text_box(4, pyui.format_length(data.width))

    dialog:create_label(1, pyloc "Height")
    ui.height_dim = dialog:create_text_box(2, pyui.format_length(data.height))
    dialog:create_label(3, pyloc "Base radius")
    ui.base_radius = dialog:create_text_box(4, pyui.format_number(data.base_radius or 0.65))

    dialog:create_label(1, pyloc "Sections")
    ui.sections = dialog:create_text_box(2, pyui.format_number(data.section_count))
    dialog:create_label(3, pyloc "Points / section")
    ui.points = dialog:create_text_box(4, pyui.format_number(data.point_count))

    dialog:create_label(1, pyloc "Output")
    ui.output_mode = dialog:create_drop_list(2, nil)
    for i = 1, #output_items do
        ui.output_mode:insert_control_item(output_labels[i])
    end
    ui.output_mode:set_control_selection(WAVE_COMMON.combo_index_from_value(output_items, data.output_mode, 1))

    dialog:create_label(3, pyloc "Profile thickness")
    ui.profile_thickness = dialog:create_text_box(4, pyui.format_length(data.profile_thickness))
    dialog:end_group_box()

    dialog:create_group_box({1,4}, pyloc "Features")

    ui.feature_select = dialog:create_drop_list({1, 2}, nil)
    ui.button_new = dialog:create_button(3, pyloc "New")
    ui.button_delete = dialog:create_button(4, pyloc "Delete")

    dialog:create_label(1, pyloc "Cross section")
    ui.profile_name = dialog:create_drop_list(2)
    for i = 1, #ui.profile_items do
        ui.profile_name:insert_control_item(ui.profile_labels[i])
    end

    dialog:create_label(3, pyloc "Path mode")
    ui.path_mode = dialog:create_drop_list(4)
    for i = 1, #ui.path_mode_items do
        ui.path_mode:insert_control_item(path_mode_labels[i])
    end

    dialog:create_label(1, pyloc "Amplitude")
    ui.amplitude = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "± Amp (%)")
    ui.amp_var = dialog:create_text_box(4)

    dialog:create_label(1, pyloc "Width (%)")
    ui.width = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "± Width (%)")
    ui.width_var = dialog:create_text_box(4)

    dialog:create_label(1, pyloc "Frequency")
    ui.frequency = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "Angle")
    ui.angle_deg = dialog:create_text_box(4)


    dialog:create_label(1, pyloc "Phase (%)")
    ui.phase = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "Shift amp. (%)")
    ui.shift_amp = dialog:create_text_box(4)

    dialog:create_label(1, pyloc "Center U (%)")
    ui.center_u = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "Center V (%)")
    ui.center_v = dialog:create_text_box(4)

    dialog:create_label(1, pyloc "Size U (%)")
    ui.size_u = dialog:create_text_box(2)
    dialog:create_label(3, pyloc "Size V (%)")
    ui.size_v = dialog:create_text_box(4)

    dialog:end_group_box()

    dialog:create_align({1, 4})
    dialog:create_ok_button(3)
    dialog:create_cancel_button(4)

    local function refresh_lists_and_enabled()
        update_feature_list(data, ui)
        update_feature_ui_enabled(data, ui)
        update_base_shape_ui(data, ui)
    end

    ui.button_new:set_on_click_handler(function()
        local new_feature = WAVE_COMMON.copy_table(wave_feature_init)
        if data.active_feature > 0 and data.active_feature <= #data.features then
            for k, v in pairs(data.features[data.active_feature]) do
                new_feature[k] = WAVE_COMMON.copy_table(v)
            end
        end
        data.features[#data.features + 1] = new_feature
        data.active_feature = #data.features
        refresh_lists_and_enabled()
        update_feature_ui_values(data, ui)
        recreate_geometry(data)
    end)

    ui.button_delete:set_on_click_handler(function()
        if data.active_feature > 0 and data.active_feature <= #data.features then
            table.remove(data.features, data.active_feature)
            if #data.features == 0 then
                data.active_feature = 0
            else
                data.active_feature = math.min(data.active_feature, #data.features)
            end
            refresh_lists_and_enabled()
            update_feature_ui_values(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.feature_select:set_on_change_handler(function(text, new_index)
        if new_index > 0 and new_index <= #data.features then
            data.active_feature = new_index
            update_feature_ui_enabled(data, ui)
            update_feature_ui_values(data, ui)
        end
    end)

    ui.name:set_on_change_handler(function(text)
        data.name = text
        recreate_geometry(data)
    end)

    ui.base_shape:set_on_change_handler(function(text, new_index)
        data.base_shape = WAVE_COMMON.combo_value_from_index(base_shape_items, new_index, "two_sided_block")
        update_base_shape_ui(data, ui)
        recreate_geometry(data)
    end)

    ui.origin:set_on_change_handler(function(text)
        local vals = { pyui.parse_length(text) }
        if vals[1] ~= nil then
            data.origin = { vals[1], vals[2] or 0.0, vals[3] or 0.0 }
            recreate_geometry(data)
        end
    end)

    ui.pick:set_on_click_handler(function()
        ui.pick:enable_control(false)
        local ret = pyux.select_coordinate()
        if ret ~= nil then
            data.origin = ret
            ui.origin:set_control_text(
                pyui.format_length(data.origin[1]) .. "," ..
                pyui.format_length(data.origin[2]) .. "," ..
                pyui.format_length(data.origin[3])
            )
            recreate_geometry(data)
        end
        ui.pick:enable_control(true)
    end)

    ui.length:set_on_change_handler(function(text)
        local v = pyui.parse_length(text)
        if v ~= nil and v > 0 then
            data.length = v
            recreate_geometry(data)
        end
    end)

    ui.width_dim:set_on_change_handler(function(text)
        local v = pyui.parse_length(text)
        if v ~= nil and v > 0 then
            data.width = v
            recreate_geometry(data)
        end
    end)

    ui.height_dim:set_on_change_handler(function(text)
        local v = pyui.parse_length(text)
        if v ~= nil and v > 0 then
            data.height = v
            recreate_geometry(data)
        end
    end)

    ui.base_radius:set_on_change_handler(function(text)
        local v = pyui.parse_number(text)
        if v ~= nil and v > 0.0 then
            data.base_radius = v
            recreate_geometry(data)
        end
    end)

    ui.sections:set_on_change_handler(function(text)
        local v = pyui.parse_number(text)
        if v ~= nil and v >= 2 then
            data.section_count = math.floor(v + 0.5)
            recreate_geometry(data)
        end
    end)

    ui.points:set_on_change_handler(function(text)
        local v = pyui.parse_number(text)
        if v ~= nil and v >= 3 then
            data.point_count = math.floor(v + 0.5)
            recreate_geometry(data)
        end
    end)

    ui.output_mode:set_on_change_handler(function(text, new_index)
        data.output_mode = WAVE_COMMON.combo_value_from_index(output_items, new_index, "face")
        update_base_shape_ui(data, ui)
        recreate_geometry(data)
    end)

    ui.profile_thickness:set_on_change_handler(function(text)
        local v = pyui.parse_length(text)
        if v ~= nil and v > 0 then
            data.profile_thickness = v
            recreate_geometry(data)
        end
    end)

    local function active_feature()
        if data.active_feature > 0 and data.active_feature <= #data.features then
            return data.features[data.active_feature]
        end
        return nil
    end

    ui.profile_name:set_on_change_handler(function(text, new_index)
        local f = active_feature()
        if f ~= nil then
            f.profile_name = WAVE_COMMON.combo_value_from_index(ui.profile_items, new_index, "soft_wave")
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.angle_deg:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.angle_deg = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.amplitude:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.amplitude = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.width:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil and v > 0.0 then
            f.width = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.frequency:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.frequency = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.phase:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.phase = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.center_u:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.center_u = v
            recreate_geometry(data)
        end
    end)

    ui.center_v:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.center_v = v
            recreate_geometry(data)
        end
    end)

    ui.size_u:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil and v > 0.0 then
            f.size_u = v
            recreate_geometry(data)
        end
    end)

    ui.size_v:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil and v > 0.0 then
            f.size_v = v
            recreate_geometry(data)
        end
    end)

    ui.path_mode:set_on_change_handler(function(text, new_index)
        local f = active_feature()
        if f ~= nil then
            f.path_mode = WAVE_COMMON.combo_value_from_index(ui.path_mode_items, new_index, "global")
            update_feature_ui_enabled(data, ui)
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.shift_amp:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.shift_amp = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.width_var:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.width_var = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    ui.amp_var:set_on_change_handler(function(text)
        local f = active_feature()
        local v = pyui.parse_number(text)
        if f ~= nil and v ~= nil then
            f.amp_var = v
            update_feature_list(data, ui)
            recreate_geometry(data)
        end
    end)

    refresh_lists_and_enabled()
    update_feature_ui_values(data, ui)
end

function edit_block(element)
    local loaded_data = pytha.get_element_history(element, "wave_shape_history")
    if loaded_data == nil then
        pyui.alert(pyloc "No data found")
        return
    end
    ensure_data_defaults(loaded_data)
    recreate_geometry(loaded_data)
    pyui.run_modal_dialog(wave_dialog, loaded_data)
    pyio.save_values("wave_shape_defaults", loaded_data)
end

function main()
    local data = {
        name = pyloc "Wave Shape",
        preset = "organic",
        base_shape = "two_sided_block",
        length = 1600.0,
        width = 600.0,
        height = 900.0,
        base_radius = 0.65,
        origin = { 0.0, 0.0, 0.0 },
        section_count = 50,
        point_count = 96,
        output_mode = "face",
        profile_thickness = 19.0,
        features = { WAVE_COMMON.copy_table(wave_feature_init) },
        active_feature = 1,
        current_elements = nil,
        main_group = nil
    }

    local loaded_data = pyio.load_values("wave_shape_defaults")
    if loaded_data ~= nil then
        for k, v in pairs(loaded_data) do
            data[k] = v
        end
    end

    ensure_data_defaults(data)
    recreate_geometry(data)
    pyui.run_modal_dialog(wave_dialog, data)
    pyio.save_values("wave_shape_defaults", data)
end