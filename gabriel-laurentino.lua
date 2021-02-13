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

function bezierMatrix(points)
	if #points == 3 then
		local controlPointsBernsteinBasis = projectivity(points[1][1], points[2][1], points[3][1], 
											points[1][2], points[2][2], points[3][2],
											points[1][3], points[2][3], points[3][3])

		local powerBasisToBernsteinBasis = projectivity(1, -2, 1,
														0, 2, -2,
														0, 0, 1)

		return controlPointsBernsteinBasis * powerBasisToBernsteinBasis
	end
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

function bezierDerivativeMatrix(points)
	local newPoints = {}
	local N = #points - 1
	for i = 1,N do
		newPoints[i] = {}
		for l = 1,#points[1] do -- for each coordinate
			newPoints[i][l] = N*(points[i+1][l] - points[i][l])
		end
	end
	return bezierMatrix(newPoints)
end

function getResultant(points)
    local bezMatrix = bezierMatrix(points)

    local fx = {bezMatrix[1],bezMatrix[2],bezMatrix[3]}
    local gy = {bezMatrix[4],bezMatrix[5],bezMatrix[6]}

    local resultantDet = function(x, y)
    	local firstDet = projectivity(fx[1] - x, gy[2], gy[1] - y,
    									fx[2], gy[3], gy[2],
    									fx[3], 0, gy[3]):det()


    	local secondDet = projectivity(fx[2], fx[1] - x, gy[1] - y,
    									fx[3], fx[2], gy[2],
    									0, fx[3], gy[3]):det()

    	local det = (fx[1] - x)*firstDet + (gy[1] - y)*secondDet

    	return det
    end

    return resultantDet
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
	local err = 0.01

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

function evalLine(point, line)
	return line[1]*point[1] + line[2]*point[2] + line[3]
end

function createImplicitLine(initialPoint, endPoint)
	-- create implicit line ax + by + c = 0
    local line = {}

    line[1] = (endPoint[2] - initialPoint[2])
    line[2] = (initialPoint[1] - endPoint[1])
    line[3] = (-line[1]*initialPoint[1] -line[2]*initialPoint[2])

    return line
end

function createImplicitPositiveLine(initialPoint, endPoint)
	local a = endPoint[2] - initialPoint[2]
	if a < 0 then return createImplicitLine(endPoint, initialPoint) end
	return createImplicitLine(initialPoint, endPoint)
end

function createLinearSegment(initialPoint, endPoint)
	local linearSegment = {}

    local boundingBox = createBoundingBox(initialPoint,endPoint)

    -- create implicit line ax + by + c = 0
    local line = createImplicitLine(initialPoint, endPoint)

    local delta = 1

    if initialPoint[2] > endPoint[2] then
    	delta = -1
    end

    linearSegment["delta"] = delta
    linearSegment["boundingBox"] = boundingBox
    linearSegment["implicit"] = line

    return linearSegment
end

function createBoundingBox(initialPoint, endPoint)
	local boundingBox = {}

	boundingBox["Xmin"] = math.min(initialPoint[1], endPoint[1])
	boundingBox["Xmax"] = math.max(initialPoint[1], endPoint[1])
	boundingBox["Ymin"] = math.min(initialPoint[2], endPoint[2])
	boundingBox["Ymax"] = math.max(initialPoint[2], endPoint[2])
	
    return boundingBox
end

function updateBoundingBox(boundingBox, shapeBoundingBox)
	local newBoundingBox = {}

	if shapeBoundingBox["Xmax"] == nil then
		newBoundingBox["Xmin"] = boundingBox["Xmin"]
		newBoundingBox["Xmax"] = boundingBox["Xmax"]
		newBoundingBox["Ymin"] = boundingBox["Ymin"]
		newBoundingBox["Ymax"] = boundingBox["Ymax"]
	else
		newBoundingBox["Xmin"] = math.min(shapeBoundingBox["Xmin"], boundingBox["Xmin"])
		newBoundingBox["Xmax"] = math.max(shapeBoundingBox["Xmax"], boundingBox["Xmax"])
		newBoundingBox["Ymin"] = math.min(shapeBoundingBox["Ymin"], boundingBox["Ymin"])
		newBoundingBox["Ymax"] = math.max(shapeBoundingBox["Ymax"], boundingBox["Ymax"])
	end

	return newBoundingBox
end

function testInsideShapeBoundingBox(shapeBoundingBox, x, y)
	return (x < shapeBoundingBox["Xmax"]
		and x > shapeBoundingBox["Xmin"]
		and y < shapeBoundingBox["Ymax"]
		and y > shapeBoundingBox["Ymin"])
end

function printBoundingBox(boundingBox)
	print(boundingBox["Xmin"], boundingBox["Xmax"],boundingBox["Ymin"], boundingBox["Ymax"])
end

function innerProduct(v1, v2)
    result = 0
    for i=1,#v1 do
        result = result + v1[i]*v2[i]
    end
    return result
end

function countIntersections(segments, x, y)
	local intersections = 0
	local pixel = {x, y, 1}
	for key, segment in pairs(segments) do
		local boundingBox = segment["boundingBox"]
		local implicit = segment["implicit"]
		local delta = segment["delta"] -- tells me if I have to sum or subtract 1 from intersections

	    if  y > boundingBox["Ymin"] and y <= boundingBox["Ymax"] and x <= boundingBox["Xmax"] then
	    	if (x < boundingBox["Xmin"]) then
	    		intersections = intersections + delta
	    	else
	    		local value = evalLine(pixel, implicit)
                if (implicit[1] > 0 and value < 0) then
                    intersections = intersections + 1
                elseif (implicit[1] < 0 and value > 0) then
                    intersections = intersections - 1
	    		end
	    	end
	    end
	end
	return intersections
end

function quadraticImplicitForm(points, x, y)
	-- Horner Form
	-- Get determinant of Cayley Bezout
	-- Translate P0 to origin
	local intersections = 0

	local x1 = points[2][1] - points[1][1]
	local y1 = points[2][2] - points[1][2]
	local x2 = points[3][1] - points[1][1]
	local y2 = points[3][2] - points[1][2]
	local w = points[2][3]

	local xp = (x - points[1][1])*w
	local yp = (y - points[1][2])*w

	-- Cayley-Bézout entries
	local a11 = 2*xp*y1 - 2*x1*yp
	local a22 = 2*x2*y1 - 2*x1*y2
	local a12 = (2*x1 - x2)*yp - (2*y1 - y2)*xp

	-- Orientation given by partial derivative in x
	local xDerivative = 2*y2*(x1*y2 - x2*y1)

	-- resultant is the determinant
	local resultant = a11*a22 - a12*a12

	-- initialPoint[2] - endPoint[2]
	local orientation = 1
	if y2 < 0 then orientation = -1 end

	if (resultant > 0 and xDerivative > 0) or (resultant < 0 and xDerivative < 0) then
		return orientation
	end
	return 0

end

function countQuadratic(segments, x, y)
	local intersections = 0
	local pixel = {x, y, 1}
	
	for key, segment in pairs(segments) do
		local resultant = segment["resultant"]
		local delta = segment["delta"]
		local boundingBox = segment["boundingBox"]
		local p0p1 = segment["p0p1"]
		local p1p2 = segment["p1p2"]
		local p0p2 = segment["p0p2"]
		local positionP1 = segment["positionP1"]
		local controlPoints = segment["controlPoints"]

	    if  y > boundingBox["Ymin"] and y <= boundingBox["Ymax"] and x <= boundingBox["Xmax"] then
	    	if (x < boundingBox["Xmin"]) then
	    		intersections = intersections + delta
	    	else
	    		if positionP1 == -1 then
	    			if evalLine(pixel, p0p1) < 0 or evalLine(pixel, p1p2) < 0 then
	    				intersections = intersections + delta
	    			elseif evalLine(pixel, p0p2) < 0 then
	    				intersections = intersections + resultant(x,y)
	    			end
	    		elseif positionP1 == 1 then
	    			if evalLine(pixel, p0p2) < 0 then
	    				intersections = intersections + delta
	    			elseif evalLine(pixel, p0p1) < 0 or evalLine(pixel, p1p2) < 0 then
	    				intersections = intersections + resultant(x,y)
	    			else intersections = intersections
	    			end
	    		else
	    			stderr("no positionP1 found")
	    		end

	    		--intersections = intersections + resultant(x,y)
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

function getLinearGradientInfo(paint)
	local lg = paint:get_linear_gradient_data()
	local ramp = lg:get_color_ramp()
	local opacity = paint:get_opacity()
    print("", "p1", lg:get_x1(), lg:get_y1())
    print("", "p2", lg:get_x2(), lg:get_y2())
    print("", ramp:get_spread())
    for i, stop in ipairs(ramp:get_color_stops()) do
        print("", stop:get_offset(), "->", table.unpack(stop:get_color()))
    end
	local sampledColors = uniformSampling(ramp, opacity)
	return sampledColors
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

function getRadialGradientInfo(paint)
	local info = {}

	local lg = paint:get_radial_gradient_data()
	local ramp = lg:get_color_ramp()
	local opacity = paint:get_opacity()
	local sampledColors = uniformSampling(ramp,opacity)

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

	info["sampledColors"] = sampledColors
	info["simplerXf"] = simplerXf
	info["newCx"] = newCx

	return info
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

        	local linearSegments = shapeAccelerated["linearSegments"]
        	local quadraticSegments = shapeAccelerated["quadraticSegments"]
        	local cubicSegments = shapeAccelerated["cubicSegments"]
        	local rationalSegments = shapeAccelerated["rationalSegments"]

         	local shapeBoundingBox = shapeAccelerated["shapeBoundingBox"]

         	if testInsideShapeBoundingBox(shapeBoundingBox, x, y) then
	        	local linearSegmentsIntersections = countIntersections(linearSegments, x, y)
	        	local quadraticSegmentsIntersections = countQuadratic(quadraticSegments, x, y)
	        	local rationalSegmentsIntersections = countQuadratic(rationalSegments, x, y)

	        	intersections = linearSegmentsIntersections
	        					+ quadraticSegmentsIntersections
	        					+ rationalSegmentsIntersections
	        					--+ countIntersectionsPath(quadraticSegments, x, y)
	        					+ countIntersectionsPath(cubicSegments, x, y)
	        					--+ countIntersectionsPath(rationalSegments, x, y)


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

    scene = scene:windowviewport(window, viewport)
    stderr("scene xf %s\n", scene:get_xf())

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
        	

            if paint:get_type() == paint_type.linear_gradient then
            	local sampledColors = getLinearGradientInfo(paint)
            	myAccelerated[shape_index]["sampledColors"] = sampledColors
            end

            if paint:get_type() == paint_type.radial_gradient then
            	local radialGradient = getRadialGradientInfo(paint)
            	myAccelerated[shape_index]["sampledColors"] = radialGradient["sampledColors"]
            	myAccelerated[shape_index]["simplerXf"] = radialGradient["simplerXf"]*paint:get_xf():inverse()*scene:get_xf():inverse()--*xf:inverse()
            	myAccelerated[shape_index]["newCx"] = radialGradient["newCx"]
            end

            myAccelerated[shape_index]["shapeType"] = shapeType
        	local pdata = shape:as_path_data()
        	--local xf = shape:get_xf():transformed(scene:get_xf())

        	--myAccelerated[shape_index]["dealAs"] = "boundingBox"

        	local beginContour = {}
        	local endOpenContour = {}
        	local linearSegments = {}
        	local quadraticSegments = {}
        	local cubicSegments = {}
        	local rationalSegments = {}

        	local shapeBoundingBox = {}

	        pdata:iterate(filter.make_input_path_f_xform(xf, {
	            begin_contour = function(self, x0, y0)
	                print("", "begin_contour", x0, y0)
	                beginContour = {x0,y0}
	            end,
	            end_open_contour = function(self, x0, y0)
	                print("", "end_open_contour", x0, y0)
	                endOpenContour = {x0,y0}

	                if beginContour ~= endOpenContour then
	                	local linearSegment = createLinearSegment(endOpenContour, beginContour)
		                linearSegments[#linearSegments + 1] = linearSegment
	                end
	            end,
	            end_closed_contour = function(self, x0, y0)
	                print("", "end_closed_contour", x0, y0)
	            end,
	            linear_segment = function(self, x0, y0, x1, y1)
	                print("", "linear_segment", x0, y0, x1, y1)

	                local initialPoint = {x0,y0}
	                local endPoint = {x1,y1}

	                local linearSegment = createLinearSegment(initialPoint, endPoint)

	                shapeBoundingBox = updateBoundingBox(linearSegment["boundingBox"], shapeBoundingBox)

	                linearSegments[#linearSegments + 1] = linearSegment
	            end,
	            quadratic_segment = function(self, x0, y0, x1, y1, x2, y2)
	                --print("", "quadratic_segment", x0, y0, x1, y1, x2, y2)

	                local points = {{x0,y0,1}, {x1,y1,1}, {x2,y2,1}}

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

	                	print("", "quadratic_segment", newPoints[1][1], newPoints[1][2],
	                		newPoints[2][1], newPoints[2][2], newPoints[3][1], newPoints[3][2])

	                	local resultant = function(s, t)
	                		return quadraticImplicitForm(newPoints, s, t)
	                	end

	                	local initialPoint = newPoints[1]
	                	local endPoint = newPoints[#newPoints]

						local boundingBox = createBoundingBox(initialPoint,endPoint)
						shapeBoundingBox = updateBoundingBox(boundingBox, shapeBoundingBox)
		                
		                local implicitP0P1 = createImplicitPositiveLine(newPoints[1], newPoints[2])
		                local implicitP1P2 = createImplicitPositiveLine(newPoints[2], newPoints[3])
		                local implicitP0P2 = createImplicitPositiveLine(newPoints[1], newPoints[3])
		                local positionP1 = 1

		                if evalLine(newPoints[2], implicitP0P2) < 0 then
		                	positionP1 = -1
		                end
		                
		                print("poisitionP1 = ", positionP1)
		                print("p0p2", implicitP0P2[1])
		                print("p0p1", implicitP0P1[1], implicitP0P1[2], implicitP0P1[3])
		                print("p1p2", implicitP1P2[1])
		                print("eval p0p1", evalLine({100,80},implicitP0P1))
		                print("eval p0p1", evalLine({80,110},implicitP0P1))
		                print("eval p0p1", evalLine(newPoints[2],implicitP0P1))

		                local delta = 1
		                if initialPoint[2] > endPoint[2] then
		                	delta = -1
		                end

		                local quadraticSegment = {}

		                quadraticSegment["boundingBox"] = boundingBox
		                quadraticSegment["controlPoints"] = newPoints
		                quadraticSegment["resultant"] = resultant
		                quadraticSegment["p0p1"] = implicitP0P1
		                quadraticSegment["p1p2"] = implicitP1P2
		                quadraticSegment["p0p2"] = implicitP0P2
		                quadraticSegment["positionP1"] = positionP1
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
	                --print("", "rational_quadratic_segment", x0, y0, x1, y1, w1, x2, y2)

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

	                	print("", "rational_segments", newPoints[1][1], newPoints[1][2],
	                		newPoints[2][1], newPoints[2][2], newPoints[2][3], newPoints[3][1], newPoints[3][2])

	                	local resultant = function(s, t)
	                		return quadraticImplicitForm(newPoints, s, t)
	                	end

	                	local initialPoint = newPoints[1]
	                	local endPoint = newPoints[#newPoints]

						local boundingBox = createBoundingBox(initialPoint,endPoint)
						shapeBoundingBox = updateBoundingBox(boundingBox, shapeBoundingBox)
		                
		                local implicitP0P1 = createImplicitPositiveLine(newPoints[1], newPoints[2])
		                local implicitP1P2 = createImplicitPositiveLine(newPoints[2], newPoints[3])
		                local implicitP0P2 = createImplicitPositiveLine(newPoints[1], newPoints[3])
		                local positionP1 = 1

		                if evalLine(newPoints[2], implicitP0P2) < 0 then
		                	positionP1 = -1
		                end
		                
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
						rationalSegment["controlPoints"] = points
		                rationalSegment["resultant"] = resultant
		                rationalSegment["p0p1"] = implicitP0P1
		                rationalSegment["p1p2"] = implicitP1P2
		                rationalSegment["p0p2"] = implicitP0P2
		                rationalSegment["positionP1"] = positionP1
		                --rationalSegment["func_x"] = func_x
		                --rationalSegment["func_y"] = func_y
		                rationalSegment["delta"] = delta
		                rationalSegments[#rationalSegments + 1] = rationalSegment		                	
	                end
	            end,
	        }))
	        myAccelerated[shape_index]["linearSegments"] = linearSegments
	        myAccelerated[shape_index]["quadraticSegments"] = quadraticSegments
	        myAccelerated[shape_index]["cubicSegments"] = cubicSegments
	        myAccelerated[shape_index]["rationalSegments"] = rationalSegments
	        myAccelerated[shape_index]["shapeBoundingBox"] = shapeBoundingBox

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
