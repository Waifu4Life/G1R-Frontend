function love.conf(t)
  t.identity = "g1r-frontend"
  t.version = "11.5"
  t.window.title = "G1R Frontend (build 7)"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.resizable = true
  t.window.highdpi = true
  t.modules.physics = false
  t.modules.video = false
end
