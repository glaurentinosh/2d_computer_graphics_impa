local facade = require"facade"
local image = require"image"
local chronos = require"chronos"

local unpack = table.unpack
local floor = math.floor

local _M = facade.driver()
setmetatable(_ENV, { __index = _M } )

local background = _M.solid_color(_M.color.white)

local function stderr(...)
    io.stderr:write(string.format(...))
end

--------------------------------------
-- VARIABLES AND FUNCTIONS

myAccelerated = {}

function createEdge(initialPoint, endPoint) 
    local edge = {}

    -- Set minimum and maximum Y coordinates for the edge

    if (initialPoint[2] < endPoint[2]) then
        edge["Ymin"] = initialPoint[2]
        edge["Ymax"] = endPoint[2]
    else
        edge["Ymax"] = initialPoint[2]
        edge["Ymin"] = endPoint[2]
    end

    -- Implicit line
    -- ax1 + by1 + c = 0, ax2 + by2 + c = 0
    -- a = y2 - y1, b = -(x2 - x1), c = - ax1 - by1

    local line = {}
    line[1] = endPoint[2] - initialPoint[2]
    line[2] = initialPoint[1] - endPoint[1]
    line[3] = -line[1]*initialPoint[1] -line[2]*initialPoint[2]
    edge["line"]= line

    return edge
end

function createMatrixByTransformation(xf)
    matrix = {}     -- matrix to be returned
    index = 1       -- index of input xf          
    for i=1,3 do
      matrix[i] = {}     
      for j=1,3 do
        matrix[i][j] = xf[index]
        index = index + 1
      end
    end
    return matrix
end

function matrixProduct(m1, m2)
    matrix = {}     -- matrix to be returned          
    for i=1,3 do
      matrix[i] = {}     
      for j=1,3 do
        matrix[i][j] = 0
        for k=1,3 do
            matrix[i][j] = matrix[i][j] + m1[i][k]*m2[k][j]
        end
      end
    end
    return matrix
end

function matrixVectorProduct(m1,v1)
    vector = {}     -- matrix to be returned          
    for i=1,3 do
      vector[i] = 0     
      for j=1,3 do
        vector[i] = vector[i] + m1[i][j]*v1[j]
      end
    end
    return vector
end

function innerProduct(v1, v2)
    result = 0
    for i=1,3 do
        result = result + v1[i]*v2[i]
    end
    return result
end

function quadraticForm(matrix, vector) -- x^T A x, for quadrics
    local matrix_vector = matrixVectorProduct(matrix, vector) -- Ax = y
    return innerProduct(vector, matrix_vector) -- x^T A x = x^T y = <x, y>
end

function countIntersections(edges, x, y)
    local intersections = 0

    for index, edge in pairs(edges) do
        if ( (y < edge["Ymax"]) and (y >= edge["Ymin"]) ) then
            local line = edge["line"]
            if (line[1] == 0) then
                intersections = intersections -- horizontal line, no intersections
            else 
                local lineValue = line[1]*x + line[2]*y + line[3]
                if (edge["line"][1] > 0 and lineValue > 0) then
                    intersections = intersections + 1
                elseif (edge["line"][1] < 0 and lineValue < 0) then
                    intersections = intersections - 1
                end
            end
        end
    end

    return intersections
end




-- ----------------
-- SAMPLE
-------------------

local function sample(accelerated, x, y)
    -- This function should return the color of the sample
    -- at coordinates (x,y).
    -- Here, we simply return r = g = b = a = 1.
    -- It is up to you to compute the correct color!


    -- local edges = myAccelerated["edges"]

    local color = 0
    local scene = accelerated

    -- index of accelerated data (one for every pixel)
    local shape_index = 1

    scene:get_scene_data():iterate{
        painted_shape = function(self, rule, shape, paint)
            local shapeAccelerated = myAccelerated[shape_index]
            local dealAs = shapeAccelerated["dealAs"]

            -- Case POLYGON (including TRIANGLE)
            if dealAs == "countIntersections" then
                local edges = shapeAccelerated["edges"]
                intersections = countIntersections(edges, x, y)

                --local windingRule = tostring(winding_rule)

                local intersectionsBool = (intersections ~= 0)
                if rule == winding_rule.odd then
                    intersectionsBool = (intersections % 2 == 1)
                end

                if (intersectionsBool) then -- non-zero
                    color = paint:get_solid_color()
                end

            -- Case ELLIPSE (including CIRCLE)
            elseif dealAs == "testInsideEllipse" then
                local ellipse = shapeAccelerated["ellipse"]
                --local squaredRadius = circle["squaredRadius"]
                --local center = circle["center"]

                local ellipseMatrix = createMatrixByTransformation(ellipse)

                local ellipseValue = quadraticForm(ellipseMatrix, {x, y, 1})
                
                if ellipseValue < 0 then
                    color = paint:get_solid_color()
                end
            end
            shape_index = shape_index + 1
        end
    }
    
    if ( color ~= 0 ) then
        return color[1], color[2], color[3],1
    end
    return 1,1,1,1 -- no color painted
end

-------------------
--
------------------



local function parse(args)
	local parsed = {
		pattern = nil,
		tx = nil,
		ty = nil,
        linewidth = nil,
		maxdepth = nil,
		p = nil,
		dumptreename = nil,
		dumpcellsprefix = nil,
	}
    local options = {
        { "^(%-tx:(%-?%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.tx = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { "^(%-ty:(%-?%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.ty = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { "^(%-p:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.p = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { ".*", function(all)
            error("unrecognized option " .. all)
        end }
    }
    -- process options
    for i, arg in ipairs(args) do
        for j, option in ipairs(options) do
            if option[2](arg:match(option[1])) then
                break
            end
        end
    end
    return parsed
end



----------------------------------------
-- ACCELERATE
----------------------------------------

function _M.accelerate(scene, window, viewport, args)
    local parsed = parse(args)
    stderr("parsed arguments\n")
    for i,v in pairs(parsed) do
        stderr("  -%s:%s\n", tostring(i), tostring(v))
    end
    -- This function should inspect the scene and pre-process it into a better
    -- representation, an accelerated representation, to simplify the job of
    -- sample(accelerated, x, y).
    -- Here, we simply print some info about the scene_data and return the
    -- unmodified scene.
    scene = scene:windowviewport(window, viewport)
    stderr("scene xf %s\n", scene:get_xf())

    -- scene transformation matrix
    local scene_xf = createMatrixByTransformation(scene:get_xf())

    -- index of accelerated data (one for every pixel)
    local shape_index = 1

    scene:get_scene_data():iterate{
        painted_shape = function(self, winding_rule, shape, paint)
            myAccelerated[shape_index] = {}

            stderr("painted %s %s %s\n", winding_rule, shape:get_type(), paint:get_type())
            stderr("  xf s %s\n", shape:get_xf())

            local shapeType = shape:get_type()
            local paintColor = paint:get_solid_color()
            local shape_xf = createMatrixByTransformation(shape:get_xf())

            -- Transformation scene+shape
            shape_xf = matrixProduct(scene_xf, shape_xf)

            myAccelerated[shape_index]["shapeType"] = shapeType
            myAccelerated[shape_index]["color"] = paintColor


            -- Case TRIANGLE
            if shapeType == shape_type.triangle then
                local tdata = shape:get_triangle_data()
                local vertices = {}
                local edges = {}

                print("\tp1", tdata:get_x1(), tdata:get_y1())
                print("\tp2", tdata:get_x2(), tdata:get_y2())
                print("\tp3", tdata:get_x3(), tdata:get_y3())

                -- points in affine coordinates
                vertices[1] = {tdata:get_x1(),tdata:get_y1(), 1}
                vertices[2] = {tdata:get_x2(),tdata:get_y2(), 1}
                vertices[3] = {tdata:get_x3(),tdata:get_y3(), 1}

                -- transform points with scene+shape transformation
                for index,value in pairs(vertices) do
                    vertices[index] = matrixVectorProduct(shape_xf, value)
                end

                -- set edges
                local edge12 = createEdge(vertices[1], vertices[2])
                local edge23 = createEdge(vertices[2], vertices[3])
                local edge31 = createEdge(vertices[3], vertices[1])

                edges = {edge12, edge23, edge31}

                myAccelerated[shape_index]["edges"] = edges
                myAccelerated[shape_index]["dealAs"] = "countIntersections"


            -- Case POLYGON
            elseif shapeType == shape_type.polygon then
                local pdata = shape:get_polygon_data()
                local coords = pdata:get_coordinates()
                
                local edges = {}
                local vertices = {}

                vertices[1] = {coords[1], coords[2], 1} -- find the first vertex
                print("coords", coords[1], coords[2])

                -- transforming ...
                vertices[1] = matrixVectorProduct(shape_xf, vertices[1])

                local numVtx = 1  -- number of vertices, using as an index

                for i = 4, #coords, 2 do -- starting with i = 4
                    numVtx = numVtx + 1

                    -- appending new vertex
                    vertices[numVtx] = {coords[i-1], coords[i], 1}
                    print(coords[i-1], coords[i])

                    -- transforming vertex
                    vertices[numVtx] = matrixVectorProduct(shape_xf, vertices[numVtx])

                    -- forming edge with previous vertex
                    edges[numVtx - 1] = createEdge(vertices[numVtx - 1], vertices[numVtx])
                end

                -- forming edge with the first vertex
                edges[numVtx] = createEdge(vertices[numVtx], vertices[1])

                myAccelerated[shape_index]["edges"] = edges
                myAccelerated[shape_index]["dealAs"] = "countIntersections"


            -- Case CIRCLE
            elseif shapeType == shape_type.circle then
                local cdata = shape:get_circle_data()
                
                local center = {cdata:get_cx(), cdata:get_cy(), 1}
                local radius = cdata:get_r()

                print("\tc", center[1], center[2])
                print("\tr", radius)


                local unitCircle = projectivity(1,0,0,0,1,0,0,0,-1)

                local translationMatrix = projectivity(radius,0,center[1],0,radius,center[2],0,0,1):inverse()

                local circle = translationMatrix:transpose()*unitCircle*translationMatrix

                local shapeScene_xf = shape:get_xf():transformed(scene:get_xf()):inverse() -- scene*shape

                local ellipse = shapeScene_xf:transpose()*circle*shapeScene_xf

                myAccelerated[shape_index]["ellipse"] = ellipse
                myAccelerated[shape_index]["dealAs"] = "testInsideEllipse"


            else
                print("not a triangle"); print("not at all")
            end

            shape_index = shape_index + 1
        end,
    }
    -- It is up to you to do better!
    return scene
end

---------------------------------------
--
---------------------------------------



function _M.render(accelerated, window, viewport, file, args)
    local parsed = parse(args)
    stderr("parsed arguments\n")
    for i,v in pairs(parsed) do
        stderr("  -%s:%s\n", tostring(i), tostring(v))
    end
local time = chronos.chronos()
    -- Get viewport to compute pixel centers
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
    local width, height = vxmax-vxmin, vymax-vymin
    assert(width > 0, "empty viewport")
    assert(height > 0, "empty viewport")
    -- Allocate output image
    local img = image.image(width, height, 4)
    -- Render
    for i = 1, height do
stderr("\r%5g%%", floor(1000*i/height)/10)
        local y = vymin+i-1.+.5
        for j = 1, width do
            local x = vxmin+j-1+.5
            img:set_pixel(j, i, sample(accelerated, x, y))
        end
    end
stderr("\n")
stderr("rendering in %.3fs\n", time:elapsed())
time:reset()
    -- Store output image
    image.png.store8(file, img)
stderr("saved in %.3fs\n", time:elapsed())
end

return _M
