if #arg < 2 then
    io.stderr:write("diffuse <input> <output>\n")
    os.exit(1)
end

local image = require"image"
local inputname = arg[1]
assert(type(inputname) == "string" and inputname:lower():sub(-3) == "png",
    "invalid output name")
local inputimage = image.png.load(assert(io.open(inputname, "rb")), 1)
local outputname = arg[2]
assert(type(outputname) == "string" and outputname:lower():sub(-3) == "png",
    "invalid output name")

local floor = math.floor

local function zeros(width)
    local row = {}
    for i = 0, width+1 do
        row[i] = 0
    end
    return row
end

local function threshold(t)
    if t > 0.5 then return 1
    else return 0 end
end

local function diffusion(image)
    local next = zeros(image:get_width())
    local current = zeros(image:get_width())
    for i = 1, image:get_height() do
        local right = 0
        current, next = next, current
        for j = 1, image:get_width() do
            local g = image:get_pixel(j, i)+current[j]+right
            local t = threshold(g)
            local e = (g-t)/16
            current[j] = 0
            right = 7*e
            next[j-1] = next[j-1] + 3*e
            next[j]   = next[j] + 5*e
            next[j+1] = next[j+1] + e
            image:set_pixel(j, i, t)
        end
    end
    return image
end

local file = assert(io.open(outputname, "wb"), "unable to open output file")
assert(image.png.store8(file, diffusion(inputimage, levels)))
file:close()
