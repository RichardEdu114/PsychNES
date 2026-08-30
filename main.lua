jit.on()

love.graphics.setDefaultFilter("nearest", "nearest")

function love.load()
  
end
function love.update(dt) 
  
end
function love.draw()
  love.graphics.print("Framerate: " .. love.timer.getFPS(), 0, 0)
end