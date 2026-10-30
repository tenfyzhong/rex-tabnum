return {
    "tenfyzhong/rex-tabnum",
    lazy = true,
    events = function()
        require("rex-tabnum").start(rex)
    end,
}
