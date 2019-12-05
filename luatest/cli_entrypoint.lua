-- Entrypoint for cli util to keep interface simple and provide compatibility
-- between different global package versions.
return function()
  local result = require('luatest.sandboxed_runner').run()
  os.exit(result)
end
