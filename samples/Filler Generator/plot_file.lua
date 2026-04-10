function plot_sheets(main_group)



	local template_file = find_plot_template("Plottblatt__ds.pyplot")

	return create_group_plot_page(template_file, {main_group})


end


-- =========================================================
-- Template / sheet helpers
-- =========================================================

function find_plot_template(template_name)
	local handle = pyux.get_library_handle_ex("plot", "library", "Plot templates")
	if handle == nil then
		return nil
	end

	local template_files = pyux.list_files("plot", handle)
	if template_files == nil then
		return nil
	end

	for _, file in pairs(template_files) do
		if file:get_name() == template_name then
			return file
		end
	end

	return nil
end

function create_sheet_from_template(template_file, fallback_name)
	if template_file ~= nil then
		local imported = pyplot.import_sheet(template_file)
		if imported ~= nil and imported[1] ~= nil then
			return imported[1]
		end
	end
	return pyplot.create_sheet(fallback_name or "No Template")
end


-- =========================================================
-- Generic helpers
-- =========================================================

function round_dim(v)
	return math.floor(v * 100 + 0.5) / 100
end

function safe_get_name(element, fallback)
	if element == nil then
		return fallback or ""
	end

	local ok, value = pcall(function()
		return element:get_element_name()
	end)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end

	ok, value = pcall(function()
		return pytha.get_element_name(element)
	end)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end

	return fallback or ""
end

function safe_get_element_type(element)
	if element == nil then
		return nil
	end

	local ok, value = pcall(function()
		return pytha.get_element_type(element)
	end)
	if ok then
		return value
	end

	ok, value = pcall(function()
		return element:get_element_type()
	end)
	if ok then
		return value
	end

	return nil
end

function is_group(element)
	return safe_get_element_type(element) == "group"
end

function is_part_like(element)
	local t = safe_get_element_type(element)
	return t == "part" or t == "ngo"
end

function elements_equal(a, b)
	return a == b
end

function array_contains_handle(arr, handle)
	for _, v in ipairs(arr) do
		if v == handle then
			return true
		end
	end
	return false
end

function add_unique_handle(arr, handle)
	if not array_contains_handle(arr, handle) then
		table.insert(arr, handle)
	end
end

function get_bbox_for_elements(elements)
	local bbox_min = { math.huge, math.huge, math.huge }
	local bbox_max = { -math.huge, -math.huge, -math.huge }

	for _, element in ipairs(elements) do
		local loc_bbox = pytha.get_element_bounding_box(element)
		if loc_bbox ~= nil and loc_bbox[1] ~= nil and loc_bbox[2] ~= nil then
			bbox_min = {
				math.min(loc_bbox[1][1], bbox_min[1]),
				math.min(loc_bbox[1][2], bbox_min[2]),
				math.min(loc_bbox[1][3], bbox_min[3])
			}
			bbox_max = {
				math.max(loc_bbox[2][1], bbox_max[1]),
				math.max(loc_bbox[2][2], bbox_max[2]),
				math.max(loc_bbox[2][3], bbox_max[3])
			}
		end
	end

	return bbox_min, bbox_max
end

function bbox_size_and_center(bbox_min, bbox_max)
	local size_x = bbox_max[1] - bbox_min[1]
	local size_y = bbox_max[2] - bbox_min[2]
	local size_z = bbox_max[3] - bbox_min[3]

	local center_p = {
		0.5 * (bbox_min[1] + bbox_max[1]),
		0.5 * (bbox_min[2] + bbox_max[2]),
		0.5 * (bbox_min[3] + bbox_max[3])
	}

	return size_x, size_y, size_z, center_p
end

function required_window_for_aspect(w, h, factor, target_ratio)
	local ww = w * factor
	local hh = h * factor

	if ww <= 0 then ww = 1 end
	if hh <= 0 then hh = 1 end

	local r = ww / hh
	if r < target_ratio then
		ww = hh * target_ratio
	else
		hh = ww / target_ratio
	end

	return ww, hh
end

function centered_window(c1, c2, w, h)
	return { c1 - 0.5 * w, c2 - 0.5 * h },
	       { c1 + 0.5 * w, c2 + 0.5 * h }
end

function get_part_dimensions(part)
	local bbox_min, bbox_max = get_bbox_for_elements({part})
	local sx, sy, sz = bbox_size_and_center(bbox_min, bbox_max)
	return round_dim(sx), round_dim(sy), round_dim(sz)
end

function make_part_signature(part)
	local name = safe_get_name(part, "")
	local sx, sy, sz = get_part_dimensions(part)
	return string.format("%s|%.2f|%.2f|%.2f", name, sx, sy, sz), name
end


-- =========================================================
-- Tree node helpers
-- =========================================================

function make_group_node(group_handle)
	return {
		handle = group_handle,
		is_group = true,
		children = {},
		parent = nil
	}
end

function make_part_node(part_handle)
	return {
		handle = part_handle,
		is_group = false,
		children = {},
		parent = nil
	}
end

function attach_child(parent_node, child_node)
	child_node.parent = parent_node
	table.insert(parent_node.children, child_node)
end


-- =========================================================
-- Group / selection analysis
-- =========================================================

function is_descendant_of_or_same(element, ancestor_group)
	if element == nil or ancestor_group == nil then
		return false
	end

	if element == ancestor_group then
		return true
	end

	local current = element
	while current ~= nil do
		if current == ancestor_group then
			return true
		end
		current = pytha.get_element_parent_group(current)
	end

	return false
end

function get_selected_elements_under_member(selected_elements, member)
	local result = {}

	for _, elem in ipairs(selected_elements) do
		if elem == member or is_descendant_of_or_same(elem, member) then
			table.insert(result, elem)
		end
	end

	return result
end

function group_selected_by_common_group(selected_elements)
	local clusters = {}

	for _, elem in ipairs(selected_elements) do
		local placed = false

		for _, cluster in ipairs(clusters) do
			local cg = pytha.get_element_common_group({cluster[1], elem})
			if cg ~= nil then
				table.insert(cluster, elem)
				placed = true
				break
			end
		end

		if not placed then
			table.insert(clusters, {elem})
		end
	end

	return clusters
end


-- =========================================================
-- Build the tree from selected elements
-- =========================================================

function build_subtree_from_selection(selected_elements)
	if selected_elements == nil or #selected_elements == 0 then
		return nil
	end

	-- If there is exactly one selected element and it is a part-like object,
	-- that is a leaf.
	if #selected_elements == 1 and is_part_like(selected_elements[1]) then
		return make_part_node(selected_elements[1])
	end

	-- Try to find the common group for this whole set.
	local common_group = pytha.get_element_common_group(selected_elements)

	-- No common group: this selection belongs to multiple separate roots.
	-- This case should normally be handled one level higher, but keep it safe.
	if common_group == nil then
		if #selected_elements == 1 then
			if is_group(selected_elements[1]) then
				local gnode = make_group_node(selected_elements[1])
				return gnode
			else
				return make_part_node(selected_elements[1])
			end
		end
		return nil
	end

	local node = make_group_node(common_group)

	-- Split the selected elements by the DIRECT members of the common group.
	local members = pytha.get_group_members(common_group)
	if members == nil then
		return node
	end

	for _, member in ipairs(members) do
		local subset = get_selected_elements_under_member(selected_elements, member)

		if #subset > 0 then
			local mtype = safe_get_element_type(member)

			if mtype == "group" then
				local child = build_subtree_from_selection(subset)
				if child ~= nil then
					attach_child(node, child)
				end
			elseif mtype == "part" or mtype == "ngo" then
				-- For direct part members, always create a leaf once.
				local child = make_part_node(member)
				attach_child(node, child)
			end
		end
	end

	return node
end

function build_selection_forest(selected_elements)
	local roots = {}

	local clusters = group_selected_by_common_group(selected_elements)

	for _, cluster in ipairs(clusters) do
		local node = build_subtree_from_selection(cluster)
		if node ~= nil then
			table.insert(roots, node)
		end
	end

	return roots
end


-- =========================================================
-- Traversal / collection
-- =========================================================

function traverse_groups(node, fn)
	if node == nil then
		return
	end

	if node.is_group then
		fn(node)
	end

	for _, child in ipairs(node.children) do
		traverse_groups(child, fn)
	end
end

function traverse_parts(node, fn)
	if node == nil then
		return
	end

	if not node.is_group then
		fn(node)
		return
	end

	for _, child in ipairs(node.children) do
		traverse_parts(child, fn)
	end
end

function collect_all_parts_from_group_handle(group_handle)
	local result = {}

	local function recurse(group_h)
		local members = pytha.get_group_members(group_h)
		if members == nil then
			return
		end

		for _, member in ipairs(members) do
			local t = safe_get_element_type(member)

			if t == "group" then
				recurse(member)
			elseif t == "part" or t == "ngo" then
				add_unique_handle(result, member)
			end
		end
	end

	recurse(group_handle)
	return result
end

function collect_unique_part_entries(roots)
	local signatures = {}
	local ordered = {}

	for _, root in ipairs(roots) do
		traverse_parts(root, function(part_node)
			if is_part_like(part_node.handle) then
				local sig, name = make_part_signature(part_node.handle)

				if signatures[sig] == nil then
					signatures[sig] = {
						part = part_node.handle,
						count = 1,
						name = name
					}
					table.insert(ordered, signatures[sig])
				else
					signatures[sig].count = signatures[sig].count + 1
				end
			end
		end)
	end

	return ordered
end


-- =========================================================
-- Plot helpers
-- =========================================================

function insert_quantity_label(sheet, count)
	if count == nil or count <= 1 then
		return
	end

	pyplot.insert_text(sheet, tostring(count), {
		position = {10, 200},
		size = 10,
		font = "Arial",
		bold = true,
		orientation = "left"
	})
end

function insert_page_title(sheet, text)
	if text == nil or text == "" then
		return
	end

	pyplot.insert_text(sheet, text, {
		position = {148.5, 202},
		size = 4,
		font = "Arial",
		bold = true,
		orientation = "center"
	})
end

function insert_orthographic_and_axo_details(sheet, parts)
	local bbox_min, bbox_max = get_bbox_for_elements(parts)
	local size_x, size_y, size_z, center_p = bbox_size_and_center(bbox_min, bbox_max)

	local area_xz = size_x * size_z
	local area_yz = size_y * size_z

	local front_view
	local side_view
	if area_xz >= area_yz then
		front_view = "xz"
		side_view = "yz"
	else
		front_view = "yz"
		side_view = "xz"
	end

	local sheet_w = 297
	local sheet_h = 210
	local margin = 20
	local gap = 10

	local cell_w = (sheet_w - 2 * margin - gap) / 2
	local cell_h = (sheet_h - 2 * margin - gap) / 2
	local cell_ratio = cell_w / cell_h

	local pos_front = { margin + 0.5 * cell_w, sheet_h - margin - 0.5 * cell_h }
	local pos_side  = { margin + cell_w + gap + 0.5 * cell_w, sheet_h - margin - 0.5 * cell_h }
	local pos_top   = { margin + 0.5 * cell_w, margin + 0.5 * cell_h }
	local pos_axo   = { margin + cell_w + gap + 0.5 * cell_w, margin + 0.5 * cell_h }

	local graphic_flags_ortho = {"edges"}
	local graphic_flags_axo = {"edges", "solid"}

	local pad = 1.05

	local req_w_xz, req_h_xz = required_window_for_aspect(size_x, size_z, pad, cell_ratio)
	local req_w_yz, req_h_yz = required_window_for_aspect(size_y, size_z, pad, cell_ratio)
	local req_w_xy, req_h_xy = required_window_for_aspect(size_x, size_y, pad, cell_ratio)

	local common_units_per_mm = math.max(
		req_w_xz / cell_w,
		req_h_xz / cell_h,
		req_w_yz / cell_w,
		req_h_yz / cell_h,
		req_w_xy / cell_w,
		req_h_xy / cell_h
	)

	local common_view_w = common_units_per_mm * cell_w
	local common_view_h = common_units_per_mm * cell_h

	local cx = 0.5 * (bbox_min[1] + bbox_max[1])
	local cy = 0.5 * (bbox_min[2] + bbox_max[2])
	local cz = 0.5 * (bbox_min[3] + bbox_max[3])

	local view_min_xz, view_max_xz = centered_window(cx, cz, common_view_w, common_view_h)
	local view_min_yz, view_max_yz = centered_window(cy, cz, common_view_w, common_view_h)
	local view_min_xy, view_max_xy = centered_window(cx, cy, common_view_w, common_view_h)

	local vmin_front, vmax_front
	if front_view == "xz" then
		vmin_front, vmax_front = view_min_xz, view_max_xz
	else
		vmin_front, vmax_front = view_min_yz, view_max_yz
	end

	local vmin_side, vmax_side
	if side_view == "xz" then
		vmin_side, vmax_side = view_min_xz, view_max_xz
	else
		vmin_side, vmax_side = view_min_yz, view_max_yz
	end

	pyplot.insert_detail(sheet, {
		view = front_view,
		position = pos_front,
		size = {cell_w, cell_h},
		view_min = vmin_front,
		view_max = vmax_front,
		graphic_flags = graphic_flags_ortho
	}, parts)

	pyplot.insert_detail(sheet, {
		view = side_view,
		position = pos_side,
		size = {cell_w, cell_h},
		view_min = vmin_side,
		view_max = vmax_side,
		graphic_flags = graphic_flags_ortho
	}, parts)

	pyplot.insert_detail(sheet, {
		view = "xy",
		position = pos_top,
		size = {cell_w, cell_h},
		view_min = view_min_xy,
		view_max = view_max_xy,
		graphic_flags = graphic_flags_ortho
	}, parts)

	pyplot.insert_detail(sheet, {
		view = "axo",
		position = pos_axo,
		size = {cell_w, cell_h},
		scale = common_units_per_mm,
		center = center_p,
		tilt = 35,
		rotation = 45,
		graphic_flags = graphic_flags_axo
	}, parts)
end

function insert_full_page_axo_detail(sheet, parts)
	local bbox_min, bbox_max = get_bbox_for_elements(parts)
	local size_x, size_y, size_z, center_p = bbox_size_and_center(bbox_min, bbox_max)

	local sheet_w = 297
	local sheet_h = 210
	local margin_left = 15
	local margin_right = 15
	local margin_bottom = 15
	local title_band = 22

	local avail_w = sheet_w - margin_left - margin_right
	local avail_h = sheet_h - margin_bottom - title_band

	local pos = {
		margin_left + 0.5 * avail_w,
		margin_bottom + 0.5 * avail_h
	}

	local max_span = math.max(size_x, size_y, size_z)
	if max_span <= 0 then
		max_span = 1
	end

	local units_per_mm = math.max(
		max_span / (avail_w * 0.70),
		max_span / (avail_h * 0.70)
	)
	if units_per_mm <= 0 then
		units_per_mm = 1
	end

	pyplot.insert_detail(sheet, {
		view = "axo",
		position = pos,
		size = {avail_w, avail_h},
		scale = units_per_mm,
		center = center_p,
		tilt = 35,
		rotation = 45,
		graphic_flags = {"edges", "solid"}
	}, parts)
end


-- =========================================================
-- Page creators
-- =========================================================

function create_group_plot_page(template_file, group_node)
	local sheet = create_sheet_from_template(template_file, "Group Plot")
	local group_name = safe_get_name(group_node.handle, "Group")
	insert_page_title(sheet, group_name)
	insert_orthographic_and_axo_details(sheet, group_node)

	return sheet
end

function create_individual_part_page(template_file, part, count, display_name)
	local sheet = create_sheet_from_template(template_file, "Part Plot")
	local name = display_name or safe_get_name(part, "Part")
	insert_page_title(sheet, name)
	insert_quantity_label(sheet, count)
	insert_orthographic_and_axo_details(sheet, {part})
	
	return sheet
end