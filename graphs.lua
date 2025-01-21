-- Defining the colors
colors = {
    0x01598C,
    0x358C01,
    0x8C5101,
    0x89018C,
    0x132A37,
    0xB1FF82,
    0xFFCA82,
    0xFD82FF
}
cpuYAxis = 520
networkYAxis = 184
scale_x = 0
scale_y = 0
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

-- Function to get the number of CPUs
function get_num_cpus()
    local handle = io.popen("nproc")
    local num_cpus = handle:read("*a"):match("^%s*(%d+)%s*$")
    handle:close()
    return tonumber(num_cpus) or 1
end

-- Function to create graph configurations
function generate_graph_config(name, color)
    local is_cpu = name:match("^cpu") ~= nil
    return {
        name = is_cpu and "cpu" or name,
        arg = is_cpu and name or get_network_interface_name(),
        max = 100,
        width = 232,
        height = 80,
        nb_values = 24,
        autoscale = not is_cpu,
        x = 8,
        y = is_cpu and cpuYAxis or networkYAxis,
        foreground_border_size = 1,
        foreground_border_color = {{0, color, 1}},
        background = false,
        foreground = false,
        inverse = true,
        opacity = (name == "upspeedf" or name == "cpu1") and 1 or 0
    }
end

-- Function to define graph parameters
function initialize_all_graph_configs()
    -- Adds the network graphs
    table.insert(graphs_config, generate_graph_config("upspeedf", colors[1]))
    table.insert(graphs_config, generate_graph_config("downspeedf", colors[2]))

    -- Dynamically adds CPU graphs
    for i = 1, get_num_cpus() do
        table.insert(graphs_config, generate_graph_config("cpu" .. i, colors[i]))
    end
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

-- Function to draw the grid lines
function draw_grid(cr, graph_config)
    -- Convert the background color to RGBA and adjust opacity
    cairo_set_line_width(cr, 0.5)
    local r, g, b, a = convert_rgb_to_rgba(graph_config.background_border_color[1])
    cairo_set_source_rgba(cr, r, g, b, a * 0.1)

    -- Drawing vertical lines
    for i = 1, graph_config.nb_values - 1 do
        cairo_move_to(cr, i * scale_x, 0)
        cairo_line_to(cr, i * scale_x, graph_config.height)
        cairo_stroke(cr)
    end
    
    -- Drawing horizontal lines
    local step = graph_config.height / 8
    for i = 1, 8 do
        cairo_move_to(cr, 0, i * step)
        cairo_line_to(cr, graph_config.width, i * step)
        cairo_stroke(cr)
    end
end

-- Converts RGB values to RGBA
function convert_rgb_to_rgba(color)
    return ((color[2] / 0x10000) % 0x100) / 255., ((color[2] / 0x100) % 0x100) / 255., (color[2] % 0x100) / 255., color[3]
end

-- Defines the gradient orientation for the background and border of the graph
function linear_orientation(o, w, h)
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
function linear_orientation_inv(o, w, h)
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

-- Draws the graph's border (foreground)
function draw_graph_foreground_border(cr, graph_config)
    -- Set line style for rounded corners
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    -- Draw the border if size is greater than 0
    if graph_config.foreground_border_size > 0 then
        local pts = linear_orientation_inv(graph_config.fg_bd_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts[1], pts[2], pts[3], pts[4])

        -- Add color stops to the gradient pattern
        for _, color in ipairs(graph_config.foreground_border_color) do
            cairo_pattern_add_color_stop_rgba(pat, 1 - color[1], convert_rgb_to_rgba(color))
        end
        cairo_set_source(cr, pat)
        
        -- Draw the border starting from the initial point
        cairo_move_to(cr, graph_config.beg * scale_x, graph_config.values[graph_config.beg + 1] * scale_y)
        for i = graph_config.beg + 1, graph_config.nb_values - 1 do
            cairo_line_to(cr, i * scale_x, graph_config.values[i + 1] * scale_y)
        end

        -- Set line width and stroke
        cairo_set_line_width(cr, graph_config.foreground_border_size)
        cairo_stroke(cr)
        cairo_pattern_destroy(pat)
    end
end

-- Draws the background border of the graph
function draw_graph_background_border(cr, graph_config)
    if graph_config.background_border_size > 0 then
        local pts = linear_orientation(graph_config.bg_bd_orientation, graph_config.width, graph_config.height)
        local pat = cairo_pattern_create_linear(pts[1], pts[2], pts[3], pts[4])

        -- Add the color stops to the pattern
        for _, color in ipairs(graph_config.background_border_color) do
            cairo_pattern_add_color_stop_rgba(pat, color[1], convert_rgb_to_rgba(color))
        end

        cairo_set_source(cr, pat)
        cairo_rectangle(cr, 0, 0, graph_config.width, graph_config.height)
        cairo_set_line_width(cr, graph_config.background_border_size)
        cairo_stroke(cr)
        cairo_pattern_destroy(pat)
    end
end

-- Adjusts for inversion (if necessary)
function apply_graph_inversion(cr, graph_config)
    if graph_config.inverse then
        cairo_scale(cr, -1, 1)
        cairo_translate(cr, -graph_config.width, 0)
    end
end

-- Function to configure autoscale and calculate the scales
function configure_autoscale(graph_config)
    -- Autoscale configuration (if enabled)
    if graph_config.autoscale then graph_config.max = graph_config.automax * 1.1 end
    
    -- Calculate the scales and assign them to global variables
    scale_x = graph_config.width / (graph_config.nb_values - 1)
    scale_y = graph_config.height / (graph_config.max or 1)
end

-- Set default values for properties if they are not set
function setDefaultGraphConfig(graph_config)
    if graph_config.height == nil then graph_config.height = 20 end
    if graph_config.background == nil then graph_config.background = true end
    if graph_config.background_border_size == nil then graph_config.background_border_size = 0.4 end
    if graph_config.x == nil then graph_config.x = graph_config.background_border_size end
    if graph_config.y == nil then graph_config.y = conky_window.height - graph_config.background_border_size end
    if graph_config.background_color == nil then graph_config.background_color = {{0, 0x000000, .5}, {1, 0xFFFFFF, .5}} end
    if graph_config.background_border_color == nil then graph_config.background_border_color = {{1, 0xFFFFFF, graph_config.opacity}} end
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
end

-- Main function to render the graph
function render_graph(graph_config)
    -- Cancels drawing if not needed
    if graph_config.draw_me ~= nil and conky_parse(tostring(graph_config.draw_me)) ~= "1" then return end

    -- Set default values for properties
    setDefaultGraphConfig(graph_config)
    
    -- Calculates distortion parameters if necessary
    if graph_config.flag_init then
        graph_config.skew_x = (graph_config.skew_x or 0) * math.pi / 180
        graph_config.skew_y = (graph_config.skew_y or 0) * math.pi / 180
        graph_config.flag_init = false
    end

    -- Creates and applies distortion matrix
    local matrix0 = cairo_matrix_t:create()
    tolua.takeownership(matrix0)
    cairo_matrix_init(matrix0, 1, graph_config.skew_y, graph_config.skew_x, 1, 0, 0)
    cairo_transform(cr, matrix0)
    cairo_save(cr)
    
    -- Adjusts the position of the graph on screen
    local ratio = graph_config.width / graph_config.nb_values
    cairo_translate(cr, graph_config.x + graph_config.width, graph_config.y)
    cairo_rotate(cr, graph_config.angle * math.pi / 180)
    cairo_scale(cr, -1, -1)
    cairo_save(cr)

    -- Defines the first point of the graph
    graph_config.beg = (updates - updates_gap < graph_config.nb_values) and math.max(graph_config.beg - 1, 0) or 0

    -- Autoscale configuration and scale calculation
    configure_autoscale(graph_config)

    -- Render the grid
    draw_grid(cr, graph_config)
    
    -- Draw the background border of the graph
    draw_graph_background_border(cr, graph_config)
    cairo_restore(cr)
   
   -- Draw points from right to left if necessary
    apply_graph_inversion(cr, graph_config)
      
    -- Draw the graph border (foreground)
    draw_graph_foreground_border(cr, graph_config)
    cairo_restore(cr) 
end

-- Initialize all graphs with default settings
function initialize_graph(graph_config)
    graph_config.width = graph_config.width or 100
    graph_config.nb_values = graph_config.nb_values or graph_config.width
    graph_config.values = {}
    graph_config.beg = graph_config.nb_values
    for i = 1, graph_config.nb_values do
        graph_config.values[i] = 0
    end
    graph_config.flag_init = true
end

-- Update graph values based on the latest data
function update_graph_values(graph_config, nb_values)
    graph_config.automax = 0
    for j = 1, nb_values do
        graph_config.values[j] = graph_config.values[j + 1] or 0
        if j == nb_values then
            local value = graph_config.name == "" and graph_config.arg or tonumber(conky_parse('${' .. graph_config.name .. " " .. graph_config.arg .. '}'))
            graph_config.values[nb_values] = value
        end
        graph_config.automax = math.max(graph_config.automax, graph_config.values[j])
    end
    if graph_config.automax == 0 then graph_config.automax = 1 end
end

-- Draw a single graph if it's allowed
function draw_single_graph(graph_config)
    if graph_config.draw_me == true then graph_config.draw_me = nil end
    if (graph_config.draw_me == nil or conky_parse(tostring(graph_config.draw_me)) == "1") then
        update_graph_values(graph_config, graph_config.nb_values)
        render_graph(graph_config)
    end
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
            initialize_graph(graph_config)
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
            draw_single_graph(graph_config)
        end
    end

    -- Clean up Cairo resources
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    updates = nil
    updates_gap = nil
end
