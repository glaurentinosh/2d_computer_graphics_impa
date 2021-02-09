local facade = require"facade"
local image = require"image"
local chronos = require"chronos"
local filter = require"filter"

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

function bezier(t, points) -- De Casteljou
	local bezier_list = {}
	local m = #points - 1
	for j = 0,m do
		bezier_list[j+1] = {}
		for k = 0,m-j do
			bezier_list[j+1][k+1] = {}
			if j == 0 then
				bezier_list[j+1][k+1] = points[k+1]
			else
				for l=1,#points[1] do -- for each coordinate
					bezier_list[j+1][k+1][l] = (1-t)*bezier_list[j][k+1][l] + t*bezier_list[j][k+2][l]
				end
				--local x = (1-t)*bezier_list[j][k+1][1] + t*bezier_list[j][k+2][1]
				--local y = (1-t)*bezier_list[j][k+1][2] + t*bezier_list[j][k+2][2]
				--bezier_list[j+1][k+1] = {x,y}
			end
		end
	end
	return bezier_list[m+1][1]
end

function bezierNumeric(t, coords)
	local bezier_list = {}
	local m = #coords - 1
	for j = 0,m do
		bezier_list[j+1] = {}
		for k = 0,m-j do
			if j == 0 then
				bezier_list[j+1][k+1] = coords[k+1]
			else
				local coord = (1-t)*bezier_list[j][k+1] + t*bezier_list[j][k+2]
				bezier_list[j+1][k+1] = coord
			end
		end
	end
	return bezier_list[m+1][1]
end

function bezierDerivative(t, points)
	local newPoints = {}
	local N = #points - 1
	for i = 1,N do
		newPoints[i] = {}
		for l = 1,#points[1] do -- for each coordinate
			newPoints[i][l] = N*(points[i+1][l] - points[i][l])
		end
		--newPoints[i][1] = N*(points[i+1][1] - points[i][1])
		--newPoints[i][2] = N*(points[i+1][2] - points[i][2])
	end

	return bezier(t, newPoints)
end

function bezierDerivativeNumeric(t, coords)
	local newCoords = {}
	local N = #coords - 1
	for i = 1,N do
		newCoords[i] = N*(coords[i+1] - coords[i])
	end

	return bezierNumeric(t, newCoords)
end

function bezierSecondDerivative(t, points)
	local auxPoints = {}
	local newPoints = {}

	local N = #points - 1
	for i = 1,N do
		auxPoints[i] = {}
		for l = 1, #points[1] do -- for each coordinate
			auxPoints[i][l] = N*(points[i+1][l] - points[i][l])
		end
		-- auxPoints[i][1] = N*(points[i+1][1] - points[i][1])
		-- auxPoints[i][2] = N*(points[i+1][2] - points[i][2])
	end
	for i = 1,N-1 do
		newPoints[i] = {}
		for l = 1, #points[1] do -- for each coordinate
			newPoints[i][l] = N*(auxPoints[i+1][l] - auxPoints[i][l])
		end
		-- newPoints[i][1] = N*(auxPoints[i+1][1] - auxPoints[i][1])
		-- newPoints[i][2] = N*(auxPoints[i+1][2] - auxPoints[i][2])
	end

	return bezier(t, newPoints)
end

function blossom(points, args) -- De Casteljou for blossoms
	local blossom_list = {}
	local m = #points - 1

	for j = 0,m do
		blossom_list[j+1] = {}
		for k = 0,m-j do
			blossom_list[j+1][k+1] = {}
			if j == 0 then
				blossom_list[j+1][k+1] = points[k+1]
			else
				for l=1,#points[1] do
					blossom_list[j+1][k+1][l] = (1-args[j])*blossom_list[j][k+1][l] + args[j]*blossom_list[j][k+2][l]
				end
				--local x = (1-args[j])*blossom_list[j][k+1][1] + args[j]*blossom_list[j][k+2][1]
				--local y = (1-args[j])*blossom_list[j][k+1][2] + args[j]*blossom_list[j][k+2][2]
				--blossom_list[j+1][k+1] = {x,y}
			end
		end
	end
	return blossom_list[m+1][1]
end

function reparametrization(r, s, points)
	local newPoints = {}
	
	local bezier_r = bezier(r, points)
	local bezier_s = bezier(s, points)
	local args = {}

	for i=1,#points-1 do -- fill arguments of blossom
		args[i] = r
	end

	for i=1,#points-1 do -- fill new control points
		newPoints[i] = blossom(points, args)
		args[i] = s
	end
	newPoints[#points] = blossom(points, args) -- last iteration
	return newPoints
end

function bissection(low, high, y, func)
	local maxIter = 200
	local nIter = 0
	local err = 0.0001

	local mid = (low + high)/2
	local valueLow = y - func(low)
	local valueMid = y - func(mid)

	repeat
		if (valueMid > 0 and valueLow > 0) or (valueMid < 0 and valueLow < 0) then
			low = mid
		else
			high = mid
		end
		nIter = nIter + 1
		mid = (low + high)/2
		valueLow = y - func(low)
		valueMid = y - func(mid)
	until math.abs(valueMid) < err or nIter > maxIter 

	return mid
end

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

function createPolygon(coords, shape_xf)
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

    return edges
end	

function createBoundingBox(initialPoint, endPoint)
	local boundingBox = {}

    if (initialPoint[2] < endPoint[2]) then
        boundingBox["Ymin"] = initialPoint[2]
        boundingBox["Ymax"] = endPoint[2]
    else
        boundingBox["Ymax"] = initialPoint[2]
        boundingBox["Ymin"] = endPoint[2]
    end

    if (initialPoint[1] < endPoint[1]) then
        boundingBox["Xmin"] = initialPoint[1]
        boundingBox["Xmax"] = endPoint[1]
    else
        boundingBox["Xmax"] = initialPoint[1]
        boundingBox["Xmin"] = endPoint[1]
    end

    return boundingBox
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
    for i=1,#v1 do
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

function countIntersectionsPath(segments, x, y)
	local intersections = 0
	for key, segment in pairs(segments) do
		local boundingBox = segment["boundingBox"]
		local func_x = segment["func_x"]
		local func_y = segment["func_y"]
		local delta = segment["delta"] -- tells me if I have to sum or subtract 1 from intersections

	    if  y > boundingBox["Ymin"] and y <= boundingBox["Ymax"] and x <= boundingBox["Xmax"] then
	    	if (x < boundingBox["Xmin"]) then
	    		intersections = intersections + delta
	    	else
	    		local t_intersection = bissection(0, 1, y, func_y)
	    		local x_intersection = func_x(t_intersection)

	    		if (x < x_intersection) then
	    			intersections = intersections + delta
	    		end
	    	end
	    end
	end
	return intersections
end

function opacityAlphaBlending(color,opacity)
	local blendColor = {table.unpack(color)}
	if color[4] ~= nil then
		blendColor[4] = opacity*blendColor[4]
	else
		blendColor[4] = opacity
	end
	if blendColor[4] > 1 then print(blendColor[4]) end
	return blendColor
end

function alphaMultipliedRGB(rgba)
	local a = rgba[4]
	--if a == nil then return rgba end
	return {a*rgba[1], a*rgba[2], a*rgba[3], a}
end

function alphaDemultipliedRGB(rgba)
	local a = rgba[4]
	--if a == nil then return rgba end
	return{rgba[1]/a, rgba[2]/a, rgba[3]/a, a}
end 

function transparency(topColor, colors)
	local bottomColor = table.remove(colors)
	bottomColor = alphaMultipliedRGB(bottomColor)
	local newColor = {}
	local a = 1-topColor[4]

	for i=1,4 do
		newColor[i] = topColor[i] + a*bottomColor[i]
	end

	if #colors == 0 or newColor[4]>0.95 then
		return alphaDemultipliedRGB(newColor)
	end

	--table.insert(colors, newColor)
	return transparency(newColor, colors)	
end

function calculateColor(colors)
	local topColor = table.remove(colors)

	if #colors == 0 then -- if there is only one color
		local newColor = {}
		local bckColor = background:get_solid_color()
		local alpha = topColor[4]

		for i=1,3 do
			newColor[i] = alpha*topColor[i] + (1-alpha)*bckColor[i]
		end
		newColor[4] = 1

		return newColor
	end

	topColor = transparency(alphaMultipliedRGB(topColor), colors)
	local alpha = topColor[4]

	if alpha > 1 then
		return topColor
	end 

	local newColor = {}
	local bckColor = background:get_solid_color()

	for i=1,3 do
		newColor[i] = alpha*topColor[i] + (1-alpha)*bckColor[i]
	end
	newColor[4]=1

	return newColor
end

function getLinearGradient(paint, x, y)
    local lg = paint:get_linear_gradient_data()
    --local p1 = {lg:get_x1(), lg:get_y1()}
    --local p2 = {lg:get_x2(), lg:get_y2()}
    --local p = {x,y}

    local op1 = {x-lg:get_x1(), y-lg:get_y1()} -- p - p1
    local op2 = {lg:get_x2()-lg:get_x1(),lg:get_y2()-lg:get_y1()} -- p2 - p1

    -- linear gradient
    local gradientValue = innerProduct(op1, op2)/innerProduct(op2, op2)

    local ramp = lg:get_color_ramp()
    local spread = ramp:get_spread()

    local gradientValueNormalized = getSpread(spread, gradientValue)

    --local color = getRamp(ramp, gradientValueNormalized)
    return gradientValueNormalized
end

function getRadialGradient(paint, px, py, cx)
	local gradientValue = 0

	local A = 1 - cx*cx
	local B = 2*px*cx
	local C = -(px*px + py*py)

	local delta = math.sqrt(B*B - 4*A*C)
	--print("","Delta", delta)
	if A == 0 then
		gradientValue = -C/B
	else
		gradientValue = -B/(2*A) + delta/(2*A) -- I want the inverse
	end

	--if gradientValue < 0 then gradientValue = inf end

	--print("gradientValue", gradientValue)

	local lg = paint:get_radial_gradient_data()
	local ramp = lg:get_color_ramp()
	local spread = ramp:get_spread()

    local gradientValueNormalized = getSpread(spread, gradientValue)
    --print("NORMALI", gradientValueNormalized)

    --local color = getRamp(ramp, gradientValueNormalized)
    return gradientValueNormalized

end

function getSpread(spreadType, value)
	if spreadType == spread.clamp then
		return math.min(1, max(0,value))
	elseif spreadType == spread.wrap then
		return value - math.floor(value)
	elseif spreadType == spread.mirror then
		return 2*math.abs(0.5*value - math.floor(0.5*value + 0.5))
	elseif spreadType == spread.transparent then
		if value < 0 or value > 1 then return 5 end
		return value
	else
		print("Couldnt find spread method")
	end
end

function binarySearch(arr, num)--LEGACY
	local low = 1
	local high = #arr

	if num == arr[low] then return low end
	if num == arr[high] then return high-1 end

	while high - low > 1 do
		local mid = (low + high)//2
		if num == arr[mid] then return mid
		elseif num < arr[mid] then high = mid
		elseif num > arr[mid] then low = mid end
	end

	return low
end

function getRamp(ramp, value)--LEGACY
    local t = {} -- offset
    local c = {} -- color of stop

    for i, stop in ipairs(ramp:get_color_stops()) do
    	t[i] = stop:get_offset()
    	c[i] = stop:get_color()
        --print("", stop:get_offset(), "->", table.unpack(stop:get_color()))
    end

    local stopIndex = binarySearch(t,value)
    local low = t[stopIndex]
	local high = t[stopIndex+1]

	--local colorFound = ((low - value)*c[stopIndex]+(low) 

    return c[stopIndex]
end

function uniformSampling(ramp,opacity)
    local colors = {}
    local t = {} -- stops
    local c = {} -- color of stops

    t[1] = 0; c[1] = {} -- adding extra extremes

    for i, stop in ipairs(ramp:get_color_stops()) do
    	t[i+1] = stop:get_offset()
    	c[i+1] = stop:get_color()
        --print("", stop:get_offset(), "->", table.unpack(stop:get_color()))
    end 

    c[1] = c[2]; t[#t+1] = 1; c[#c+1] = c[#c]

    local delta = 0.001
    local curSample = 0
    
    for i=1,#t-1 do  --for all stop intervals
    	local inverseDenominator = 1/(t[i+1]-t[i])
    	print(inverseDenominator)
    	while curSample <= t[i+1] do
    		local interpolatedColor = {}
    		if curSample == t[i] then
    			interpolatedColor = {table.unpack(c[i])}
    		elseif curSample == t[i+1] then
    			interpolatedColor = {table.unpack(c[i+1])}
    		elseif curSample > t[i] and curSample < t[i+1] then
	    		for j=1,#c[i] do
			    	interpolatedColor[j] = ((t[i+1]-curSample)*c[i][j] + (curSample-t[i])*c[i+1][j])*inverseDenominator
	    		end
	    	end
	    	--print("SIZE", table.unpack(interpolatedColor))
	    	interpolatedColor = opacityAlphaBlending(interpolatedColor,opacity)
	    	table.insert(colors, interpolatedColor)
	    	curSample = curSample + delta
    	end
    end

    return colors
end


-- ----------------
-- SAMPLE
-------------------

local function sample(accelerated, x, y)
    -- This function should return the color of the sample
    -- at coordinates (x,y).
    -- Here, we simply return r = g = b = a = 1.
    -- It is up to you to compute the correct color!

    --stderr("\r%s\r%s",x,y)
    -- local edges = myAccelerated["edges"]

    local colors = {}
    --table.insert(colors, background:get_solid_color())
    local scene = accelerated

    -- index of accelerated data (one for every pixel)
    local shape_index = 1

    scene:get_scene_data():iterate{
        painted_shape = function(self, rule, shape, paint)
            local shapeAccelerated = myAccelerated[shape_index]
            local dealAs = shapeAccelerated["dealAs"]
            local intersections = 0

            -- Case POLYGON (including TRIANGLE)
            if dealAs == "countIntersections" then
                local edges = shapeAccelerated["edges"]
                intersections = countIntersections(edges, x, y)

            -- Case ELLIPSE (including CIRCLE)
            elseif dealAs == "testInsideEllipse" then
                local ellipse = shapeAccelerated["ellipse"]
                --local squaredRadius = circle["squaredRadius"]
                --local center = circle["center"]

                local ellipseMatrix = createMatrixByTransformation(ellipse)

                local ellipseValue = quadraticForm(ellipseMatrix, {x, y, 1})
                
                if ellipseValue < 0 then
                    --table.insert(colors,paint:get_solid_color())
                    intersections = 1
                end

            -- Case PATH    
            elseif dealAs == "boundingBox" then
            	
            	local linearSegments = shapeAccelerated["linearSegments"]
            	local quadraticSegments = shapeAccelerated["quadraticSegments"]
            	local cubicSegments = shapeAccelerated["cubicSegments"]
            	local rationalSegments = shapeAccelerated["rationalSegments"]

            	intersections = countIntersectionsPath(linearSegments, x, y)
            					+ countIntersectionsPath(quadraticSegments, x, y)
            					+ countIntersectionsPath(cubicSegments, x, y)
            					+ countIntersectionsPath(rationalSegments, x, y)

            	--if intersections ~=0 then print(intersections, table.unpack(paint:get_solid_color())) end

            else
            	print("weird dealAs value : ", dealAs)
            	table.insert(colors,paint:get_solid_color())
            end

            local intersectionsBool = (intersections ~= 0)
            if rule == winding_rule.odd then
                intersectionsBool = (intersections % 2 == 1)
            end

            if (intersectionsBool) then -- non-zero
            	local opacity = paint:get_opacity()
            	local paint_xf = paint:get_xf():inverse() --shapeAccelerated["xf"]
            	if paint:get_type() == paint_type.solid_color then
	            	local blendColor = opacityAlphaBlending(paint:get_solid_color(),opacity)
                	table.insert(colors, blendColor)

                elseif paint:get_type() == paint_type.linear_gradient then
                	--print("paint transformation", paint:get_xf())
                	local px, py = paint_xf:transformed(scene:get_xf():inverse()):apply(x, y, 1)
					local t_ramp = getLinearGradient(paint, px, py)
					local sampledColors = shapeAccelerated["sampledColors"]
					local sampleIndex = math.max(math.floor(#sampledColors*t_ramp),1)
					local colorFound = sampledColors[sampleIndex]
					--if t_ramp == 0 then print("cor encontrada", colorFound, "", sampleIndex) end
					table.insert(colors, colorFound)

                elseif paint:get_type() == paint_type.radial_gradient then
			        local simplerXf = shapeAccelerated["simplerXf"]
			        local px, py = simplerXf:apply(x,y,1) -- transformed pixel coordinates
			        local cx = shapeAccelerated["newCx"]
			        local t_ramp = getRadialGradient(paint,px,py,cx)
			        local sampledColors = shapeAccelerated["sampledColors"]
					local sampleIndex = math.max(math.floor(#sampledColors*t_ramp),1)
					local colorFound = sampledColors[sampleIndex]
					--if t_ramp == 0 then print("cor encontrada", colorFound, "", sampleIndex) end
					table.insert(colors, colorFound)
                else
                	print("unknown paint")
                end
            end

            shape_index = shape_index + 1
        end
    }
    
    if ( #colors > 0 ) then
    	local colorReturned = calculateColor(colors)
    	--print(table.unpack(colorReturned))
        return table.unpack(colorReturned)
    end
    return table.unpack(background:get_solid_color()) -- no color painted
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

    -- stack of transformations
    local transformationStack = {}
    transformationStack[1] = projectivity(1,0,0,0,1,0,0,0,1)

    -- index of accelerated data (one for every pixel)
    local shape_index = 1

    scene:get_scene_data():iterate{
        painted_shape = function(self, winding_rule, shape, paint)
            myAccelerated[shape_index] = {}

            stderr("painted %s %s %s\n", winding_rule, shape:get_type(), paint:get_type())
            stderr("  xf s %s\n", shape:get_xf())

            local shapeType = shape:get_type()

            local xf = shape:get_xf():transformed(scene:get_xf())
            xf = xf:transformed(transformationStack[#transformationStack])

            print("transformation depth", #transformationStack)

            local shape_xf = createMatrixByTransformation(xf)

            -- Transformation scene+shape
            --shape_xf = matrixProduct(scene_xf, shape_xf)

            --
            --
            --
            -- Deal with COLORS
            --
            --
            --
        	local opacity = paint:get_opacity()
        	print("Opa", opacity)
            if paint:get_type() == paint_type.linear_gradient then
            	local lg = paint:get_linear_gradient_data()
            	local ramp = lg:get_color_ramp()
		        print("", "p1", lg:get_x1(), lg:get_y1())
		        print("", "p2", lg:get_x2(), lg:get_y2())
        	    print("", ramp:get_spread())
			    for i, stop in ipairs(ramp:get_color_stops()) do
			        print("", stop:get_offset(), "->", table.unpack(stop:get_color()))
			    end
            	local sampledColors = uniformSampling(ramp,opacity)
            	myAccelerated[shape_index]["sampledColors"] = sampledColors
            	--myAccelerated[shape_index]["xf"] = xf
            end

            if paint:get_type() == paint_type.radial_gradient then
		        local lg = paint:get_radial_gradient_data()
		        local ramp = lg:get_color_ramp()
            	local sampledColors = uniformSampling(ramp,opacity)
            	myAccelerated[shape_index]["sampledColors"] = sampledColors

		        local cx = lg:get_cx()
		        local cy = lg:get_cy()
		        local fx = lg:get_fx()
		        local fy = lg:get_fy()
		        local r = lg:get_r()

		        -- translates focus to origin
		        local translationFocusOriginXf = projectivity(1, 0, -fx,0,1,-fy,0,0,1)

		        -- rotation
		        local rotationXf = projectivity(1,0,0,0,1,0,0,0,1)
		        local auxValue = (cy-fy)*(cy-fy)
		        if auxValue ~= 0 then
			        local focusCenterDist = math.abs(cy-fy)*math.sqrt(1 + (cx-fx)*(cx-fx)/auxValue) -- distance
					local vx = (cx - fx)/focusCenterDist -- cossine
			        local vy = (cy - fy)/focusCenterDist -- sine
			        rotationXf = projectivity(vx,vy,0,-vy,vx,0,0,0,1) -- it rotates clockwise
			    else
			    	if fx>cx then
			    		rotationXf = projectivity(-1,0,0,0,-1,0,0,0,1) -- 180 degrees
			    	end
		        end

		        -- scaling based on radius
		        local scalingFactor = 1/r
		        local scalingXf = projectivity(scalingFactor,0,0,0,scalingFactor,0,0,0,1)
		        
		        -- our simpler transformation
		        local simplerXf = scalingXf*rotationXf*translationFocusOriginXf

		        local newCx = simplerXf:apply(cx, cy, 1)

            	myAccelerated[shape_index]["simplerXf"] = simplerXf*paint:get_xf():inverse()*scene:get_xf():inverse()--*xf:inverse()
            	myAccelerated[shape_index]["newCx"] = newCx
            end

            myAccelerated[shape_index]["shapeType"] = shapeType


            -- Case TRIANGLE
            if shapeType == shape_type.triangle then
                local tdata = shape:get_triangle_data()
                --local vertices = {}
                --local edges = {}
                print("asPathdata", shape:as_path_data())
                

                print("\tp1", tdata:get_x1(), tdata:get_y1())
                print("\tp2", tdata:get_x2(), tdata:get_y2())
                print("\tp3", tdata:get_x3(), tdata:get_y3())

                local coords = {tdata:get_x1(), tdata:get_y1(),tdata:get_x2(), tdata:get_y2(),tdata:get_x3(), tdata:get_y3()}
                local edges = createPolygon(coords, shape_xf)

                myAccelerated[shape_index]["edges"] = edges
                myAccelerated[shape_index]["dealAs"] = "countIntersections"


            -- Case POLYGON
            elseif shapeType == shape_type.polygon then
                local pdata = shape:get_polygon_data()
                local coords = pdata:get_coordinates()
                
                local edges = createPolygon(coords, shape_xf)

                myAccelerated[shape_index]["edges"] = edges
                myAccelerated[shape_index]["dealAs"] = "countIntersections"


            -- Case RECT
        	elseif shapeType == shape_type.rect then
        		local rdata = shape:get_rect_data()
        		
        		local x0 = rdata:get_x()
        		local y0 = rdata:get_y()
        		local dx = rdata:get_width()
        		local dy = rdata:get_height()

				print("", rdata:get_x(), rdata:get_y())
        		print("", rdata:get_width(), rdata:get_height())

        		local coords = {x0,y0,x0+dx,y0,x0+dx,y0+dy,x0,y0+dy}
        		local edges = createPolygon(coords, shape_xf)

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

                local shapeScene_xf = xf:inverse() -- scene*shape

                local ellipse = shapeScene_xf:transpose()*circle*shapeScene_xf

                myAccelerated[shape_index]["ellipse"] = ellipse
                myAccelerated[shape_index]["dealAs"] = "testInsideEllipse"


            -- Case PATH
            elseif shapeType == shape_type.path then
            	local pdata = shape:get_path_data()
            	--local xf = shape:get_xf():transformed(scene:get_xf())

            	myAccelerated[shape_index]["dealAs"] = "boundingBox"
            	local beginContour = {}
            	local endOpenContour = {}
            	local linearSegments = {}
            	local quadraticSegments = {}
            	local cubicSegments = {}
            	local rationalSegments = {}
            	local shapeBoundingBox = {}

		        pdata:iterate(filter.make_input_path_f_xform(xf,{
		            begin_contour = function(self, x0, y0)
		                print("", "begin_contour", x0, y0)
		                beginContour = {x0,y0}
		            end,
		            end_open_contour = function(self, x0, y0)
		                print("", "end_open_contour", x0, y0)
		                endOpenContour = {x0,y0}
		                if beginContour ~= endOpenContour then
		                	local linearSegment = {}
		                	local boundingBox = createBoundingBox(endOpenContour, beginContour)
		                	local func_x = function(t)
		                		return (1-t)*endOpenContour[1] + t*beginContour[1]
		                	end
			                local func_y = function(t)
			                	return (1-t)*endOpenContour[2] + t*beginContour[2]
			                end
    		                local delta = 1

			                if y0 > beginContour[2] then
			                	delta = -1
			                end
			                linearSegment["boundingBox"] = boundingBox
			               	linearSegment["delta"] = delta
		                	linearSegment["func_x"] = func_x
		                	linearSegment["func_y"] = func_y
			                linearSegments[#linearSegments + 1] = linearSegment
		                end
		            end,
		            end_closed_contour = function(self, x0, y0)
		                print("", "end_closed_contour", x0, y0)
		                --myAccelerated[shape_index]["end_closed_contour"] = {x0,y0}
		            end,
		            linear_segment = function(self, x0, y0, x1, y1)
		                print("", "linear_segment", x0, y0, x1, y1)

		                local boundingBox = createBoundingBox({x0,y0},{x1,y1})
		                local points = {{x0,y0}, {x1,y1}}

		                local func_x = function(t)
		                	--return (1-t)*x0 + t*x1
		                	return bezier(t, points)[1]
		                end

		                local func_y = function(t)
		                	--return (1-t)*y0 + t*y1
		                	return bezier(t, points)[2]
		                end

		                local delta = 1

		                if y0 > y1 then
		                	delta = -1
		                end

		                local linearSegment = {}

		                linearSegment["boundingBox"] = boundingBox
		                linearSegment["delta"] = delta
		                --linearSegment["points"] = points
		                linearSegment["func_x"] = func_x
		                linearSegment["func_y"] = func_y
		                linearSegments[#linearSegments + 1] = linearSegment
		                --linearSegmentsIndex = linearSegmentsIndex + 1
		            end,
		            quadratic_segment = function(self, x0, y0, x1, y1, x2, y2)
		                print("", "quadratic_segment", x0, y0, x1, y1, x2, y2)

		                local points = {{x0,y0}, {x1,y1}, {x2,y2}}

		                local d_func_x = function(t)
		                	return bezierDerivative(t, points)[1]
		                end

		                local d_func_y = function(t)
		                	return bezierDerivative(t, points)[2]
		                end


		                local boundingBox_t = {0, 1}
		                -- check critical points in x
		                local crit_x = -1
		                if (d_func_x(0) < 0 and d_func_x(1) > 0) or (d_func_x(0) > 0 and d_func_x(1) < 0) then
		                	crit_x = bissection(0, 1, 0, d_func_x)
		                	table.insert(boundingBox_t, crit_x)
		                end

		                -- check critical points in y
		                local crit_y = -1
		                if (d_func_y(0) < 0 and d_func_y(1) > 0) or (d_func_y(0) > 0 and d_func_y(1) < 0) then
		                	crit_y = bissection(0, 1, 0, d_func_y)
		                	table.insert(boundingBox_t, crit_y)
		                end

		                -- sort critival points 
		                table.sort(boundingBox_t)

		                for i=2,#boundingBox_t do -- create quadratic segments
		                	local newPoints = reparametrization(boundingBox_t[i-1], boundingBox_t[i], points)

		                	local initialPoint = newPoints[1]
		                	local endPoint = newPoints[#newPoints]

							local boundingBox = createBoundingBox(initialPoint,endPoint)
			                
			                local delta = 1
			                if initialPoint[2] > endPoint[2] then
			                	delta = -1
			                end

    		                local func_x = function(t)
			                	return bezier(t, newPoints)[1]
			                end

			                local func_y = function(t)
			                	return bezier(t, newPoints)[2]
			                end
			                
			                local quadraticSegment = {}

			                quadraticSegment["boundingBox"] = boundingBox
			                quadraticSegment["func_x"] = func_x
			                quadraticSegment["func_y"] = func_y
			                quadraticSegment["delta"] = delta
			                quadraticSegments[#quadraticSegments + 1] = quadraticSegment		                	
		                end

		            end,
		            cubic_segment = function(self, x0, y0, x1, y1, x2, y2, x3, y3)
		                print("", "cubic_segment", x0, y0, x1, y1, x2, y2, x3, y3)


		                local points = {{x0,y0}, {x1,y1}, {x2,y2}, {x3,y3}}

		                -- find second derivatives
		                local d2_func_x = function(t)
		                	return bezierSecondDerivative(t, points)[1]
		                end

		                local d2_func_y = function(t)
		                	return bezierSecondDerivative(t, points)[2]
		                end

		                -- find if second derivates have a root (it's a line)
		                local bissection_extreme_t = {0, 1}
		                -- check critical points in x
		                if (d2_func_x(0) < 0 and d2_func_x(1) > 0) or (d2_func_x(0) > 0 and d2_func_x(1) < 0) then
		                	local crit_x = bissection(0, 1, 0, d2_func_x)
		                	table.insert(bissection_extreme_t, crit_x)
		                end

		                -- check critical points in y
		                if (d2_func_y(0) < 0 and d2_func_y(1) > 0) or (d2_func_y(0) > 0 and d2_func_y(1) < 0) then
		                	local crit_y = bissection(0, 1, 0, d2_func_y)
		                	table.insert(bissection_extreme_t, crit_y)
		                end

		                -- sort bissection extreme points 
		                table.sort(bissection_extreme_t)

		                -- bissect intervals
		                local d_func_x = function(t)
		                	return bezierDerivative(t, points)[1]
		                end

		                local d_func_y = function(t)
		                	return bezierDerivative(t, points)[2]
		                end

		                local boundingBox_t = {0, 1} -- critical points in t for bounding boxes

		                for i=2,#bissection_extreme_t do
			                local low = bissection_extreme_t[i-1]
			                local high = bissection_extreme_t[i]
			                -- check critical points in x
			                if (d_func_x(low) < 0 and d_func_x(high) > 0) or (d_func_x(low) > 0 and d_func_x(high) < 0) then
			                	local crit_x = bissection(low, high, 0, d_func_x)
			                	table.insert(boundingBox_t, crit_x)
			                end

			                -- check critical points in y
			                if (d_func_y(low) < 0 and d_func_y(high) > 0) or (d_func_y(low) > 0 and d_func_y(high) < 0) then
			                	local crit_y = bissection(low, high, 0, d_func_y)
			                	table.insert(boundingBox_t, crit_y)
			                end
		                end

		                -- sort critival points 
		                table.sort(boundingBox_t)


		                for i=2,#boundingBox_t do -- create quadratic segments
		                	local newPoints = reparametrization(boundingBox_t[i-1], boundingBox_t[i], points)

		                	local initialPoint = newPoints[1]
		                	local endPoint = newPoints[#newPoints]

							local boundingBox = createBoundingBox(initialPoint,endPoint)
			                
			                local delta = 1
			                if initialPoint[2] > endPoint[2] then
			                	delta = -1
			                end

    		                local func_x = function(t)
			                	return bezier(t, newPoints)[1]
			                end

			                local func_y = function(t)
			                	return bezier(t, newPoints)[2]
			                end
			                
			                local cubicSegment = {}

			                cubicSegment["boundingBox"] = boundingBox
			                cubicSegment["func_x"] = func_x
			                cubicSegment["func_y"] = func_y
			                cubicSegment["delta"] = delta
			                cubicSegments[#cubicSegments + 1] = cubicSegment		                	
		                end
		            end,
		            rational_quadratic_segment = function(self, x0, y0, x1, y1, w1,
		                x2, y2)
		                print("", "rational_quadratic_segment", x0, y0, x1, y1, w1,
		                    x2, y2)

		                local points = {{x0,y0,1},{x1,y1,w1},{x2,y2,1}}

		                --local x_coords = {x0,x1,x2}
		                --local y_coords = {y0,y1,y2}
		                --local w_coords = {1,w1,1}

		                local func_w = function(t)
		                	--return bezierNumeric(t, w_coords)
		                	return bezier(t,points)[3]
		                end
		                local func_x = function(t)
		                	--return bezierNumeric(t, x_coords)
		                	return bezier(t,points)[1]
		                end
		                local func_y = function(t)
		                	--return bezierNumeric(t, y_coords)
		                	return bezier(t,points)[2]
		                end

		                local d_func_w = function(t)
		                	--return bezierDerivativeNumeric(t, w_coords)
		                	return bezierDerivative(t,points)[3]
		                end
		                local d_func_x = function(t)
		                	--return bezierDerivativeNumeric(t, x_coords)
		                	return bezierDerivative(t,points)[1]
		                end
		                local d_func_y = function(t)
		                	--return bezierDerivativeNumeric(t, y_coords)
		                	return bezierDerivative(t,points)[2]
		                end

		                local d_func_x_w = function(t) -- numerator of derivative of x(t)/w(t)
		                	return d_func_x(t)*func_w(t) - func_x(t)*d_func_w(t)
		                end
		                local d_func_y_w = function(t) -- numerator of derivative of x(t)/w(t)
		                	return d_func_y(t)*func_w(t) - func_y(t)*d_func_w(t)
		                end

		               
		                local boundingBox_t = {0, 1}
		                -- check critical points in x

		                if (d_func_x_w(0) < 0 and d_func_x_w(1) > 0) or (d_func_x_w(0) > 0 and d_func_x_w(1) < 0) then
		                	local crit_x = bissection(0, 1, 0, d_func_x_w)
		                	table.insert(boundingBox_t, crit_x)
		                end

		                -- check critical points in y

		                if (d_func_y_w(0) < 0 and d_func_y_w(1) > 0) or (d_func_y_w(0) > 0 and d_func_y_w(1) < 0) then
		                	local crit_y = bissection(0, 1, 0, d_func_y_w)
		                	table.insert(boundingBox_t, crit_y)
		                end

		                -- sort critival points 
		                table.sort(boundingBox_t)


		                for i=2,#boundingBox_t do -- create rational segments
		                	local newPoints = reparametrization(boundingBox_t[i-1], boundingBox_t[i], points)
		                	local w2 = newPoints[3][3]
		                	local w0 = newPoints[1][3]
		                	print("w0, w2", w0, w2)

		                	local lambda = math.sqrt(w2/w0)

		                	for i=1,#newPoints do
		                		for j=1,#newPoints[1] do
		                			newPoints[i][j] = newPoints[i][j] * math.pow(lambda,3-i)/w2
		                		end
		                	end

		                	for k,v in pairs(newPoints) do
		                		print("v", v[3])
		                	end

		                	--local wCoord = newPoints[2][3]
		                	--print("wCoord", wCoord)
		                	local initialPoint = newPoints[1]
		                	local endPoint = newPoints[#newPoints]

							local boundingBox = createBoundingBox(initialPoint,endPoint)
			                
			                local delta = 1
			                if initialPoint[2] > endPoint[2] then
			                	delta = -1
			                end

			                local func_w = function(t)
			                	return bezier(t, newPoints)[3]
			                end

    		                local func_x = function(t)
			                	return bezier(t, newPoints)[1]/func_w(t)
			                end

			                local func_y = function(t)
			                	return bezier(t, newPoints)[2]/func_w(t)
			                end
			                
			                local rationalSegment = {}

			                rationalSegment["boundingBox"] = boundingBox
			                rationalSegment["func_x"] = func_x
			                rationalSegment["func_y"] = func_y
			                rationalSegment["delta"] = delta
			                rationalSegments[#rationalSegments + 1] = rationalSegment		                	
		                end
		            end,
		        }))
		        myAccelerated[shape_index]["linearSegments"] = linearSegments
		        myAccelerated[shape_index]["quadraticSegments"] = quadraticSegments
		        myAccelerated[shape_index]["cubicSegments"] = cubicSegments
		        myAccelerated[shape_index]["rationalSegments"] = rationalSegments
		        myAccelerated[shape_index]["shapeBoundingBox"] = {}

            else
                print("not a triangle"); print("not at all")
            end

            shape_index = shape_index + 1
        end,
		begin_transform = function(self, depth, xf)
            print("begin transform", depth, xf)
            local cur_xf = xf:transformed(transformationStack[depth+1])
            table.insert(transformationStack,cur_xf)
        end,
        end_transform = function(self, depth, xf)
            print("end transform", depth, xf)
	        table.remove(transformationStack)
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
		--stderr("\r%5g%%", floor(1000*i/height)/10)
        local y = vymin+i-1.+.5
        for j = 1, width do
            local x = vxmin+j-1+.5
            img:set_pixel(j, i, sample(accelerated, x, y))
        end
        stderr("\r%5g%%\t\t%s", floor(1000*i/height)/10,y)
    end
	stderr("\n")
	stderr("rendering in %.3fs\n", time:elapsed())
	time:reset()
	    -- Store output image
	    image.png.store8(file, img)
	stderr("saved in %.3fs\n", time:elapsed())
end

return _M
