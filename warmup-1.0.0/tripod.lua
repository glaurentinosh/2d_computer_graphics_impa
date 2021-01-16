local image = require"image"

local function wrap(i, n)
    i = (i-1) % (2*n)
    if i < n then return i+1
    else return 2*n-i end
end

local function point(img, x, y)
    x = wrap(x, img:get_width())
    y = wrap(y, img:get_height())
    img:set_pixel(x, y, 1)
end

local function sign(v)
    if v < 0 then return -1
    elseif v > 0 then return 1
    else return 0 end
end

function vline(img, x, y1, y2)
    if y2 < y1 then y1, y2 = y2, y1 end
    for y = y1, y2 do
        point(img, x, y)
    end
end

function hline(img, x1, x2, y)
    if x2 < x1 then x1, x2 = x2, x1 end
    for x = x1, x2 do
        point(img, x, y)
    end
end

function linene(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    -- line equation is dx*(y-y1)-dy*(x-x1) = 0
    -- negative to the right of the line
    -- start midopoint at x1+.5,y1+.5
    local e = .5*(dx-dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        -- midpoint to the right
        -- means we crossed the top border
        if e <= 0 then
            -- go up
            y = y + 1
            e = e + dx
        -- midpoint to the left
        -- means we crossed the right border
        else
            -- go right
            x = x + 1
            e = e - dy
        end
        point(img, x, y)
    end
end

function linenw(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    -- line equation is dx*(y-y1)-dy*(x-x1) = 0
    -- negative to the right of the line
    -- start midopoint at x1-.5,y1+.5
    local e = .5*(dx+dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        -- midpoint to the right
        -- means we crossed the left border
        if e <= 0 then
            -- go left
            x = x - 1
            e = e + dy
        -- midpoint to the left
        -- means we crossed the top border
        else
            -- go up
            y = y + 1
            e = e + dx
        end
        point(img, x, y)
    end
end

function linesw(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    -- line equation is -dx(y-y1)+dy(x-x1) = 0
    -- negative to the right of the line
    -- start midopoint at x1-.5,y1-.5
    local e = .5*(dx-dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        -- midpoint to the right
        -- means we crossed the left border
        if e <= 0 then
            -- go left
            x = x - 1
            e = e - dy
        -- midpoint to the left
        -- means we crossed the bottom border
        else
            -- go down
            y = y - 1
            e = e + dx
        end
        point(img, x, y)
    end
end

function linese(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    -- line equation is -dx(y-y1)+dy(x-x1) = 0
    -- negative to the right of the line
    -- start midopoint at x1+.5,y1-.5
    local e = .5*(dx+dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        -- midpoint to the right
        -- means we crossed the bottom border
        if e <= 0 then
            -- go down
            y = y - 1
            e = e + dx
        -- midpoint to the left
        -- means we crossed the right border
        else
            -- go right
            x = x + 1
            e = e + dy
        end
        point(img, x, y)
    end
end

-- this is the version that uses all four quadrant implementations
function line(img, x1, y1, x2, y2)
    if y2 > y1 then
        if x2 > x1 then
            linene(img, x1, y1, x2, y2)
        elseif x2 == x1 then
            vline(img, x1, y1, y2)
        else
            linenw(img, x1, y1, x2, y2)
        end
    elseif y2 < y1 then
        if x2 > x1 then
            linese(img, x1, y1, x2, y2)
        elseif x2 == x1 then
            vline(img, x1, y1, y2)
        else
            linesw(img, x1, y1, x2, y2)
        end
    else
        hline(img, x1, x2, y1)
    end
end

-- this is the version cuts down to two quadrant implementations
-- by swapping endpoints
function line(img, x1, y1, x2, y2)
    if y1 ~= y2 then
        if y2 < y1 then x1, y1, x2, y2 = x2, y2, x1, y1 end
        if x2 > x1 then
            linene(img, x1, y1, x2, y2)
        elseif x2 == x1 then
            vline(img, x1, y1, y2)
        else
            linenw(img, x1, y1, x2, y2)
        end
    else
        hline(img, x1, x2, y1)
    end
end

function linene(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    local e = .5*(dx-dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        if e > 0 then
            x = x + 1
            e = e - dy
        else
            y = y + 1
            e = e + dx
        end
        point(img, x, y)
    end
end

function linenw(img, x1, y1, x2, y2)
    local dx, dy = x2-x1, y2-y1
    local e = .5*(dx+dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        if e <= 0 then
            x = x - 1
            e = e + dy
        else
            y = y + 1
            e = e + dx
        end
        point(img, x, y)
    end
end

-- now we unify linene and linenw
function linenew(img, x1, y1, x2, y2)
    local dx = x2-x1
    local sx = sign(dx)
    local dy = sx*(y2-y1)
    local e = .5*(dx-dy)
    local x, y = x1, y1
    point(img, x, y)
    while x ~= x2 or y ~= y2 do
        if (e > 0) ~= (sx < 0) then
            x = x + sx
            e = e - dy
        else
            y = y + 1
            e = e + dx
        end
        point(img, x, y)
    end
end

-- only need one version of the code
function line(img, x1, y1, x2, y2)
    if y1 ~= y2 then
        if y2 < y1 then x1, y1, x2, y2 = x2, y2, x1, y1 end
        if x2 ~= x1 then
            linenew(img, x1, y1, x2, y2)
        else
            vline(img, x1, y1, y2)
        end
    else
        hline(img, x1, x2, y1)
    end
end

local halfwidth, halfheight = 256, 256
local n = 20

function clear(img)
    for i = 1, img:get_height() do
        for j = 1, img:get_width() do
            img:set_pixel(j, i, 0)
        end
    end
    return img
end

local outputimage = clear(image.image(2*halfwidth+1, 2*halfheight+1, 1))

for i = 0, n do
    local x = math.floor((1-i/n)*halfwidth+0.5)
    local y = math.floor((i/n)*halfheight+0.5)
    line(outputimage, halfwidth, halfheight+y, halfwidth+x, halfheight)
    line(outputimage, halfwidth, halfheight-y, halfwidth+x, halfheight)
    line(outputimage, halfwidth, halfheight+y, halfwidth-x, halfheight)
    line(outputimage, halfwidth, halfheight-y, halfwidth-x, halfheight)
end

local filename = "tripod.png"

local file = assert(io.open(filename, "wb"), "unable to open output file")
assert(image.png.store8(file, outputimage))
file:close()
