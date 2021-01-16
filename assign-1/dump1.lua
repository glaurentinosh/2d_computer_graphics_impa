local facade = require"facade"

local _M = facade.driver()
setmetatable(_ENV, { __index = _M } )

function _M.accelerate(scene, window, viewport, args)
    return scene
end

local print_shape = {
    [shape_type.triangle] = function(shape)
        local tdata = shape:get_triangle_data()
        print("\tp1", tdata:get_x1(), tdata:get_y1())
        print("\tp2", tdata:get_x2(), tdata:get_y2())
        print("\tp3", tdata:get_x3(), tdata:get_y3())
    end,

    [shape_type.circle] = function(shape)
        local cdata = shape:get_circle_data()
        print("\tc", cdata:get_cx(), cdata:get_cy())
        print("\tr", cdata:get_r())
    end,

    [shape_type.polygon] = function(shape)
        local pdata = shape:get_polygon_data()
        local coords = pdata:get_coordinates()
        for i = 2, #coords, 2 do
            local xi, yi = coords[i-1], coords[i]
            print("", i//2, xi, yi)
        end
    end,
}

local print_paint = {
    [paint_type.solid_color] = function(paint)
        local color = paint:get_solid_color()
        print("", table.unpack(color))
        local opacity = paint:get_opacity()
        print("", opacity)
    end
}

function _M.render(scene, window, viewport, file, args)
    local i = 1
    print("window", table.unpack(window))
    print("viewport", table.unpack(viewport))
    print("scene")
    print(scene:get_xf())
    scene:get_scene_data():iterate({
        painted_shape = function(self, winding_rule, shape, paint)
            print("painted shape", i)
            print(winding_rule)
            print(shape, shape:get_xf())
            print_shape[shape:get_type()](shape)
            print(paint, paint:get_xf())
            print_paint[paint:get_type()](paint)
            i = i + 1
        end
    })
end

return _M
