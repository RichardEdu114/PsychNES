jit.on()

local Emulator = require("Core.Emulator")
love.graphics.setDefaultFilter("nearest", "nearest")
local Image = 0
local ImageData = 0

function love.load()
  
end
function love.update(dt) 
  Image, ImageData = Emulator.Run()
end
function love.draw()
  love.graphics.print("Framerate: " .. love.timer.getFPS(), 0, 0)
  --love.graphics.print("Emulator: " .. Image, 0, 50)
  
  Image:replacePixels(ImageData)
  love.graphics.draw(Image, 50, 50)
end