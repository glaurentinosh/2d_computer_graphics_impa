if #arg < 3 then
    io.stderr:write("quantize <input> <levels> <output>\n")
    os.exit(1)
end

local image = require"image"
local inputname = arg[1]
assert(type(inputname) == "string" and inputname:lower():sub(-3) == "png",
    "invalid output name")
local inputimage = image.png.load(assert(io.open(inputname, "rb")), 1)
local levels = assert(tonumber(arg[2]), "invalid levels")
assert(levels > 0, "invalid number of levels")
local filename = arg[3]
assert(type(filename) == "string" and filename:lower():sub(-3) == "png",
    "invalid output name")

local floor = math.floor

local function quantizeimage(image, levels)
    levels = levels-1
    for i = 1, image:get_height() do
        for j = 1, image:get_width() do
            local g = image:get_pixel(j, i)*levels
            g = floor(g + .5)/levels
            image:set_pixel(j, i, g)
        end
    end
    return image
end

local file = assert(io.open(filename, "wb"), "unable to open output file")
assert(image.png.store8(file, quantizeimage(inputimage, levels)))
file:close()
