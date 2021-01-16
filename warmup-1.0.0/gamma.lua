local image = require"image"

local w = 60
local h = 4*w
local g = 20

local sqrt = math.sqrt

img = image.image(12*w+4*g, h+2*g, 4)

for y = 1, img:get_height() do
    for x = 1, img:get_width() do
        img:set_pixel(x, y, 0, 1, 0, 1)
    end
end

print(img:get_width(), img:get_height())

local values = {
    {0, 137, 188},
    {255, 188, 0},
    {255, 225, 188},
}

local function hline(img, y, xmin, xmax, v)
    for x = xmin, xmax do
        img:set_pixel(x, y, v, v, v, 1)
    end
end

for y = g, g+w do
    for i,v in ipairs(values) do
        x = g + (i-1)*(g+4*w)
        if y % 2 == 1 then
            hline(img, y, x, x+4*w, v[1]/255.0)
        else
            hline(img, y, x, x+4*w, v[3]/255.0)
        end
    end
end

for y = g+w+1, g+3*w do
    for i,v in ipairs(values) do
        x = g + (i-1)*(g+4*w)
        if y % 2 == 1 then
            hline(img, y, x, x+w, v[1]/255.0)
            hline(img, y, x+w+1, x+3*w, v[2]/255.0)
            hline(img, y, x+3*w+1, x+4*w, v[1]/255.0)
        else
            hline(img, y, x, x+w, v[3]/255.0)
            hline(img, y, x+w+1, x+3*w, v[2]/255.0)
            hline(img, y, x+3*w+1, x+4*w, v[3]/255.0)
        end
    end
end

for y = g+3*w+1, h+g do
    for i,v in ipairs(values) do
        x = g + (i-1)*(g+4*w)
        if y % 2 == 1 then
            hline(img, y, x, x+4*w, v[1]/255.0)
        else
            hline(img, y, x, x+4*w, v[3]/255.0)
        end
    end
end

local function ungamma(v)
    v = v/255.
    local a = 0.055;
    if v <= 0.04045 then v = v/12.92;
    else v = ((v+a)/(1.+a))^2.4 end
    return v*255.
end

local function gamma(v)
    v = v/255.
    local a = 0.055;
    if v <= 0.0031308 then v = 12.92*v
    else v = (1.+a)*v^(1./2.4)-a end
    return 255.*v
end

for i,v in ipairs(values) do
    print(v[1], v[2], v[3])
    print(gamma(.5*(ungamma(v[1])+ungamma(v[3]))), v[2])
end

local f = assert(io.open("gamma.png", "wb"))
assert(image.png.store8(f, img))
f:close()
