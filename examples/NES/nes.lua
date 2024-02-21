package.path = package.path .. ';../../gymbizhawk/bizhawk.lua'

local bizhawk = require('bizhawk')

-- "P1 A": "False"
-- "P1 B": "False"
-- "P1 Down": "False"
-- "P1 Left": "False"
-- "P1 Right": "False"
-- "P1 Select": "False"
-- "P1 Start": "False"
-- "P1 Up": "False"
-- "Power": "False"
-- "Reset": "False"

local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "NES"
    this.ROM = os.getenv("NES_PATH")
    this.HASH = ""
    this.ACTION = {
        "bool", -- A
        "bool", -- B
        "bool", -- Down
        "bool", -- Left
        "bool", -- Right
        "bool", -- Up
        "bool", -- Select
        "bool", -- Start
    }
    this.OBSERVATION = "int"

    this.init = function(self, env, py_init_str)
        self.env = env
        if py_init_str == "" then
            self.loadslot = -1
        else
            self.loadslot = tonumber(py_init_str)
        end
    end

    this.reset = function(self)
        if self.loadslot ~= -1 then
            savestate.loadslot(self.loadslot)
        end
    end

    this.step = function(self, action)
        local buttons = joypad.get()
        for k, val in pairs(buttons) do buttons[k] = false end
        buttons["P1 A"] = action[1]
        buttons["P1 B"] = action[2]
        buttons["P1 Down"] = action[3]
        buttons["P1 Left"] = action[4]
        buttons["P1 Right"] = action[5]
        buttons["P1 Up"] = action[6]
        buttons["P1 Select"] = action[7]
        buttons["P1 Start"] = action[8]
        joypad.set(buttons)
        emu.frameadvance()
        return 0, false
    end

    return this
end


---- main
local env = bizhawk.new("_nes.log")
env:run(EnvProcessor.new())
