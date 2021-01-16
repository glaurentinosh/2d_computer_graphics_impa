local image = require"image"

local min = math.min
local max = math.max
local floor = math.floor

local function stderr(...)
    io.stderr:write(string.format(...))
end

local function hline(img, y, x1, x2)
    assert(x2 >= x1)
    if x2 < 1 or x1 > img:get_width() then return end
    x1 = min(max(x1, 1), img:get_width())
    x2 = min(max(x2, 1), img:get_width())
    if y >= 1 and y <= img:get_height() then
        for x = x1, x2 do
            img:set_pixel(x, y, 1)
        end
    end
end

local function edge(x1, y1, x2, y2)
    local miny = min(y1, y2)
    local maxy = max(y1, y2)
    assert(y1 ~= y2)
    if y2 > y1 then
        local dxdy = (x2-x1)/(y2-y1)
        return { miny = miny, maxy = maxy, x = x1, xi = floor(x1), dxdy = dxdy }
    else
        local dxdy = (x1-x2)/(y1-y2)
        return { miny = miny, maxy = maxy, x = x2, xi = floor(x2), dxdy = dxdy }
    end
end

local function polygon(img, xs, ys)
    local nvertices = min(#xs, #ys)
    -- build global edge table and obtain min and max y coordinates
    local edges = {}
    local miny, maxy = ys[1], ys[1]
    local nedges = 0
    for i = 2, nvertices do
        if ys[i-1] ~= ys[i] then
            nedges = nedges + 1
            edges[nedges] = edge(xs[i-1], ys[i-1], xs[i], ys[i])
        end
        miny = min(miny, ys[i])
        maxy = max(maxy, ys[i])
    end
    if ys[nvertices] ~= ys[1] then
        nedges = nedges + 1
        edges[nedges] = edge(xs[nvertices], ys[nvertices], xs[1], ys[1])
    end
    -- sort global edge table by miny in decreasing order
    table.sort(edges, function(a, b) return a.miny > b.miny end)
    local active = {}
    local nactive = 0
    for y = miny, maxy do
        -- remove edges that are not active anymore
        local i = 1
        while i <= nactive do
            if active[i].maxy <= y then
                active[i] = active[nactive]
                active[nactive] = nil
                nactive = nactive - 1
            else
                i = i + 1
            end
        end
        -- advance y in active edges
        for i = 1, nactive do
            active[i].x = active[i].x + active[i].dxdy
            active[i].xi = floor(active[i].x+0.5)
        end
        -- add newly active edges
        while nedges >= 1 and edges[nedges].miny == y do
            nactive = nactive + 1
            active[nactive] = edges[nedges]
            nedges = nedges - 1
        end
        -- sort active edges by increasing x
        table.sort(active, function(a,b) return a.xi < b.xi end)
        -- draw spans
        for i = 2, nactive, 2 do
            hline(img, y, active[i-1].xi, active[i].xi)
        end
    end
end

local random = math.random
local function randvec(n, max)
    local t = {}
    for i = 1, n do
        t[i] = random(max)
    end
    return t
end

local function star(n, s, width, height)
    local x = {}
    local y = {}
    x[#x+1] = width/2 + width/2
    y[#y+1] = height/2
    for i = 1, n do
        local a = math.rad(s*i*360/n)
        x[#x+1] = floor(width/2 + width/2 * math.cos(a) + 0.5)
        y[#y+1] = floor(height/2 + height/2 * math.sin(a) + 0.5)
    end
    return x, y
end

function clear(img)
    for i = 1, img:get_height() do
        for j = 1, img:get_width() do
            img:set_pixel(j, i, 0)
        end
    end
    return img
end

local width, height = 512, 512
local xs, ys = star(10, 3, width, height)
--local vertices = 30
--local xs, ys = randvec(vertices, width), randvec(vertices, height)

local outputimage = clear(image.image(width, height, 1))
local filename = "polygon.png"
polygon(outputimage, xs, ys)
local file = assert(io.open("polygon.png", "wb"), "unable to open output file")
assert(image.png.store8(file, outputimage))
file:close()
