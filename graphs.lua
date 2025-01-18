-- Defining the colors
color0 = 0x01598C
color1 = 0x358C01
color2 = 0x8C5101
color3 = 0x89018C
color4 = 0x132A37
color5 = 0xB1FF82
color6 = 0xFFCA82
color7 = 0xFD82FF
require 'cairo'

-- Cache to store the network interface name
local network_interface_cache = nil
local graphs_config = {}

-- Function to get the network interface name
function get_network_interface_name()
    if not network_interface_cache then
        local handle = io.popen("nmcli device status | awk '/ethernet/ && /connected/ {print $1} /wifi/ {print $1}'")
        network_interface_cache = handle:read("*a"):match("^%s*(.-)%s*$")
        handle:close()
        print("Network interface found: " .. (network_interface_cache or "none"))
    end
    return network_interface_cache
end

-- Function to create graph configurations
local function generate_graph_config(name, color, max, height)
    local is_cpu = name:match("^cpu") ~= nil
    return {
        name = is_cpu and "cpu" or name,
        arg = is_cpu and name or get_network_interface_name(),
        max = is_cpu and 100 or max,
        width = 220,
        height = is_cpu and 75 or height,
        nb_values = is_cpu and 100 or 76,
        autoscale = not is_cpu,
        x = 16,
        y = is_cpu and 512 or 180,
        foreground_border_size = 1,
        foreground_border_color = {{0, color, 1}},
        background = false,
        foreground = false,
        inverse = true,
    }
end

-- Function to define graph parameters
function initialize_all_graph_configs()
    graphs_config = {
        generate_graph_config("cpu1", color0),
        generate_graph_config("cpu2", color1),
        generate_graph_config("cpu3", color2),
        generate_graph_config("cpu4", color3),
        generate_graph_config("upspeedf", color0, 40, 20),
        generate_graph_config("downspeedf", color1, 40, 20)
    }
end

-- Function to check graph parameters
function validate_all_graph_config(config)
    if not config.name and not config.arg then
        print("No input values ... use parameters 'name' with 'arg' or only parameter 'arg'")
        return 1
    end
    if not config.max then
        print("No maximum value defined, use 'max' for name=" .. config.name .. " with arg=" .. config.arg)
        return 1
    end
    return 0
end

function conky_main_draw_graphs()
    -- Checks if the Conky window is open
    if conky_window == nil then return end
    
    -- Create drawing surface with window dimensions
    local w, h = conky_window.width, conky_window.height
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
    cr = cairo_create(cs)

    -- Number of updates
    updates = tonumber(conky_parse('${updates}'))
    updates_gap = 5
    
    -- First execution to configure the graphs
    if updates == 1 then
        initialize_all_graph_configs()  
        valid_config_status = 0
    
        -- Initialize each graph
        for _, graph_config in pairs(graphs_config) do
            graph_config.width = graph_config.width or 100
            graph_config.nb_values = graph_config.nb_values or graph_config.width
            graph_config.values = {}
            graph_config.beg = graph_config.nb_values
            for j = 1, graph_config.nb_values do
                graph_config.values[j] = 0
            end
            graph_config.flag_init = true    
            valid_config_status = valid_config_status + validate_all_graph_config(graph_config)
        end
    end

    -- If there's an error, abort execution
    if valid_config_status > 0 then
        print("ERROR: Check the graph_setting table")
        return
    end

    -- Draw graphs after update interval
    if updates > updates_gap then
        for _, graph_config in pairs(graphs_config) do
            -- Check if the graph should be drawn
            if graph_config.draw_me == true then graph_config.draw_me = nil end
            if (graph_config.draw_me == nil or conky_parse(tostring(graph_config.draw_me)) == "1") then
                graph_config.automax = 0
                local nb_values = graph_config.nb_values
                -- Update the graph values
                for j = 1, nb_values do
                    graph_config.values[j] = graph_config.values[j + 1] or 0
                    if j == nb_values then
                        local value = graph_config.name == "" and graph_config.arg or tonumber(conky_parse('${' .. graph_config.name .. " " .. graph_config.arg .. '}'))
                        graph_config.values[nb_values] = value
                    end
                    graph_config.automax = math.max(graph_config.automax, graph_config.values[j])
                    if graph_config.automax == 0 then graph_config.automax = 1 end
                end
                render_graph(graph_config)
            end
        end
    end

    -- Clean up Cairo resources
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    updates = nil
    updates_gap = nil
end

-- Main function to render the graph
function render_graph(graph_config)

    -- Converts RGB values to RGBA
    local function convert_rgb_to_rgba(colour)
        return ((colour[2] / 0x10000) % 0x100) / 255., ((colour[2] / 0x100) % 0x100) / 255., (colour[2] % 0x100) / 255., colour[3]
    end

    -- Defines the gradient orientation for the background and border of the graph
    local function linear_orientation(o, w, h)
        local p
        if o == "nn" then p = {w / 2, h, w / 2, 0}
        elseif o == "ne" then p = {w, h, 0, 0}
        elseif o == "ww" then p = {0, h / 2, w, h / 2}
        elseif o == "se" then p = {w, 0, 0, h}
        elseif o == "ss" then p = {w / 2, 0, w / 2, h}
        elseif o == "ee" then p = {w, h / 2, 0, h / 2}
        elseif o == "sw" then p = {0, 0, w, h}
        elseif o == "nw" then p = {0, h, w, 0}
        end
        return p
    end

    -- Defines the gradient orientation for the foreground and border of the graph
    local function linear_orientation_inv(o, w, h)
        local p
        if o == "ss" then p = {w / 2, h, w / 2, 0}
        elseif o == "sw" then p = {w, h, 0, 0}
        elseif o == "ee" then p = {0, h / 2, w, h / 2}
        elseif o == "nw" then p = {w, 0, 0, h}
        elseif o == "nn" then p = {w / 2, 0, w / 2, h}
        elseif o == "ww" then p = {w, h / 2, 0, h / 2}
        elseif o == "ne" then p = {0, 0, w, h}
        elseif o == "se" then p = {0, h, w, 0}
        end
        return p
    end

    -- Cancels drawing if not needed
    if graph_config.draw_me ~= nil and conky_parse(tostring(graph_config.draw_me)) ~= "1" then 
        return
    end

    -- Set default values for properties
    if graph_config.height == nil then graph_config.height = 20 end
    if graph_config.background == nil then graph_config.background = true end
    if graph_config.background_border_size == nil then graph_config.background_border_size = 0 end
    if graph_config.x == nil then graph_config.x = graph_config.background_border_size end
    if graph_config.y == nil then graph_config.y = conky_window.height - graph_config.background_border_size end
    if graph_config.background_color == nil then graph_config.background_color = {{0, 0x000000, .5}, {1, 0xFFFFFF, .5}} end
    if graph_config.background_border_color == nil then graph_config.background_border_color = {{1, 0xFFFFFF, 1}} end
    if graph_config.foreground == nil then graph_config.foreground = true end
    if graph_config.fg_colour == nil then graph_config.fg_colour = {{0, 0x00FFFF, 1}, {1, 0x0000FF, 1}} end
    if graph_config.foreground_border_size == nil then graph_config.foreground_border_size = 0 end
    if graph_config.foreground_border_color == nil then graph_config.foreground_border_color = {{1, 0xFFFF00, 1}} end
    if graph_config.autoscale == nil then graph_config.autoscale = false end
    if graph_config.inverse == nil then graph_config.inverse = false end
    if graph_config.angle == nil then graph_config.angle = 0 end
    if graph_config.bg_bd_orientation == nil then graph_config.bg_bd_orientation = "nn" end
    if graph_config.bg_orientation == nil then graph_config.bg_orientation = "nn" end
    if graph_config.fg_bd_orientation == nil then graph_config.fg_bd_orientation = "nn" end
    if graph_config.fg_orientation == nil then graph_config.fg_orientation = "nn" end

    -- Validates color tables
    for i = 1, #graph_config.fg_colour do
        if #graph_config.fg_colour[i] ~= 3 then
            print("error in fg_colour table")
            graph_config.fg_colour[i] = {1, 0x0000FF, 1}
        end
    end

    for i = 1, #graph_config.foreground_border_color do
        if #graph_config.foreground_border_color[i] ~= 3 then
            print("error in foreground_border_color table")
            graph_config.foreground_border_color[i] = {1, 0x00FF00, 1}
        end
    end

    for i = 1, #graph_config.background_color do
        if #graph_config.background_color[i] ~= 3 then
            print("error in background color table")
            graph_config.background_color[i] = {1, 0xFFFFFF, 0.5}
        end
    end

    for i = 1, #graph_config.background_border_color do
        if #graph_config.background_border_color[i] ~= 3 then
            print("error in background border color table")
            graph_config.background_border_color[i] = {1, 0xFFFFFF, 1}
        end
    end

    -- Calculates distortion parameters if necessary
    if graph_config.flag_init then
        if graph_config.skew_x == nil then
            graph_config.skew_x = 0
        else
            graph_config.skew_x = math.pi * graph_config.skew_x / 180
        end
        if graph_config.skew_y == nil then
            graph_config.skew_y = 0
        else
            graph_config.skew_y = math.pi * graph_config.skew_y / 180
        end
        graph_config.flag_init = false
    end

    -- Sets line style
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    -- Creates and applies distortion matrix
    local matrix0 = cairo_matrix_t:create()
    tolua.takeownership(matrix0)
    cairo_save(cr)
    cairo_matrix_init(matrix0, 1, graph_config.skew_y, graph_config.skew_x, 1, 0, 0)
    cairo_transform(cr, matrix0)

    local ratio = graph_config.width / graph_config.nb_values

    -- Adjusts the position of the graph on screen
    cairo_translate(cr, graph_config.x, graph_config.y)
    cairo_rotate(cr, graph_config.angle * math.pi / 180)
    cairo_scale(cr, 1, -1)

    -- Draw the background of the graph
    if graph_config.background then
        local pts = linear_orientation(graph_config.bg_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts[1], pts[2], pts[3], pts[4])
        for i = 1, #graph_config.background_color do
            cairo_pattern_add_color_stop_rgba(pat, graph_config.background_color[i][1], convert_rgb_to_rgba(graph_config.background_color[i]))
        end
        cairo_set_source(cr, pat)
        cairo_rectangle(cr, 0, 0, graph_config.width, graph_config.height)
        cairo_fill(cr)
        cairo_pattern_destroy(pat)
    end
    
    -- Autoscale configuration (if enabled)
    cairo_save(cr)
    if graph_config.autoscale then
        graph_config.max = graph_config.automax * 1.1
    end

    local scale_x = graph_config.width / (graph_config.nb_values - 1)
    local scale_y = graph_config.height / (graph_config.max or 1)

    -- Defines the first point of the graph
    if updates - updates_gap < graph_config.nb_values then
        graph_config.beg = graph_config.beg - 1
        if graph_config.beg < 0 then graph_config.beg = 0 end
    else
        graph_config.beg = 0
    end

    -- Adjusts for inversion (if necessary)
    if graph_config.inverse then
        cairo_scale(cr, -1, 1)
        cairo_translate(cr, -graph_config.width, 0)
    end
    
    -- Draw the graph (foreground)
    if graph_config.foreground then
        local pts_fg = linear_orientation_inv(graph_config.fg_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts_fg[1], pts_fg[2], pts_fg[3], pts_fg[4])
        for i = 1, #graph_config.fg_colour do
            cairo_pattern_add_color_stop_rgba(pat, 1 - graph_config.fg_colour[i][1], convert_rgb_to_rgba(graph_config.fg_colour[i]))
        end
        cairo_set_source(cr, pat)

        -- Starts the graph from the correct initial point
        local first_value = graph_config.values[graph_config.beg + 1] or 0
        cairo_move_to(cr, graph_config.beg * scale_x, first_value * scale_y)

        -- Continues drawing the graph lines
        for i = graph_config.beg + 1, graph_config.nb_values - 1 do
            local value = graph_config.values[i + 1] or 0
            cairo_line_to(cr, i * scale_x, value * scale_y)
        end

        -- Closes the path and fills it
        cairo_line_to(cr, (graph_config.nb_values - 1) * scale_x, 0)
        cairo_close_path(cr)
        cairo_fill(cr)
        cairo_pattern_destroy(pat)
    end

    -- Draws the graph's border (foreground)
    if graph_config.foreground_border_size > 0 then
        local pts = linear_orientation_inv(graph_config.fg_bd_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts[1], pts[2], pts[3], pts[4])
        for i = 1, #graph_config.foreground_border_color do
            cairo_pattern_add_color_stop_rgba(pat, 1 - graph_config.foreground_border_color[i][1], convert_rgb_to_rgba(graph_config.foreground_border_color[i]))
        end
        cairo_set_source(cr, pat)
        cairo_move_to(cr, graph_config.beg * scale_x, graph_config.values[graph_config.beg + 1] * scale_y)
        for i = graph_config.beg + 1, graph_config.nb_values - 1 do
            cairo_line_to(cr, i * scale_x, graph_config.values[i + 1] * scale_y)
        end
        cairo_set_line_width(cr, graph_config.foreground_border_size)
        cairo_stroke(cr)
        cairo_pattern_destroy(pat)
    end
        
    cairo_restore(cr)

    -- Draws the background border of the graph
    if graph_config.background_border_size > 0 then
        local pts = linear_orientation(graph_config.bg_bd_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts[1], pts[2], pts[3], pts[4])
        for i = 1, #graph_config.background_border_color do
            cairo_pattern_add_color_stop_rgba(pat, graph_config.background_border_color[i][1], convert_rgb_to_rgba(graph_config.background_border_color[i]))
        end
        cairo_set_source(cr, pat)
        cairo_rectangle(cr, 0, 0, graph_config.width, graph_config.height)
        cairo_set_line_width(cr, graph_config.background_border_size)
        cairo_stroke(cr)
        cairo_pattern_destroy(pat)
    end

    cairo_restore(cr)
end
