
local ok, scheme = pcall(require, "scheme.current")

if ok and type(scheme) == "table" and scheme.primary then
    return scheme
end

return require("scheme.default")
