local facade = require"facade"
local image = require"image"
local chronos = require"chronos"
local filter = require"filter"
local blue = require"blue"
local svg = require"svg"

local unpack = table.unpack
local floor = math.floor

local _M = facade.driver()
setmetatable(_ENV, { __index = _M } )

local background = _M.solid_color(_M.color.white)

local function stderr(...)
    io.stderr:write(string.format(...))
end

---------------------------------------
---------------------------------------
-- CELL CLASS
---------------------------------------
---------------------------------------

Cell = {}
Cell.__index = Cell

function Cell:new(segments, k, limits, parent, children, index, numShapeSegments, depth)
    local obj = {}
    setmetatable(obj, Cell)
    obj.segments = segments
    obj.k = k
    obj.limits = limits
    obj.parent = parent
    obj.children = children
    obj.index = index
    obj.depth = depth or parent.depth + 1
    obj.numShapeSegments = numShapeSegments
    obj.usefulShapes = {}
    obj.shortcutIn = {}
    obj.shortcutOut = {}
    return obj
end

function Cell:set(segments)
    self.segments = segments
end

function Cell:get()
    return self.segments
end

function Cell:size()
	return math.min((self.limits[3] - self.limits[1]),(self.limits[4] - self.limits[2]))
end

function Cell:free()
	self.k = nil
	self.numShapeSegments = nil
	self.usefulShapes = nil
	self.shortcutIn = nil
	self.shortcutOut = nil
end

function Cell:isPointInside(point)
	--print(table.unpack(self.limits))
	if point[1] >= self.limits[1] and point[1] < self.limits[3] then
		if point[2] >= self.limits[2] and point[2] < self.limits[4] then
			return true
		end
	end
	return false
end

function Cell:isSegmentInside(segment)
	local seg = segment.segment
	local initialPoint = seg.initialPoint
	local endPoint = seg.endPoint

	local isP0Inside = self:isPointInside(initialPoint)
	local isPfInside = self:isPointInside(endPoint)

	if isP0Inside and isPfInside then
		return true
	end

	local limits = self.limits

	local p1 = {limits[1], limits[2]}
	local p2 = {limits[3], limits[2]}
	local p3 = {limits[3], limits[4]}
	local p4 = {limits[1], limits[4]}

	local crossp2p3 = segment:testCrossVerticalLine(p2, p3)

	if crossp2p3 then
		if endPoint[1] > initialPoint[1] and endPoint[2] < limits[4] then
			--print("added shortcut!! OUT")
			self:addShortcutOut(segment)
		elseif endPoint[1] < initialPoint[1] and initialPoint[2] < limits[4] then
			--print("added shortcut!! IN")
			self:addShortcutIn(segment)
		end
		return true
	end

	local crossp1p2 = segment:testCrossHorizontalLine(p1, p2)
	local crossp3p4 = segment:testCrossHorizontalLine(p3, p4)
	local crossp1p4 = segment:testCrossVerticalLine(p1, p4)

	if crossp1p2 or crossp3p4 or crossp1p4 then return true end
	if isP0Inside or isPfInside then return true end

	--print(table.unpack(initialPoint))
	--print(table.unpack(endPoint))
	--print(table.unpack(limits))
	--print("segment not inside cell")

	return false
end

function Cell:addShortcutIn(segment)
	table.insert(self.shortcutIn, segment)
	--self.shortcut[segment] = -1
end

function Cell:addShortcutOut(segment)
	table.insert(self.shortcutOut, segment)
	--self.shortcut[segment] = 1
end

function Cell:getShortcut(segment)
	return self.shortcut[segment] or 0
end

function Cell:subdivide()
	if #self.segments < 16 or #self.usefulShapes < 4 or self.depth > 4 then return end
	--print("SUBDIVIDE", self.depth, self.index)
	--if self.depth > 2 then return end

	local segments = self.segments
	local limits = self.limits
	local k = self.k
	local numShapes = #self.numShapeSegments

	-- middle point of cell
	local middleX, middleY = (self.limits[1]+self.limits[3])//2, (self.limits[2]+self.limits[4])//2

	-- new limits for new cells
	local limits00 = {self.limits[1], self.limits[2], middleX, middleY}
	local limits10 = {middleX, self.limits[2], self.limits[3], middleY}
	local limits11 = {middleX, middleY, self.limits[3], self.limits[4]}
	local limits01 = {self.limits[1], middleY, middleX, self.limits[4]}

	local zeroes = {}
	for i=1,numShapes do zeroes[i] = 0 end

	-- new cells
	local cell00 = Cell:new({}, {table.unpack(k)}, limits00, self, nil, 1, {table.unpack(zeroes)}) -- bottom left
	local cell10 = Cell:new({}, {table.unpack(k)}, limits10, self, nil, 2, {table.unpack(zeroes)}) -- bottom right
	local cell11 = Cell:new({}, {table.unpack(k)}, limits11, self, nil, 3, {table.unpack(zeroes)}) -- top right
	local cell01 = Cell:new({}, {table.unpack(k)}, limits01, self, nil, 4, {table.unpack(zeroes)}) -- top left
	local newCells = {cell00, cell10, cell11, cell01}

	self.children = newCells
	
	for keyC,newCell in pairs(newCells) do
		local corner = {newCell.limits[3], newCell.limits[2]}
		--local displacedCorner = {2*newCell.limits[3] - newCell.limits[1], newCell.limits[2]}
		for keyS,segment in pairs(segments) do
			if newCell:isSegmentInside(segment) then
				table.insert(newCell.segments, segment)
				newCell.numShapeSegments[segment.shapeIndex] = newCell.numShapeSegments[segment.shapeIndex] + 1
			end
			if keyC ~= 2 then
				newCell.k[segment.shapeIndex] = newCell.k[segment.shapeIndex] + segment:testIntersection(corner)
			end
		end
		if keyC ~= 2 then
			for keyI,shortcut in pairs(self.shortcutIn) do
				if shortcut.segment.initialPoint[2] <= corner[2] then
					newCell.k[shortcut.shapeIndex] = newCell.k[shortcut.shapeIndex] - 1
				end
			end
			for keyO,shortcut in pairs(self.shortcutOut) do
				if shortcut.segment.endPoint[2] <= corner[2] then
					newCell.k[shortcut.shapeIndex] = newCell.k[shortcut.shapeIndex] + 1
				end
			end
		end
		newCell:findUsefulShapes()
		newCell:subdivide()
	end
	self:free()
end

function Cell:findUsefulShapes()
	--print("finding useful shapes")
	--print(table.unpack(self.numShapeSegments))
	for key,numShapes in pairs(self.numShapeSegments) do
		if numShapes > 0 then
			--print("useful - ", key)
			table.insert(self.usefulShapes, key)
		elseif self.k[key] ~= 0 then
			table.insert(self.usefulShapes, key)
		end
	end
end

function Cell:calculateK()
	if self.index == 2 then return end
	local corner = {self.limits[3], self.limits[2]}
	for key, segment in pairs(self.parent.segments) do
		newCell.k[segment.shapeIndex] = newCell.k[segment.shapeIndex] + segment:testIntersection(corner)
	end
end

function Cell:findLeaf(pixel)
	--print("find leaf", table.unpack(self.limits))
	if self.children == nil or #self.children == 0 then
		--print("no children")
		return self
	end
	--print("children", table.unpack(self.children))
	for key, child in pairs(self.children) do
		--print(child)
		if child:isPointInside(pixel) then
			--print("yes")
			return child:findLeaf(pixel)
		end
	end
	--print("deu zebra")
	return nil
end

function Cell:printTree()
	print("PRINT TREE")
	if self.k ~= nil and self.parent ~= nil then
		print(table.unpack(self.k))
		--print(table.unpack(self.parent.k))
		print(table.unpack(self.limits))
		for key,segment in pairs(self.segments) do
			print("initial", table.unpack(segment.segment.initialPoint))
			print("end",table.unpack(segment.segment.endPoint))
		end
	end
	if self.shortcutIn ~= nil then print("shortcutIn"); print(#(self.shortcutIn)) end
	if self.shortcutOut ~= nil then print("shortcutOut"); print(#(self.shortcutOut)) end
	if self.children ~= nil then
		for key, child in pairs(self.children) do
			child:printTree()
		end
	end
end


--------------------------------------
-- Segment class
--------------------------------------

local Segment = {}
Segment.__index = Segment

function Segment:new(segment, segType, shapeIndex)
	local Segment = setmetatable({}, Segment)
	Segment.segment = segment
	Segment.type = segType
	Segment.shapeIndex = shapeIndex
	Segment.shortcut = {}
	return Segment
end

function Segment:testCrossHorizontalLine(p1, p2)
	local segType = self.type
	local seg = self.segment
	if segType == "linear" then
		if countLinear(seg, p1[1], p1[2]) ~= countLinear(seg, p2[1], p2[2]) then return true end
	elseif segType == "quadratic" then
		if countQuadratic(seg, p1[1], p1[2]) ~= countQuadratic(seg, p2[1], p2[2]) then return true end
	elseif segType == "cubic" then
		if countCubic(seg, p1[1], p1[2]) ~= countCubic(seg, p2[1], p2[2]) then return true end
	end
end

function Segment:testCrossVerticalLine(p1, p2)
	local segType = self.type
	local seg = self.segment
	if segType == "linear" then
		if countLinearVertical(seg, p1[1], p1[2]) ~= countLinearVertical(seg, p2[1], p2[2]) then return true end
	elseif segType == "quadratic" then
		if countQuadraticVertical(seg, p1[1], p1[2]) ~= countQuadraticVertical(seg, p2[1], p2[2]) then return true end
	elseif segType == "cubic" then
		if countCubicVertical(seg, p1[1], p1[2]) ~= countCubicVertical(seg, p2[1], p2[2]) then return true end
	end
end

function Segment:testIntersection(p1)
	local segType = self.type
	local seg = self.segment
	if segType == "linear" then
		return countLinear(seg, p1[1], p1[2])
	elseif segType == "quadratic" then
		return countQuadratic(seg, p1[1], p1[2])
	elseif segType == "cubic" then
		return countCubic(seg, p1[1], p1[2])
	end
end

function Segment:addShortcutIn(cell)
	self.shortcut[cell] = -1
end

function Segment:addShortcutOut(cell)
	self.shortcut[cell] = 1
end

function Segment:getShortcut(cell)
	return self.shortcut[cell] or 0
end

--------------------------------------
-- VARIABLES AND FUNCTIONS
-------------------------------------

myAccelerated = {}
quadTree = nil

function roundupPow2(num)
	if num == 0 then return 0 end
	local iter = num
	local result = 1
	while iter > 0 do
		iter = iter//2
		result = result * 2
	end
	return result
end

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

function getCriticalPointsInMonotonicIntervals(funcX, funcY, extremePoints)
	criticalPoints = {0,1}

    for i=2,#extremePoints do
        local low = extremePoints[i-1]
        local high = extremePoints[i]

        table.insert(criticalPoints, low) -- insert inflectionPoints
        -- check critical points in x
        if (funcX(low) < 0 and funcX(high) > 0) or (funcX(low) > 0 and funcX(high) < 0) then
        	local crit_x = bissection(low, high, 0, funcX)
        	table.insert(criticalPoints, crit_x)
        end
        -- check critical points in y
        if (funcY(low) < 0 and funcY(high) > 0) or (funcY(low) > 0 and funcY(high) < 0) then
        	local crit_y = bissection(low, high, 0, funcY)
        	table.insert(criticalPoints, crit_y)
        end

		table.insert(criticalPoints, high) -- insert inflectionPoints
    end
    table.sort(criticalPoints)
    return criticalPoints
end

function getMonotonicIntervals(d2_func_x, d2_func_y)
    -- find if second derivates have a root (it's a line)
    local extremePoints = {0, 1}
    -- check critical points in x
    if (d2_func_x(0) < 0 and d2_func_x(1) > 0) or (d2_func_x(0) > 0 and d2_func_x(1) < 0) then
    	local crit_x = bissection(0, 1, 0, d2_func_x)
    	table.insert(extremePoints, crit_x)
    end
    -- check critical points in y
    if (d2_func_y(0) < 0 and d2_func_y(1) > 0) or (d2_func_y(0) > 0 and d2_func_y(1) < 0) then
    	local crit_y = bissection(0, 1, 0, d2_func_y)
    	table.insert(extremePoints, crit_y)
    end
    -- sort bissection extreme points 
    table.sort(extremePoints)
    return removeRepeatedValuesInSortedList(extremePoints)
end

function getCriticalPoints(d_func_x, d_func_y, extremePoints)
    local criticalPoints = {0,1} -- critical points in t for bounding boxes

    for i=2,#extremePoints do
        local low = extremePoints[i-1]
        local high = extremePoints[i]

        table.insert(criticalPoints, low) -- insert inflectionPoints

        -- check critical points in x
        if (d_func_x(low) < 0 and d_func_x(high) > 0) or (d_func_x(low) > 0 and d_func_x(high) < 0) then
        	local crit_x = bissection(low, high, 0, d_func_x)
        	table.insert(criticalPoints, crit_x)
        end

        -- check critical points in y
        if (d_func_y(low) < 0 and d_func_y(high) > 0) or (d_func_y(low) > 0 and d_func_y(high) < 0) then
        	local crit_y = bissection(low, high, 0, d_func_y)
        	table.insert(criticalPoints, crit_y)
        end

		table.insert(criticalPoints, high) -- insert inflectionPoints
    end

    -- sort critical points 
    table.sort(criticalPoints)

    return removeRepeatedValuesInSortedList(criticalPoints)
end

function removeRepeatedValuesInSortedList(list)
	local newList = {}
	newList[1] = list[1]
	
	for i=2,#list do
		if list[i] ~= list[i-1] then table.insert(newList, list[i]) end
	end

	return newList
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

	--return mid
	return tonumber(string.format("%.2f", mid))
end

function evalLine(point, line)
	return line[1]*point[1] + line[2]*point[2] + line[3]
end

function intersectionBetweenLines(line1, line2)
	local a1, b1, c1 = line1[1], line1[2], line1[3]
	local a2, b2, c2 = line2[1], line2[2], line2[3]
	local D = 1/(a2*b1 - a1*b2)
	local y = -(a2*c1-a1*c2)*D
	local x = (b2*c1 - b1*c2)*D
	return {x, y, 1}
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

    if endPoint == nil then print("aqui foi nil") end

    linearSegment["initialPoint"] = initialPoint
    linearSegment["endPoint"] = endPoint
    linearSegment["delta"] = delta
    linearSegment["boundingBox"] = boundingBox
    linearSegment["implicit"] = line

    return linearSegment
end

function pointsAreColinear(points)
	local line = createImplicitPositiveLine(points[1], points[#points])
	for i=2,#points-1 do
		if math.abs(evalLine(points[i], line)) > 0.001 then
			return false
		end
	end
	return true
end

function pointsAreQuadratic(points)
	local cubicTerm = {}
	for i=1,2 do
		cubicTerm[i] = -points[1][i] + 3*points[2][i]
						-3*points[3][i] + points[4][i]
	end
	if arePointsEqual(cubicTerm, {0,0}) then return true end
	return false
end

function arePointsEqual(p1, p2)
	if #p1 ~= #p2 then return false end
	for i=1,#p1 do
		if math.abs(p1[i] - p2[i]) > 0.001 then return false end
	end
	return true
end

function getFirstTangent(points)
	if not arePointsEqual(points[1], points[2]) then
		return createImplicitPositiveLine(points[1], points[2])
	elseif not arePointsEqual(points[1], points[3]) then
		return createImplicitPositiveLine(points[1], points[3])
	elseif not arePointsEqual(points[1], points[4]) then
		return createImplicitPositiveLine(points[1], points[4])
	else
		print("degeneration")
	end
end

function getLastTangent(points)
	if not arePointsEqual(points[4], points[3]) then
		return createImplicitPositiveLine(points[4], points[3])
	elseif not arePointsEqual(points[4], points[2]) then
		return createImplicitPositiveLine(points[4], points[2])
	elseif not arePointsEqual(points[1], points[4]) then
		return createImplicitPositiveLine(points[1], points[4])
	else
		print("degeneration")
	end
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

function testIndideBoundingBox(shapeBoundingBox, x, y)
	return (x < shapeBoundingBox["Xmax"]
		and x > shapeBoundingBox["Xmin"]
		and y < shapeBoundingBox["Ymax"]
		and y > shapeBoundingBox["Ymin"])
end

function paintBoundingBoxes(segments, x, y)
	for key,segment in pairs(segments) do
		if testIndideBoundingBox(segment["boundingBox"], x, y) then
			return 1
		end
	end
	return 0
end

function printBoundingBox(boundingBox)
	print(boundingBox["Xmin"], boundingBox["Xmax"],boundingBox["Ymin"], boundingBox["Ymax"])
end

function printPairs(list)
	for k,v in pairs(list) do print(v) end
end

function innerProduct(v1, v2)
    result = 0
    for i=1,#v1 do
        result = result + v1[i]*v2[i]
    end
    return result
end

function countLinear(segment, x, y, vertical)
	local intersections = 0
	local pixel = {x, y, 1}
	local boundingBox = segment["boundingBox"]
	local implicit = segment["implicit"]
	local delta = segment["delta"] -- tells me if I have to sum or subtract 1 from intersections

    if  y >= boundingBox["Ymin"] and y < boundingBox["Ymax"] and x < boundingBox["Xmax"] then
    	if (x < boundingBox["Xmin"]) then
    		intersections = intersections + delta
    	else
    		local value = evalLine(pixel, implicit)
            if (implicit[1] > 0 and value <= 0) then
                intersections = intersections + 1
            elseif (implicit[1] < 0 and value >= 0) then
                intersections = intersections - 1
    		end
    	end
    end
    return intersections
end

function countLinearVertical(segment, x, y)
	local intersections = 0
	local pixel = {x, y, 1}
	local boundingBox = segment["boundingBox"]
	local implicit = segment["implicit"]
	local delta = segment["delta"] -- tells me if I have to sum or subtract 1 from intersections

    if  x >= boundingBox["Xmin"] and x < boundingBox["Xmax"] and y < boundingBox["Ymax"] then
    	if (y < boundingBox["Ymin"]) then
    		intersections = intersections + delta
    	else
    		local value = evalLine(pixel, implicit)
            if (implicit[2] > 0 and value < 0) then
                intersections = intersections + 1
            elseif (implicit[2] < 0 and value > 0) then
                intersections = intersections - 1
    		end
    	end
    end
    return intersections
end

function cubicImplicitForm(points, x, y)
	local x1 = points[2][1] - points[1][1]
	local y1 = points[2][2] - points[1][2]
	local x2 = points[3][1] - points[1][1]
	local y2 = points[3][2] - points[1][2]
	local x3 = points[4][1] - points[1][1]
	local y3 = points[4][2] - points[1][2]

	local xp = x - points[1][1]
	local yp = y - points[1][2]

	local signTest = -(y1 - y2 - y3)*(-x3*x3*(4*y1*y1 - 2*y1*y2 + y2*y2) + 
					x1*x1*(9*y2*y2 - 6*y2*y3 - 4*y3*y3) + 
					x2*x2*(9*y1*y1 - 12*y1*y3 - y3*y3) + 
					2*x1*x3*(-y2*(6*y2 + y3) + y1*(3*y2 + 4*y3)) - 
					2*x2*(x3*(3*y1*y1 - y2*y3 + y1*(-6*y2 + y3)) + 
				    x1*(y1*(9*y2 - 3*y3) - y3*(6*y2 + y3))))

	local resultant = -(-9*x2*y1 + 3*x3*y1 + 9*x1*y2 - 3*x1*y3)*((-3*x1*yp + 3*xp*y1)*(-9*x2*y1 + 3*x3*y1 + 9*x1*y2 - 3*x1*y3)
					- ((6*x1 - 3*x2)*yp + xp*(-6*y1 + 3*y2))*((-3*x1 + 3*x2 - x3)*yp
					+ xp*(3*y1 - 3*y2 + y3))) + (9*x2*y1 - 6*x3*y1 - 9*x1*y2 + 3*x3*y2 + 6*x1*y3 - 3*x2*y3)*(-((6*x1 - 3*x2)*yp
					+ xp*(-6*y1 + 3*y2))*((6*x1 - 3*x2)*yp + xp*(-6*y1 + 3*y2)) + (-3*x1*yp + 3*xp*y1)*((-3*x1 + 3*x2 - x3)*yp
					+ 9*x2*y1 - 9*x1*y2 + xp*(3*y1 - 3*y2 + y3))) + ((-3*x1 + 3*x2 - x3)*yp
					+ xp*(3*y1 - 3*y2 + y3))*(((6*x1 - 3*x2)*yp + xp*(-6*y1 + 3*y2))*(-9*x2*y1 + 3*x3*y1 + 9*x1*y2 - 3*x1*y3)
					- ((-3*x1 + 3*x2 - x3)*yp + xp*(3*y1 - 3*y2 + y3))*((-3*x1 + 3*x2 - x3)*yp
					+ 9*x2*y1 - 9*x1*y2 + xp*(3*y1 - 3*y2 + y3)))

	local orientation = 1
	if y3 < 0 then orientation = -1 end

	if (resultant >= 0 and signTest < 0) or (resultant <= 0 and signTest > 0) then
		return orientation
	end
	return 0
end

function countCubic(segment, x, y)
	local intersections = 0
	local pixel = {x, y, 1}

	local resultant = segment["resultant"]
	local delta = segment["delta"]
	local boundingBox = segment["boundingBox"]
	local vertex = segment["vertex"]
	local positionVertex = segment["positionVertex"]
	local controlPoints = segment["controlPoints"]

	local p0 = controlPoints[1]
	local p1 = RP2ToR2(vertex)
	local p2 = controlPoints[4]

    if  y >= boundingBox["Ymin"] and y < boundingBox["Ymax"] and x < boundingBox["Xmax"] then
    	if (x < boundingBox["Xmin"]) then
    		intersections = intersections + delta
    	else
    		local triangleTest = triangleTest(p0,p1,p2, pixel)
    		if positionVertex[1] == -1 then -- left positionVertex
    			if triangleTest == 1 then intersections = intersections + delta
    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
    			end
    		elseif positionVertex[1] == 1 then -- right positionVertex
    			if triangleTest == -1 then intersections = intersections + delta
    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
    			end
	    	end
    	end
    end

	return intersections
end

function countCubicVertical(segment, x, y)
	local intersections = 0
	local pixel = {x, y, 1}

	local resultant = segment["resultant"]
	local delta = segment["delta"]
	local boundingBox = segment["boundingBox"]
	local vertex = segment["vertex"]
	local positionVertex = segment["positionVertex"]
	local controlPoints = segment["controlPoints"]

	local p0 = controlPoints[1]
	local p1 = RP2ToR2(vertex)
	local p2 = controlPoints[4]

    if  x >= boundingBox["Xmin"] and x < boundingBox["Xmax"] and y < boundingBox["Ymax"] then
    	if (y < boundingBox["Ymin"]) then
    		intersections = intersections + delta
    	else
    		local triangleTest = triangleTest(p0,p1,p2, pixel)
    		if positionVertex[1]*positionVertex[2] == -1 then
	    		if positionVertex[2] == -1 then -- down positionVertex
	    			if triangleTest == 1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + (1 - math.abs(resultant(x,y)))*delta
	    			end
	    		elseif positionVertex[2] == 1 then -- up positionVertex
	    			if triangleTest == -1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + (1 - math.abs(resultant(x,y)))*delta
	    			end
		    	end
		    elseif positionVertex[1]*positionVertex[2] == 1 then
	    		if positionVertex[2] == -1 then -- down positionVertex
	    			if triangleTest == 1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
	    			end
	    		elseif positionVertex[2] == 1 then -- up positionVertex
	    			if triangleTest == -1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
	    			end
		    	end
		    end
    	end
    end
	return intersections
end

function getQuadraticSegment(newPoints)
	local resultant = function(s, t)
		return quadraticImplicitForm(newPoints, s, t)
	end

	local initialPoint = newPoints[1]
	local endPoint = newPoints[#newPoints]

	local boundingBox = createBoundingBox(initialPoint,endPoint)

    local diagonalLine = createImplicitPositiveLine(newPoints[1], newPoints[3])
    local positionVertex = checkPosition(RP2ToR2(newPoints[2]), diagonalLine)
    local delta = getOrientation(initialPoint, endPoint)

    local quadraticSegment = {}
    quadraticSegment["boundingBox"] = boundingBox
    quadraticSegment["controlPoints"] = newPoints
    quadraticSegment["initialPoint"] = initialPoint
    quadraticSegment["endPoint"] = endPoint
    quadraticSegment["resultant"] = resultant
    quadraticSegment["positionVertex"] = positionVertex
    quadraticSegment["delta"] = delta
    return quadraticSegment
end

function quadraticImplicitForm3(points, x, y)
	-- Translate P0 to origin	
	local intersections = 0

	local w1 = points[2][3]
	local x1 = points[2][1] - points[1][1]*w1
	local y1 = points[2][2] - points[1][2]*w1
	local x2 = points[3][1] - points[1][1]
	local y2 = points[3][2] - points[1][2]

	local xp = x - points[1][1]
	local yp = y - points[1][2]

	-- Cayley-Bézout entries
	local a11 = 2*(xp*y1 - x1*yp)
	local a22 = 2*((x2*y1 - x1*y2) + (1 - w1)*(x2*yp - xp*y2))
	local a12 = (2*x1 - x2)*yp - (2*y1 - y2)*xp

	-- Orientation given by partial derivative in x
	local xDerivative = (x2*y1 - x1*y2)*(2*y2 + (2*y1 - y2)*(1-w1))

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

function quadraticImplicitForm(points, x, y)
	-- Translate P0 to origin	
	local intersections = 0

	local w1 = points[2][3]
	local x1 = points[2][1] - points[1][1]*w1
	local y1 = points[2][2] - points[1][2]*w1
	local x2 = points[3][1] - points[1][1]
	local y2 = points[3][2] - points[1][2]

	local xp = x - points[1][1]
	local yp = y - points[1][2]

	-- Orientation given by partial derivative in x
	local xDerivative = 2*y2*(x1*y2 - x2*y1)

	-- Horner Form
	local resultant = yp*(
							yp*(
								4*x1*x1 - 4*w1*x1*x2 + x2*x2
								)
							+ 4*x1*x2*y1 - 4*x1*x1*y2
						)
					+ xp*(
							-4*x2*y1*y1 + 4*x1*y1*y2
							+ yp*(
									-8*x1*y1 + 4*w1*x2*y1 + 4*w1*x1*y2 - 2*x2*y2
								)
							+ xp*(
									4*y1*y1 - 4*w1*y1*y2 + y2*y2
								)
						)

	-- initialPoint[2] - endPoint[2]
	local orientation = 1
	if y2 < 0 then orientation = -1 end

	if (resultant >= 0 and xDerivative < 0) or (resultant <= 0 and xDerivative > 0) then
		return orientation
	end
	return 0
end

function quadraticImplicitForm1(points, x, y)
	-- Get determinant of Cayley Bezout
	-- Translate P0 to origin
	local intersections = 0

	local w1 = points[2][3]
	local x1 = points[2][1] - points[1][1]*w1
	local y1 = points[2][2] - points[1][2]*w1
	local x2 = points[3][1] - points[1][1]
	local y2 = points[3][2] - points[1][2]

	local xp = x - points[1][1]
	local yp = y - points[1][2]

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

function countQuadraticVertical(segment, x, y)
	local intersections = 0
	local pixel = {x, y, 1}
	
	local resultant = segment["resultant"]
	local delta = segment["delta"]
	local boundingBox = segment["boundingBox"]
	local positionVertex = segment["positionVertex"]
	local controlPoints = segment["controlPoints"]

	local p0 = controlPoints[1]
	local p1 = RP2ToR2(controlPoints[2])
	local p2 = controlPoints[3]

    if  x >= boundingBox["Xmin"] and x < boundingBox["Xmax"] and y < boundingBox["Ymax"] then
    	if (y < boundingBox["Ymin"]) then
    		intersections = intersections + delta
    	else
    		local triangleTest = triangleTest(p0,p1,p2, pixel)
    		if positionVertex[1]*positionVertex[2] == -1 then
	    		if positionVertex[2] == -1 then -- down positionVertex
	    			if triangleTest == 1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + (1 - math.abs(resultant(x,y)))*delta
	    			end
	    		elseif positionVertex[2] == 1 then -- up positionVertex
	    			if triangleTest == -1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + (1 - math.abs(resultant(x,y)))*delta
	    			end
		    	end
		    elseif positionVertex[1]*positionVertex[2] == 1 then
	    		if positionVertex[2] == -1 then -- down positionVertex
	    			if triangleTest == 1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
	    			end
	    		elseif positionVertex[2] == 1 then -- up positionVertex
	    			if triangleTest == -1 then intersections = intersections + delta
	    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
	    			end
		    	end
		    end
    	end
    end

	return intersections
end

function countQuadratic(segment, x, y)
	local intersections = 0
	local pixel = {x, y, 1}
	
	local resultant = segment["resultant"]
	local delta = segment["delta"]
	local boundingBox = segment["boundingBox"]
	local positionVertex = segment["positionVertex"]
	local controlPoints = segment["controlPoints"]

	local p0 = controlPoints[1]
	local p1 = RP2ToR2(controlPoints[2])
	local p2 = controlPoints[3]

    if  y >= boundingBox["Ymin"] and y < boundingBox["Ymax"] and x < boundingBox["Xmax"] then
    	if (x < boundingBox["Xmin"]) then
    		intersections = intersections + delta
    	else
    		local triangleTest = triangleTest(p0,p1,p2, pixel)
    		if positionVertex[1] == -1 then -- left positionVertex
    			if triangleTest == 1 then intersections = intersections + delta
    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
    			end
    		elseif positionVertex[1] == 1 then -- right positionVertex
    			if triangleTest == -1 then intersections = intersections + delta
    			elseif triangleTest == 0 then intersections = intersections + resultant(x,y)
    			end
	    	end
    	end
    end

	return intersections
end

function triangleTest(p0,p1,p2,p)
	local p0p1p2 = triangleArea(p0,p1,p2)
	local p0pp2 = triangleArea(p0,p,p2)
	local p0p1p = triangleArea(p0,p1,p)
	local pp1p2 = triangleArea(p,p1,p2)

	--if p0p1p2 ~= pp1p2 + p0pp2 + p0p1p then print("somethings wrong") end

	if isSameSign(p0p1p2, p0pp2) then
		if isSameSign(p0p1p2, p0p1p) and isSameSign(p0p1p2, pp1p2) then
			return 0 -- inside triangle
		else return 1 end -- same side
	else return -1 end -- opposite side
end

function isSameSign(m,n)
	return (m >= 0 and n >= 0) or (m <= 0 and n <= 0)
end

function triangleArea(p0,p1,p2)
	return 0.5*((p1[1]*p2[2] - p2[1]*p1[2])
			- (p0[1]*p2[2] - p0[2]*p2[1])
			+ (p0[1]*p1[2] - p0[2]*p1[1]))
end

function checkPosition(point, line)
	local horizontal = -1 -- WEST
	local vertical = -1 -- SOUTH

	local value = evalLine(point, line)

	if (line[1] > 0 and value > 0) or (line[1] < 0 and value < 0) then
		horizontal = 1 -- EAST
	end

	if (line[2] > 0 and value > 0) or (line[2] < 0 and value < 0) then
		vertical = 1 -- NORTH
	end
	
	return {horizontal, vertical}
end

function isBelowLine(point, line)
	local value = evalLine(point, line)
	if line[2] > 0 then
		if value > 0 then return false else return true end
	elseif line[2] < 0 then
		if value > 0 then return true else return false end
	else
		return false
	end
end	

function isAboveLine(point, line)
	local value = evalLine(point, line)
	if line[2] < 0 then
		if value > 0 then return false else return true end
	elseif line[2] > 0 then
		if value > 0 then return true else return false end
	else
		return false
	end
end

function getOrientation(initialPoint, endPoint)
	if initialPoint[2] > endPoint[2] then return -1 end
	return 1
end

function RP2ToR2(point)
	return {point[1]/point[3], point[2]/point[3], 1}
end

function opacityAlphaBlending(color,opacity)
	local blendColor = {table.unpack(color)}
	if color[4] ~= nil then
		blendColor[4] = opacity*blendColor[4]
	else
		blendColor[4] = opacity
	end
	if blendColor[4] > 1 then print(blendColor[4]) end -- shouldnt happen
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
    --print("", "p1", lg:get_x1(), lg:get_y1())
    --print("", "p2", lg:get_x2(), lg:get_y2())
    --print("", ramp:get_spread())
    --for i, stop in ipairs(ramp:get_color_stops()) do
    --    print("", stop:get_offset(), "->", table.unpack(stop:get_color()))
    --end
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

function getTextureInfo(paint)
    local tex = paint:get_texture_data()
    local img = tex:get_image()
    local width, height = img:get_width(), img:get_height()
    return scaling(width, height)
end

function getTexture(paint, x, y)
    local tex = paint:get_texture_data()
    local spread, img = tex:get_spread(), tex:get_image()
    local width, height = img:get_width(), img:get_height()
    local opacity = paint:get_opacity()

    local xRamp = math.floor(width*getSpread(spread, x)) % width + 1
    local yRamp = math.floor(height*getSpread(spread, y)) % height + 1

    local c1, c2, c3, c4 = img:get_pixel(xRamp, yRamp)
    local color = {c1, c2, c3, c4}

	return opacityAlphaBlending(color,opacity)
end

function getSpread(spreadType, value)
	if spreadType == spread.clamp then
		return math.min(1, max(0,value))
	elseif spreadType == spread.wrap then
		return value - math.floor(value)
	elseif spreadType == spread.mirror then
		return 2*math.abs(0.5*value - math.floor(0.5*value + 0.5))
	elseif spreadType == spread.transparent then
		if value < 0 or value > 1 then return -1 end
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
    	--print(inverseDenominator)
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

function countIntersections(cell, x, y, shapeIndex)
	local segments = cell.segments
	local intersections = cell.k[shapeIndex]
	for key, segment in pairs(segments) do
		if segment.shapeIndex == shapeIndex then
			if segment.type == "linear" then
				intersections = intersections + countLinear(segment.segment, x, y)-- + cell:getShortcut(segment)-- + segment:getShortcut(cell)
			elseif segment.type == "cubic" then
				intersections = intersections + countCubic(segment.segment, x, y)-- + cell:getShortcut(segment)-- + segment:getShortcut(cell)
			elseif segment.type == "quadratic" then
				intersections = intersections + countQuadratic(segment.segment, x, y)-- + cell:getShortcut(segment)-- + segment:getShortcut(cell)
			end
		end
	end
	-- shortcuts
	for key,segment in pairs(cell.shortcutIn) do
		if segment.shapeIndex == shapeIndex then
			if y >= segment.segment.initialPoint[2]
			then
				intersections = intersections - 1
			end
		end
	end
	for key,segment in pairs(cell.shortcutOut) do
		if segment.shapeIndex == shapeIndex then
			if y >= segment.segment.endPoint[2]
			then
				intersections = intersections + 1
			end
		end
	end
	return intersections
end


-- ----------------
-- SAMPLE
-------------------

-- Set Number of Samples for Anti-Aliasing, must be power of 2
local blueSize = 1

function mixColors(colorsToMix)
	local R = 0
	local G = 0
	local B = 0
	local size = 1/#colorsToMix
	for i=1,#colorsToMix do
		R = R + colorsToMix[i][1]
		G = G + colorsToMix[i][2]
		B = B + colorsToMix[i][3]
	end
	R = R*size
	G = G*size
	B = B*size
	return R, G, B, 1
end


local function preSampleTeste(accelerated, x, y)
	local cell = quadTree:findLeaf({x,y})
	local numShapeSegments = cell.numShapeSegments
	local usefulShapes = cell.usefulShapes

	local colors = {}
	local red = {255,1,1,1}
	local green = {1,255,1,1}
	local blue = {1,1,255,1}
	local any = {120,40,80,1}

	colors = {red, green, blue, any}

	return colors[(cell.depth + cell.index)%4 + 1]
end


local function preSample(accelerated, x, y, cell)
    -- This function should return the color of the sample
    -- at coordinates (x,y).

    local colors = {}
    --table.insert(colors, background:get_solid_color())
    local scene = accelerated

    -- index of accelerated data (one for every pixel)
    --local shape_index = 1

	--if cell.index == 1 then return {255,1,1,1} end
	--if cell.index == 2 then return {1,1,255,1} end
	--if cell.index == 3 then return {255,255,1,1} end
	--if cell.index == 4 then return {1,255,255,1} end

	local usefulShapes = cell.usefulShapes

	if #usefulShapes > 0 then
		--print(table.unpack(usefulShapes))
		for key,shape_index in pairs(usefulShapes) do
	        local shapeAccelerated = myAccelerated[shape_index]
	        local shape = shapeAccelerated["shape"]
	        local paint = shapeAccelerated["paint"]
	        local rule = shapeAccelerated["rule"]
	        --rule = winding_rule.odd
	        local intersections = 0

	    	--local segments = shapeAccelerated["segments"]
	     	local shapeBoundingBox = shapeAccelerated["shapeBoundingBox"]

	     	if testIndideBoundingBox(shapeBoundingBox, x, y) then
	        	intersections = countIntersections(cell, x, y, shape_index)
	            local intersectionsBool = (intersections ~= 0)
	            if rule == winding_rule.odd then
	                intersectionsBool = (intersections % 2 == 1)
	            end

	            if (intersectionsBool) then -- non-zero
	            	--local paint_xf = paint:get_xf():inverse() --shapeAccelerated["xf"]
	            	if paint:get_type() == paint_type.solid_color then 
		            	local blendColor = shapeAccelerated["blendColor"]--opacityAlphaBlending(paint:get_solid_color(),opacity)
	                	table.insert(colors, blendColor)
	                elseif paint:get_type() == paint_type.linear_gradient then
				        local simplerXf = shapeAccelerated["simplerXf"]
				        local px, py = simplerXf:apply(x,y,1) -- transformed pixel coordinates
	                	--local px, py = paint_xf:transformed(scene:get_xf():inverse()):apply(x, y, 1)
						local t_ramp = getLinearGradient(paint, px, py)
						local sampledColors = shapeAccelerated["sampledColors"]
						local sampleIndex = math.max(math.floor(#sampledColors*t_ramp),1)
						local colorFound = sampledColors[sampleIndex]
						table.insert(colors, colorFound)
	                elseif paint:get_type() == paint_type.radial_gradient then
				        local simplerXf = shapeAccelerated["simplerXf"]
				        local px, py = simplerXf:apply(x,y,1) -- transformed pixel coordinates
				        local cx = shapeAccelerated["newCx"]
				        local t_ramp = getRadialGradient(paint,px,py,cx)
				        local sampledColors = shapeAccelerated["sampledColors"]
						local sampleIndex = math.max(math.floor(#sampledColors*t_ramp),1)
						local colorFound = sampledColors[sampleIndex]
						table.insert(colors, colorFound)
	                elseif paint:get_type() == paint_type.texture then
				        local simplerXf = shapeAccelerated["simplerXf"]
				        local px, py = simplerXf:apply(x,y,1) -- transformed pixel coordinates
	                	local colorFound = getTexture(paint, px, py)
	                	table.insert(colors, colorFound)
	                else
	                	print("unknown paint")
	                end
	            end
	     	end
		end
	end

    --shape_index = shape_index + 1
    --if math.abs(x - cell.limits[1]) < 0.8 then return {255,1,1,1} end
    --if math.abs(x - cell.limits[3]) < 0.8 then return {1,1,255,1} end
    --if math.abs(y - cell.limits[2]) < 0.8 then return {255,1,255,1} end
    --if math.abs(y - cell.limits[4]) < 0.8 then return {1,255,1,1} end

	--if x > 64 and x < 96 and y > 64 and y < 96 then print("SIZE OF COLORS", #colors) end

    if ( #colors > 0 ) then
    	local colorReturned = calculateColor(colors)
    	--print(table.unpack(colorReturned))
    	--if x > 64 and x < 96 and y > 64 and y < 96 then print("RETURN", table.unpack(colorReturned)) end
        return colorReturned--table.unpack(colorReturned)
    end
    return background:get_solid_color() --table.unpack(background:get_solid_color()) -- no color painted
end

local function sample(accelerated, x, y)
	local colorsToMix = {}
	local cell = quadTree:findLeaf({x,y})
	--local numShapeSegments = cell.numShapeSegments
	--print(table.unpack(numShapeSegments))
	for i=1,blueSize do
		local dx = blue[blueSize].x[i]
		local dy = blue[blueSize].x[i]
		table.insert(colorsToMix, preSample(accelerated, x + dx, y + dy, cell))
	end
	return mixColors(colorsToMix)
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
-- Acceleration structure
----------------------------------------


----------------------------------------
-- ACCELERATE
----------------------------------------

function _M.accelerate(scene, window, viewport, args)
    local parsed = parse(args)
    stderr("parsed arguments\n")
    for i,v in pairs(parsed) do
        stderr("  -%s:%s\n", tostring(i), tostring(v))
    end

    print("wv", table.unpack(viewport))
   	print(roundupPow2(viewport[3]), roundupPow2(viewport[4]))

    scene = scene:windowviewport(window, viewport)
    --stderr("scene xf %s\n", scene:get_xf())

    -- stack of transformations
    local transformationStack = {}
    transformationStack[1] = projectivity(1,0,0,0,1,0,0,0,1)

    -- index of accelerated data (one for every pixel)
    local shape_index = 1

    local segments = {}

--[[
    -- create a new scene data
    local new_sd = svg.scene_data()

    -- copy the scene data to new_sd
    scene:get_scene_data():iterate(new_sd)

    local new_scene = svg.scene(new_sd):transformed(scene:get_xf())
    local output = io.open('dump.svg', "w")
    -- save our svg scene
    svg.render(new_scene, window, viewport, output)
    output:close()
--]]

    scene:get_scene_data():iterate{
        painted_shape = function(self, winding_rule, shape, paint)
            myAccelerated[shape_index] = {}
            myAccelerated[shape_index]["shape"] = shape
            myAccelerated[shape_index]["rule"] = winding_rule
            myAccelerated[shape_index]["paint"] = paint

            --stderr("painted %s %s %s\n", winding_rule, shape:get_type(), paint:get_type())
            --stderr("  xf s %s\n", shape:get_xf())

            local shapeType = shape:get_type()

            local cur_xf = transformationStack[#transformationStack]
            local sceneCurXf = scene:get_xf()*cur_xf
            local shape_xf = sceneCurXf*shape:get_xf()
            local paint_xf = sceneCurXf*paint:get_xf()

            --print("transformation depth", #transformationStack)
        	if paint:get_type() == paint_type.solid_color then
            	local opacity = paint:get_opacity()
        		local blendColor = opacityAlphaBlending(paint:get_solid_color(),opacity)
        		myAccelerated[shape_index]["blendColor"] = blendColor
            elseif paint:get_type() == paint_type.linear_gradient then
            	local sampledColors = getLinearGradientInfo(paint)
            	local simplerXf = paint_xf:inverse()
            	myAccelerated[shape_index]["simplerXf"] = simplerXf
            	myAccelerated[shape_index]["sampledColors"] = sampledColors
            elseif paint:get_type() == paint_type.radial_gradient then
            	local radialGradient = getRadialGradientInfo(paint)
            	myAccelerated[shape_index]["sampledColors"] = radialGradient["sampledColors"]
            	myAccelerated[shape_index]["simplerXf"] = radialGradient["simplerXf"]*paint_xf:inverse()--*xf:inverse()
            	myAccelerated[shape_index]["newCx"] = radialGradient["newCx"]
            elseif paint:get_type() == paint_type.texture then
            	local textureXf = getTextureInfo(paint)
            	local simplerXf = paint_xf:inverse()
            	myAccelerated[shape_index]["simplerXf"] = simplerXf
            end

            myAccelerated[shape_index]["shapeType"] = shapeType

        	local pdata = shape:as_path_data()

        	local beginContour = {}
        	local endOpenContour = {}
        	--local segments = {}

        	local shapeBoundingBox = {}
        	local doubleAndInflectionParameters = {}

	        pdata:iterate(filter.make_input_path_f_xform(shape_xf, filter.make_input_path_f_find_cubic_parameters({
	            begin_contour = function(self, x0, y0)
	                --print("", "begin_contour", x0, y0)
	                beginContour = {x0,y0}
	            end,
				inflection_parameter = function(self, t)
					table.insert(doubleAndInflectionParameters, t)
				end,
	            double_point_parameter = function(self, t)
	            	table.insert(doubleAndInflectionParameters, t)
				end,
	            end_open_contour = function(self, x0, y0)
	                --print("", "end_open_contour", x0, y0)
	                endOpenContour = {x0,y0}

	                if beginContour ~= endOpenContour then
	                	local linearSegment = createLinearSegment(endOpenContour, beginContour)
		                --linearSegments[#linearSegments + 1] = linearSegment
		                segments[#segments + 1] = Segment:new(linearSegment, "linear", shape_index)
	                end
	            end,
	            end_closed_contour = function(self, x0, y0)
	                --print("", "end_closed_contour", x0, y0)
	            end,
	            linear_segment = function(self, x0, y0, x1, y1)
	                --print("original", "linear_segment", x0, y0, x1, y1)

	                local initialPoint = {x0,y0}
	                local endPoint = {x1,y1}

	                local linearSegment = createLinearSegment(initialPoint, endPoint)

	                shapeBoundingBox = updateBoundingBox(linearSegment["boundingBox"], shapeBoundingBox)

	                --linearSegments[#linearSegments + 1] = linearSegment
	                local segment = Segment:new(linearSegment, "linear", shape_index)
	                segments[#segments + 1] = segment
	            end,
	            quadratic_segment = function(self, x0, y0, x1, y1, x2, y2)
	                --print("original", "quadratic_segment", x0, y0, x1, y1, x2, y2)

	                local points = {{x0,y0,1}, {x1,y1,1}, {x2,y2,1}}

				    local d_func_x = function(t)
				    	return bezierDerivative(t, points)[1]
				    end
				    local d_func_y = function(t)
				    	return bezierDerivative(t, points)[2]
				    end

	                local criticalPoints = getCriticalPoints(d_func_x, d_func_y, {0,1})

	                for i=2,#criticalPoints do -- create quadratic segments
	                	local newPoints = reparametrization(criticalPoints[i-1], criticalPoints[i], points)

	                	if not pointsAreColinear(newPoints) then
                			--print("transformed", "quadratic_segment", newPoints[1][1], newPoints[1][2],
                					--newPoints[2][1], newPoints[2][2], newPoints[3][1], newPoints[3][2])
		                	local quadraticSegment = getQuadraticSegment(newPoints)
	                		shapeBoundingBox = updateBoundingBox(quadraticSegment["boundingBox"], shapeBoundingBox)
			                --quadraticSegments[#quadraticSegments + 1] = quadraticSegment	 
			                segments[#segments + 1] = Segment:new(quadraticSegment, "quadratic", shape_index)               	
		            	else
			                local linearSegment = createLinearSegment(newPoints[1], newPoints[3])
			                --print("transformed", "linear_segment", newPoints[1][1], newPoints[1][2], newPoints[2][1], newPoints[2][2])
			                shapeBoundingBox = updateBoundingBox(linearSegment["boundingBox"], shapeBoundingBox)
			                --linearSegments[#linearSegments + 1] = linearSegment
			                segments[#segments + 1] = Segment:new(linearSegment, "linear", shape_index)
   		                end
		            end
	            end,
	            cubic_segment = function(self, x0, y0, x1, y1, x2, y2, x3, y3)
	                --print("original", "cubic_segment", x0, y0, x1, y1, x2, y2, x3, y3)

	                local points = {{x0,y0,1}, {x1,y1,1}, {x2,y2,1}, {x3,y3,1}}

	                -- find second derivatives
	                local d2_func_x = function(t)
	                	return bezierSecondDerivative(t, points)[1]
	                end
	                local d2_func_y = function(t)
	                	return bezierSecondDerivative(t, points)[2]
	                end

	                local secondExtremePoints = getMonotonicIntervals(d2_func_x, d2_func_y)
	                ----print("secondExtremePoints", table.unpack(secondExtremePoints))

                    -- bissect intervals
				    local d_func_x = function(t)
				    	return bezierDerivative(t, points)[1]
				    end
				    local d_func_y = function(t)
				    	return bezierDerivative(t, points)[2]
				    end

	                local criticalPoints = getCriticalPoints(d_func_x, d_func_y, secondExtremePoints)

	                for key, value in pairs(doubleAndInflectionParameters) do
	                	table.insert(criticalPoints, value)
	                end

	                table.sort(criticalPoints)
	                criticalPoints = removeRepeatedValuesInSortedList(criticalPoints)

	                ----print("criticalPoints", table.unpack(criticalPoints))

	                for i=2,#criticalPoints do -- create quadratic segments
	                	local newPoints = reparametrization(criticalPoints[i-1], criticalPoints[i], points)

	                	if pointsAreColinear(newPoints) then
			                local linearSegment = createLinearSegment(newPoints[1], newPoints[4])
			                ----print("transformed", "linear_segment", newPoints[1][1], newPoints[1][2], newPoints[4][1], newPoints[4][2])
			                shapeBoundingBox = updateBoundingBox(linearSegment["boundingBox"], shapeBoundingBox)
			                --linearSegments[#linearSegments + 1] = linearSegment
			                segments[#segments + 1] = Segment:new(linearSegment, "linear", shape_index)
			            elseif pointsAreQuadratic(newPoints) then
			            	local Q = {-0.5*newPoints[1][1] + 1.5*newPoints[2][1], -0.5*newPoints[1][2] + 1.5*newPoints[2][2], 1} -- control point of degeneration
			            	local equivalentPoints = {newPoints[1], Q, newPoints[4]}
			            	--print("transformed", "quadratic_segment", equivalentPoints[1][1], equivalentPoints[1][2],
			            											--equivalentPoints[2][1], equivalentPoints[2][2],
			            											--equivalentPoints[3][1], equivalentPoints[3][2])
			            	local quadraticSegment = getQuadraticSegment(equivalentPoints)
	                		shapeBoundingBox = updateBoundingBox(quadraticSegment["boundingBox"], shapeBoundingBox)
			                --quadraticSegments[#quadraticSegments + 1] = quadraticSegment
			                segments[#segments + 1] = Segment:new(quadraticSegment, "quadratic", shape_index)
	                	elseif not (arePointsEqual(newPoints[1], newPoints[2]) and
	                				arePointsEqual(newPoints[2], newPoints[3]) and
	                				arePointsEqual(newPoints[3], newPoints[4])) then
		                	----print("transformed", "cubic_segment", newPoints[1][1], newPoints[1][2], newPoints[2][1], newPoints[2][2],
		                	--										newPoints[3][1], newPoints[3][2], newPoints[4][1], newPoints[4][2])

		                	local initialPoint = newPoints[1]
		                	local endPoint = newPoints[#newPoints]
		                	
		                	local resultant = function(s, t)
		                		return cubicImplicitForm(newPoints, s, t)
		                	end
								
							local boundingBox = createBoundingBox(initialPoint,endPoint)
							shapeBoundingBox = updateBoundingBox(boundingBox, shapeBoundingBox)

			                local firstTangent = getFirstTangent(newPoints)
			                local lastTangent = getLastTangent(newPoints)

				            local diagonalLine = createImplicitPositiveLine(newPoints[1], newPoints[4])
			                local vertex = intersectionBetweenLines(firstTangent, lastTangent)
			                local positionVertex = checkPosition(vertex, diagonalLine)

			                local delta = getOrientation(initialPoint,endPoint)
			                
			                local cubicSegment = {}

			                cubicSegment["boundingBox"] = boundingBox
			                cubicSegment["controlPoints"] = newPoints
			                cubicSegment["initialPoint"] = initialPoint
			                cubicSegment["endPoint"] = endPoint
			                cubicSegment["resultant"] = resultant
			                cubicSegment["vertex"] = vertex
			                cubicSegment["positionVertex"] = positionVertex
			                cubicSegment["delta"] = delta
			                --cubicSegments[#cubicSegments + 1] = cubicSegment
			                segments[#segments + 1] = Segment:new(cubicSegment, "cubic", shape_index)
		                else
		                	--print("degeneration found")
		                end        	
	                end
	                doubleAndInflectionParameters = {}
	            end,
	            rational_quadratic_segment = function(self, x0, y0, x1, y1, w1,
	                x2, y2)
	                ----print("original", "rational_quadratic_segment", x0, y0, x1, y1, w1, x2, y2)

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

	            	local criticalPoints = getCriticalPoints(d_func_x_w, d_func_y_w, {0,1})

	                for i=2,#criticalPoints do -- create rational segments
	                	local newPoints = reparametrization(criticalPoints[i-1], criticalPoints[i], points)

	                	if not pointsAreColinear(newPoints) then
	                		-- normalize control points
		                	local w2 = newPoints[3][3]
		                	local w0 = newPoints[1][3]

		                	local lambda = math.sqrt(w2/w0)
		                	for i=1,#newPoints do
		                		for j=1,#newPoints[1] do
		                			newPoints[i][j] = newPoints[i][j] * math.pow(lambda,3-i)/w2
		                		end
		                	end

		                	local rationalSegment = getQuadraticSegment(newPoints)

							shapeBoundingBox = updateBoundingBox(rationalSegment["boundingBox"], shapeBoundingBox)
			                --rationalSegments[#rationalSegments + 1] = rationalSegment
			                segments[#segments + 1] = Segment:new(rationalSegment, "quadratic", shape_index)
						else
			                local linearSegment = createLinearSegment(newPoints[1], newPoints[3])
			                ----print("transformed", "linear_segment", newPoints[1][1], newPoints[1][2], newPoints[2][1], newPoints[2][2])
			                shapeBoundingBox = updateBoundingBox(linearSegment["boundingBox"], shapeBoundingBox)
			                --linearSegments[#linearSegments + 1] = linearSegment
			                segments[#segments + 1] = Segment:new(linearSegment, "linear", shape_index)
			            end
	                end
	            end,
	        })))
	        myAccelerated[shape_index]["segments"] = segments
	        myAccelerated[shape_index]["shapeBoundingBox"] = shapeBoundingBox

            shape_index = shape_index + 1
        end,
		begin_transform = function(self, depth, xf)
            --print("begin transform", depth, xf)
            local cur_xf = xf:transformed(transformationStack[depth+1])
            table.insert(transformationStack,cur_xf)
        end,
        end_transform = function(self, depth, xf)
            --print("end transform", depth, xf)
	        table.remove(transformationStack)
        end,
    }
    local limits = {(viewport[1]), (viewport[2]), roundupPow2(viewport[3]), roundupPow2(viewport[4])}
    local k = {}
    local numShapeSegments = {}
    for i=1,shape_index-1 do k[i] = 0;  numShapeSegments[i] = 0; end
    for key,segment in pairs(segments) do
    	numShapeSegments[segment.shapeIndex] = numShapeSegments[segment.shapeIndex] + 1
    end
    quadTree = Cell:new(segments, k, limits, nil, nil, 0, numShapeSegments, 0)
    quadTree:findUsefulShapes()
    quadTree:subdivide()
    --quadTree:printTree()
    --table.unpack(quadTree:findLeaf({1,1}).k)
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
