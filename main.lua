jit.on()
love.graphics.setDefaultFilter("nearest", "nearest")

local Emulator = require("Core.Emulator")
local bit = require("bit")
local bnot, band, bor, bxor, lshift, rshift, truncate = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift, math.modf

--TODO: Properly check if the controllers are connected.
--TODO: Add keyboard input
--TODO: Add touch input
local joystickTbl = love.joystick.getJoysticks()
local joy1 = joystickTbl[1]

local Image = 0
local ImageData = 0
local Ret = 0

function love.load()
  
end
function love.update(dt) 
  Image, ImageData, Ret = Emulator.Run()
  
  local controller1 = 0
  if joy1:isGamepadDown("dpright") then controller1 = bor(controller1, 0x01) end
  if joy1:isGamepadDown("dpleft") then controller1 = bor(controller1, 0x02) end
  if joy1:isGamepadDown("dpdown") then controller1 = bor(controller1, 0x04) end
  if joy1:isGamepadDown("dpup") then controller1 = bor(controller1, 0x08) end
  if joy1:isGamepadDown("back") then controller1 = bor(controller1, 0x10) end --select 
  if joy1:isGamepadDown("start") then controller1 = bor(controller1, 0x20) end
  if joy1:isGamepadDown("x") then controller1 = bor(controller1, 0x40) end 
  if joy1:isGamepadDown("a") then controller1 = bor(controller1, 0x80) end
  
  Emulator.Controller1 = controller1
  Image:replacePixels(ImageData)
end
function love.draw()
  love.graphics.print("Framerate: " .. love.timer.getFPS(), 0, 0)
  love.graphics.print("Emulator: " .. Ret, 0, 25)
  
  love.graphics.draw(Image, 150, 50)
end