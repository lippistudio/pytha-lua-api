-- Filler Generator
-- Cleaned version:
-- Removed unused duplicate inner-loop builder functions
-- Added apply_defaults() to avoid repeated initialization code
-- Base and Top panels still construct their own geometry directly
-- Added No of Ribs with equally spaced internal ribs using same profile as Top/Base Panel
-- No of Ribs is now a drop list from 0 to 99
-- Added Rotation (degrees) and builds the whole part already rotated

function apply_defaults(data)
    if data == nil then data = {} end

    if data.length == nil then data.length = 500 end
    if data.width == nil then data.width = 300 end
    if data.height == nil then data.height = 30 end
    if data.panel_thickness == nil then data.panel_thickness = 18 end
    if data.carcass_thickness == nil then data.carcass_thickness = 18 end
    if data.no_of_ribs == nil then data.no_of_ribs = 0 end
    if data.rotation == nil then data.rotation = 0 end

    if data.front_left_radius == nil then data.front_left_radius = 0 end
    if data.front_right_radius == nil then data.front_right_radius = 0 end
    if data.back_left_radius == nil then data.back_left_radius = 0 end
    if data.back_right_radius == nil then data.back_right_radius = 0 end

    if data.front_left_segments == nil then data.front_left_segments = 8 end
    if data.front_right_segments == nil then data.front_right_segments = 8 end
    if data.back_left_segments == nil then data.back_left_segments = 8 end
    if data.back_right_segments == nil then data.back_right_segments = 8 end

    if data.exposed_side == nil then data.exposed_side = "Left Exposed" end
    if data.origin == nil then data.origin = {0, 0, 0} end
    if data.name == nil then data.name = pyloc "Panel" end

    return data
end

local function set_history(data)

    pytha.set_element_history(data.current_element, data, "filler_history")


end

function edit_filler(element)
    local loaded_data = pytha.get_element_history(element, "filler_history")
    if loaded_data == nil then
        pyui.alert(pyloc "No data found")
        return
    end

    loaded_data.current_element = element
    apply_defaults(loaded_data)

    if loaded_data.old_sheet ~= nil then 
        pyplot.delete_sheet(loaded_data.old_sheet)
    end

    pyui.run_modal_dialog(cube_dialog, loaded_data)
    
    loaded_data.old_sheet = plot_sheets(loaded_data.current_element)
    set_history(loaded_data)

    pyio.save_values("default_dimensions", loaded_data)
end

function main()
    local data = pyio.load_values("default_dimensions")
    apply_defaults(data)
    
    if data.old_sheet ~= nil then 
        pyplot.delete_sheet(data.old_sheet)
    end

    recreate_geometry(data)
    pyui.run_modal_dialog(cube_dialog, data)

    data.old_sheet = plot_sheets(data.current_element)
    set_history(data)

    
    pyio.save_values("default_dimensions", data)
end

function cube_dialog(dialog, data)
    dialog:set_window_title(pyloc "Filler Generator")

    dialog:create_label(1, pyloc "Name")
    local name = dialog:create_text_box({2,10}, data.name)

    dialog:create_label(1, pyloc "Length")
    local length = dialog:create_text_box(2, data.length)

    dialog:create_label(3, pyloc "Depth")
    local width = dialog:create_text_box(4, data.width)
    local button_pick_depth = dialog:create_button({5,6}, pyloc "Pick Depth")

    dialog:create_label(7, pyloc "Height")
    local height = dialog:create_text_box(8, data.height)
    local button_pick_height = dialog:create_button({9,10}, pyloc "Pick Height")

    dialog:create_label(1, pyloc "Panel Thickness")
    local panel_thickness = dialog:create_text_box(2, data.panel_thickness)

    dialog:create_label(3, pyloc "Carcass Thickness")
    local carcass_thickness = dialog:create_text_box(4, data.carcass_thickness)

    dialog:create_label(5, pyloc "No of Ribs")
    local no_of_ribs = dialog:create_drop_list(6)
    for i = 0, 99 do
        no_of_ribs:insert_control_item(tostring(i))
    end
    no_of_ribs:set_control_selection((data.no_of_ribs or 0) + 1)

    dialog:create_label(7, pyloc "Rotation")
    local rotation = dialog:create_text_box(8, tostring(data.rotation or 0))

    dialog:create_label(1, pyloc "Exposed Side")
    local exposed_side = dialog:create_drop_list({2,5})
    exposed_side:insert_control_item(pyloc "Left Exposed")
    exposed_side:insert_control_item(pyloc "Right Exposed")
    if data.exposed_side == "Right Exposed" then
        exposed_side:set_control_selection(2)
    else
        exposed_side:set_control_selection(1)
    end

    local fl_label = dialog:create_label(1, pyloc "Front Left Radius")
    local fl_radius = dialog:create_text_box({2,3}, data.front_left_radius)
    local fl_seg_label = dialog:create_label(4, pyloc "Segments")
    local fl_segments = dialog:create_text_box({5,6}, tostring(data.front_left_segments))

    local fr_label = dialog:create_label(1, pyloc "Front Right Radius")
    local fr_radius = dialog:create_text_box({2,3}, data.front_right_radius)
    local fr_seg_label = dialog:create_label(4, pyloc "Segments")
    local fr_segments = dialog:create_text_box({5,6}, tostring(data.front_right_segments))

    local bl_label = dialog:create_label(1, pyloc "Back Left Radius")
    local bl_radius = dialog:create_text_box({2,3}, data.back_left_radius)
    local bl_seg_label = dialog:create_label(4, pyloc "Segments")
    local bl_segments = dialog:create_text_box({5,6}, tostring(data.back_left_segments))

    local br_label = dialog:create_label(1, pyloc "Back Right Radius")
    local br_radius = dialog:create_text_box({2,3}, data.back_right_radius)
    local br_seg_label = dialog:create_label(4, pyloc "Segments")
    local br_segments = dialog:create_text_box({5,6}, tostring(data.back_right_segments))

    local button_ori = dialog:create_button({1,4}, pyloc "Left Insert")
    local button_ori2 = dialog:create_button({5,10}, pyloc "Right Insert")
    dialog:create_ok_button(1)
    dialog:create_cancel_button(2)

    local function parse_segments(text, old_value)
        local n = tonumber(text)
        if n == nil then n = old_value or 8 end
        n = math.floor(n)
        if n < 1 then n = 1 end
        return n
    end

    local function set_control_visible(ctrl, is_visible)
        if ctrl == nil then return end
        if pyui.show_control ~= nil then
            pyui.show_control(ctrl, is_visible)
        else
            if is_visible then
                if ctrl.enable_control ~= nil then ctrl:enable_control() end
            else
                if ctrl.disable_control ~= nil then ctrl:disable_control() end
            end
        end
    end

    local function update_corner_visibility()
        local left_visible = (data.exposed_side ~= "Left Exposed")
        local right_visible = (data.exposed_side ~= "Right Exposed")

        set_control_visible(fl_label, left_visible)
        set_control_visible(fl_radius, left_visible)
        set_control_visible(fl_seg_label, left_visible)
        set_control_visible(fl_segments, left_visible)

        set_control_visible(bl_label, left_visible)
        set_control_visible(bl_radius, left_visible)
        set_control_visible(bl_seg_label, left_visible)
        set_control_visible(bl_segments, left_visible)

        set_control_visible(fr_label, right_visible)
        set_control_visible(fr_radius, right_visible)
        set_control_visible(fr_seg_label, right_visible)
        set_control_visible(fr_segments, right_visible)

        set_control_visible(br_label, right_visible)
        set_control_visible(br_radius, right_visible)
        set_control_visible(br_seg_label, right_visible)
        set_control_visible(br_segments, right_visible)
    end

    local function refresh()
        clamp_radii(data)
        recreate_geometry(data)
        update_corner_visibility()
    end

    update_corner_visibility()

    name:set_on_change_handler(function(text)
        data.name = text
        refresh()
    end)

    length:set_on_change_handler(function(text)
        data.length = pyui.parse_length(text) or data.length
        if data.length == nil then data.length = 0 end
        if data.length > 0 then refresh() end
    end)

    width:set_on_change_handler(function(text)
        local new_width = pyui.parse_length(text) or data.width
        if new_width == nil then new_width = 0 end
        if new_width > 0 then
            local back_y = data.origin[2] + (data.width or 0)
            data.width = new_width
            data.origin[2] = back_y - data.width
            refresh()
        end
    end)

    height:set_on_change_handler(function(text)
        data.height = pyui.parse_length(text) or data.height
        if data.height == nil then data.height = 0 end
        if data.height > 0 then refresh() end
    end)

    panel_thickness:set_on_change_handler(function(text)
        data.panel_thickness = pyui.parse_length(text) or data.panel_thickness
        if data.panel_thickness == nil then data.panel_thickness = 0 end
        if data.panel_thickness > 0 then refresh() end
    end)

    carcass_thickness:set_on_change_handler(function(text)
        data.carcass_thickness = pyui.parse_length(text) or data.carcass_thickness
        if data.carcass_thickness == nil then data.carcass_thickness = 0 end
        if data.carcass_thickness >= 0 then refresh() end
    end)

    no_of_ribs:set_on_change_handler(function(text, new_index)
        data.no_of_ribs = (new_index or 1) - 1
        if data.no_of_ribs < 0 then data.no_of_ribs = 0 end
        refresh()
    end)

    rotation:set_on_change_handler(function(text)
        local v = tonumber(text)
        if v ~= nil then
            data.rotation = v
            refresh()
        end
    end)

    button_pick_depth:set_on_click_handler(function()
        button_pick_depth:disable_control()
        local ret_wert = pyux.select_coordinate()
        if ret_wert ~= nil then
            local back_y = data.origin[2] + (data.width or 0)
            local new_depth = back_y - ret_wert[2]
            if new_depth < 0 then new_depth = -new_depth end

            data.width = new_depth
            data.origin[2] = back_y - data.width

            if width.set_control_text ~= nil then
                width:set_control_text(pyui.format_length(data.width))
            end

            if data.width > 0 then refresh() end
        end
        button_pick_depth:enable_control()
    end)

    button_pick_height:set_on_click_handler(function()
        button_pick_height:disable_control()
        local ret_wert = pyux.select_coordinate()
        if ret_wert ~= nil then
            local base_z = data.origin[3] or 0
            data.height = math.abs(ret_wert[3] - base_z)

            if height.set_control_text ~= nil then
                height:set_control_text(pyui.format_length(data.height))
            end

            if data.height > 0 then refresh() end
        end
        button_pick_height:enable_control()
    end)

    exposed_side:set_on_change_handler(function(text, new_index)
        data.exposed_side = text
        update_corner_visibility()
        refresh()
    end)

    fl_radius:set_on_change_handler(function(text)
        data.front_left_radius = pyui.parse_length(text) or data.front_left_radius
        if data.front_left_radius == nil then data.front_left_radius = 0 end
        data.front_left_segments = parse_segments(data.front_left_segments, 8)
        refresh()
    end)

    fl_segments:set_on_change_handler(function(text)
        data.front_left_segments = parse_segments(text, data.front_left_segments)
        refresh()
    end)

    fr_radius:set_on_change_handler(function(text)
        data.front_right_radius = pyui.parse_length(text) or data.front_right_radius
        if data.front_right_radius == nil then data.front_right_radius = 0 end
        data.front_right_segments = parse_segments(data.front_right_segments, 8)
        refresh()
    end)

    fr_segments:set_on_change_handler(function(text)
        data.front_right_segments = parse_segments(text, data.front_right_segments)
        refresh()
    end)

    bl_radius:set_on_change_handler(function(text)
        data.back_left_radius = pyui.parse_length(text) or data.back_left_radius
        if data.back_left_radius == nil then data.back_left_radius = 0 end
        data.back_left_segments = parse_segments(data.back_left_segments, 8)
        refresh()
    end)

    bl_segments:set_on_change_handler(function(text)
        data.back_left_segments = parse_segments(text, data.back_left_segments)
        refresh()
    end)

    br_radius:set_on_change_handler(function(text)
        data.back_right_radius = pyui.parse_length(text) or data.back_right_radius
        if data.back_right_radius == nil then data.back_right_radius = 0 end
        data.back_right_segments = parse_segments(data.back_right_segments, 8)
        refresh()
    end)

    br_segments:set_on_change_handler(function(text)
        data.back_right_segments = parse_segments(text, data.back_right_segments)
        refresh()
    end)

    button_ori:set_on_click_handler(function()
        button_ori:disable_control()
        local ret_wert = pyux.select_coordinate()
        if ret_wert ~= nil then
            data.origin = {
                ret_wert[1] - (data.length or 0),
                ret_wert[2] - (data.width or 0),
                ret_wert[3]
            }
        end
        button_ori:enable_control()
        refresh()
    end)

    button_ori2:set_on_click_handler(function()
        button_ori2:disable_control()
        local ret_wert = pyux.select_coordinate()
        if ret_wert ~= nil then
            data.origin = {
                ret_wert[1],
                ret_wert[2] - (data.width or 0),
                ret_wert[3]
            }
        end
        button_ori2:enable_control()
        refresh()
    end)
end

function clamp_radii(data)
    local L = data.length or 0
    local W = data.width or 0
    local T = data.panel_thickness or 0

    local function clamp(v)
        v = v or 0
        if v < 0 then v = 0 end
        return v
    end

    data.front_left_radius  = clamp(data.front_left_radius)
    data.front_right_radius = clamp(data.front_right_radius)
    data.back_left_radius   = clamp(data.back_left_radius)
    data.back_right_radius  = clamp(data.back_right_radius)

    if T < 0 then data.panel_thickness = 0 end
    if T > W / 2 then data.panel_thickness = W / 2 end
    if T > L then data.panel_thickness = L end

    local max_corner = math.min(L, W)
    data.front_left_radius  = math.min(data.front_left_radius,  max_corner)
    data.front_right_radius = math.min(data.front_right_radius, max_corner)
    data.back_left_radius   = math.min(data.back_left_radius,   max_corner)
    data.back_right_radius  = math.min(data.back_right_radius,  max_corner)
end

function get_rotation_axes(data)
    local a = math.rad(data.rotation or 0)
    local axis_x = {math.cos(a), math.sin(a), 0}
    local axis_y = {-math.sin(a), math.cos(a), 0}
    return axis_x, axis_y
end

function transform_loop_to_world(loop_data, origin, axis_x, axis_y, z_value)
    local pts2d = loop_data[1]
    local segs = loop_data[2]
    local pts3d = {}

    for i = 1, #pts2d do
        local px = pts2d[i][1] or 0
        local py = pts2d[i][2] or 0

        pts3d[i] = {
            origin[1] + px * axis_x[1] + py * axis_y[1],
            origin[2] + px * axis_x[2] + py * axis_y[2],
            z_value
        }
    end

    return {pts3d, segs}
end

function build_left_exposed_loop(data)
    local L = data.length or 0
    local W = data.width or 0
    local T = data.panel_thickness or 0

    local rFR = math.min(data.front_right_radius or 0, math.min(L, W))
    local rBR = math.min(data.back_right_radius or 0, math.min(L, W))
    local sFR = math.max(1, math.floor(data.front_right_segments or 8))
    local sBR = math.max(1, math.floor(data.back_right_segments or 8))

    if T <= 0 then
        local pts = {
            {0, 0},
            {L - rFR, 0},
            {L, rFR},
            {L, W - rBR},
            {L - rBR, W},
            {0, W}
        }

        local segs = {
            nil,
            (rFR > 0) and {radius = rFR, orientation = "ccw", select_arc = "small", segments = sFR} or nil,
            nil,
            (rBR > 0) and {radius = rBR, orientation = "ccw", select_arc = "small", segments = sBR} or nil,
            nil,
            nil
        }

        return {pts, segs}
    end

    if T > W / 2 then T = W / 2 end
    if T > L then T = L end

    local rFRi = math.max(rFR - T, 0)
    local rBRi = math.max(rBR - T, 0)

    local pts = {
        {0, 0},
        {L - rFR, 0},
        {L, rFR},
        {L, W - rBR},
        {L - rBR, W},
        {0, W},
        {0, W - T},
        {L - rBR, W - T},
        {L - T, W - rBR},
        {L - T, rFR},
        {L - rFR, T},
        {0, T}
    }

    local segs = {
        nil,
        (rFR > 0) and {radius = rFR, orientation = "ccw", select_arc = "small", segments = sFR} or nil,
        nil,
        (rBR > 0) and {radius = rBR, orientation = "ccw", select_arc = "small", segments = sBR} or nil,
        nil,
        nil,
        nil,
        (rBRi > 0) and {radius = rBRi, orientation = "cw", select_arc = "small", segments = sBR} or nil,
        nil,
        (rFRi > 0) and {radius = rFRi, orientation = "cw", select_arc = "small", segments = sFR} or nil,
        nil,
        nil
    }

    return {pts, segs}
end

function build_right_exposed_loop(data)
    local L = data.length or 0
    local W = data.width or 0
    local T = data.panel_thickness or 0

    local rFL = math.min(data.front_left_radius or 0, math.min(L, W))
    local rBL = math.min(data.back_left_radius or 0, math.min(L, W))
    local sFL = math.max(1, math.floor(data.front_left_segments or 8))
    local sBL = math.max(1, math.floor(data.back_left_segments or 8))

    if T <= 0 then
        local pts = {
            {L, W},
            {rBL, W},
            {0, W - rBL},
            {0, rFL},
            {rFL, 0},
            {L, 0}
        }

        local segs = {
            nil,
            (rBL > 0) and {radius = rBL, orientation = "cw", select_arc = "small", segments = sBL} or nil,
            nil,
            (rFL > 0) and {radius = rFL, orientation = "cw", select_arc = "small", segments = sFL} or nil,
            nil,
            nil
        }

        return {pts, segs}
    end

    if T > W / 2 then T = W / 2 end
    if T > L then T = L end

    local rFLi = math.max(rFL - T, 0)
    local rBLi = math.max(rBL - T, 0)

    local pts = {
        {L, T},
        {rFL, T},
        {T, rFL},
        {T, W - rBL},
        {rBL, W - T},
        {L, W - T},
        {L, W},
        {rBL, W},
        {0, W - rBL},
        {0, rFL},
        {rFL, 0},
        {L, 0}
    }

    local segs = {
        nil,
        (rFLi > 0) and {radius = rFLi, orientation = "cw", select_arc = "small", segments = sFL} or nil,
        nil,
        (rBLi > 0) and {radius = rBLi, orientation = "cw", select_arc = "small", segments = sBL} or nil,
        nil,
        nil,
        nil,
        (rBL > 0) and {radius = rBL, orientation = "ccw", select_arc = "small", segments = sBL} or nil,
        nil,
        (rFL > 0) and {radius = rFL, orientation = "ccw", select_arc = "small", segments = sFL} or nil,
        nil,
        nil
    }

    return {pts, segs}
end

function get_profile_definition(data)
    clamp_radii(data)

    if data.exposed_side == "Right Exposed" then
        return build_right_exposed_loop(data)
    else
        return build_left_exposed_loop(data)
    end
end

function create_inner_panel_loop(data)
    local L = data.length or 0
    local W = data.width or 0
    local T = data.panel_thickness or 0
    local C = data.carcass_thickness or 0

    if T <= 0 then return nil end
    if T > W / 2 then T = W / 2 end
    if T > L then T = L end

    if data.exposed_side == "Right Exposed" then
        local rFL = math.min(data.front_left_radius or 0, math.min(L, W))
        local rBL = math.min(data.back_left_radius or 0, math.min(L, W))
        local sFL = math.max(1, math.floor(data.front_left_segments or 8))
        local sBL = math.max(1, math.floor(data.back_left_segments or 8))

        local rFLi = math.max(rFL - T, 0)
        local rBLi = math.max(rBL - T, 0)

        local pts = {
            {L - C, T},
            {L - C, W - T},
            {rBL, W - T},
            {T, W - rBL},
            {T, rFL},
            {rFL, T}
        }

        local segs = {
            nil,
            nil,
            (rBLi > 0) and {radius = rBLi, orientation = "ccw", select_arc = "small", segments = sBL} or nil,
            nil,
            (rFLi > 0) and {radius = rFLi, orientation = "ccw", select_arc = "small", segments = sFL} or nil,
            nil
        }

        return {pts, segs}
    else
        local rFR = math.min(data.front_right_radius or 0, math.min(L, W))
        local rBR = math.min(data.back_right_radius or 0, math.min(L, W))
        local sFR = math.max(1, math.floor(data.front_right_segments or 8))
        local sBR = math.max(1, math.floor(data.back_right_segments or 8))

        local rFRi = math.max(rFR - T, 0)
        local rBRi = math.max(rBR - T, 0)

        local pts = {
            {C, T},
            {C, W - T},
            {L - rBR, W - T},
            {L - T, W - rBR},
            {L - T, rFR},
            {L - rFR, T}
        }

        local segs = {
            nil,
            nil,
            (rBRi > 0) and {radius = rBRi, orientation = "ccw", select_arc = "small", segments = sBR} or nil,
            nil,
            (rFRi > 0) and {radius = rFRi, orientation = "ccw", select_arc = "small", segments = sFR} or nil,
            nil
        }

        return {pts, segs}
    end
end

function get_inner_panel_face_origin(data, z_pos)
    local face_origin = {
        data.origin[1],
        data.origin[2],
        z_pos
    }

    if data.exposed_side == "Left Exposed" then
        face_origin[3] = face_origin[3] + (data.carcass_thickness or 0)
    end

    return face_origin
end

function create_inner_profile_part(data, z_pos, part_name)
    local inner_loop = create_inner_panel_loop(data)
    if inner_loop == nil then
        return nil
    end

    local axis_x, axis_y = get_rotation_axes(data)
    local face_origin = get_inner_panel_face_origin(data, z_pos)
    local world_loop = transform_loop_to_world(inner_loop, face_origin, axis_x, axis_y, face_origin[3])

    local inner_face = pytha.create_polygon_ex({world_loop})
    if inner_face == nil then
        return nil
    end

    local parts = pytha.create_profile(inner_face, data.carcass_thickness, {name = part_name})
    pytha.delete_element(inner_face)

    if parts ~= nil and parts[1] ~= nil then
        return parts[1]
    end

    return nil
end

function recreate_geometry(data)
    if data.current_element ~= nil then
        pytha.delete_element(data.current_element)
    end

    local axis_x, axis_y = get_rotation_axes(data)

    local base_loop = get_profile_definition(data)
    local world_base_loop = transform_loop_to_world(base_loop, data.origin, axis_x, axis_y, data.origin[3])
    local base_face = pytha.create_polygon_ex({world_base_loop})

    if base_face == nil then
        data.current_element = nil
        return
    end

    local profile_parts = pytha.create_profile(base_face, data.height, {name = data.name})
    pytha.delete_element(base_face)

    if profile_parts == nil or profile_parts[1] == nil then
        data.current_element = nil
        return
    end

    local created_elements = {profile_parts[1]}

    if (data.carcass_thickness or 0) > 0 then
        local end_panel = nil
        local end_depth = (data.width or 0) - (data.panel_thickness or 0) - (data.panel_thickness or 0)

        if end_depth < 0 then end_depth = 0 end

        if data.exposed_side == "Right Exposed" then
            end_panel = pytha.create_block(
                data.carcass_thickness,
                end_depth,
                data.height,
                {
                    data.origin[1] + (data.length - data.carcass_thickness) * axis_x[1] + (data.panel_thickness) * axis_y[1],
                    data.origin[2] + (data.length - data.carcass_thickness) * axis_x[2] + (data.panel_thickness) * axis_y[2],
                    data.origin[3]
                },
                {name = data.name .. " End Panel", u_axis = axis_x, v_axis = axis_y}
            )
        elseif data.exposed_side == "Left Exposed" then
            end_panel = pytha.create_block(
                data.carcass_thickness,
                end_depth,
                data.height,
                {
                    data.origin[1] + (data.panel_thickness) * axis_y[1],
                    data.origin[2] + (data.panel_thickness) * axis_y[2],
                    data.origin[3]
                },
                {name = data.name .. " End Panel", u_axis = axis_x, v_axis = axis_y}
            )
        end

        if end_panel ~= nil then
            table.insert(created_elements, end_panel)
        end
    end

    if (data.carcass_thickness or 0) > 0 then
        local C = data.carcass_thickness or 0
        local H = data.height or 0
        local rib_count = data.no_of_ribs or 0

        local base_part = create_inner_profile_part(data, data.origin[3], data.name .. " Base Panel")
        if base_part ~= nil then
            table.insert(created_elements, base_part)
        end

        local top_z = data.origin[3] + H - C
        local top_part = create_inner_profile_part(data, top_z, data.name .. " Top Panel")
        if top_part ~= nil then
            table.insert(created_elements, top_part)
        end

        if rib_count > 0 then
            local clear_space = H - (2 * C)
            if clear_space > 0 then
                local spacing = clear_space / (rib_count + 1)

                for i = 1, rib_count do
                    local rib_z = data.origin[3] + C + (spacing * i) - (C * 0.5)
                    local rib_part = create_inner_profile_part(data, rib_z, data.name .. " Rib")
                    if rib_part ~= nil then
                        table.insert(created_elements, rib_part)
                    end
                end
            end
        end
    end

    if #created_elements > 1 and pytha.create_group ~= nil then
        local grp = pytha.create_group(created_elements, {name = data.name})
        if grp ~= nil then
            data.current_element = grp
        else
            data.current_element = created_elements[1]
        end
    else
        data.current_element = created_elements[1]
    end

end