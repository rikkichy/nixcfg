local path = vim.fn.stdpath("config") .. "/matugen.json"
local file, err, code = io.open(path)
if not file then
  if code == 2 then -- No palette until the first wallpaper theme run.
    vim.cmd.colorscheme("default")
    return
  end
  error(err)
end

local text = file:read(2048)
file:close()
assert(text and #text < 2048, "Empty or oversized Matugen palette: " .. path)
local data = vim.json.decode(text)
assert(data.mode == "dark" or data.mode == "light", "Invalid Matugen mode: " .. path)

require("mini.base16").setup({ palette = data.palette })
vim.o.background = data.mode
vim.g.colors_name = "matugen"
