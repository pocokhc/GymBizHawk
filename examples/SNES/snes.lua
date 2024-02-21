package.path = package.path .. ';../../gymbizhawk/bizhawk.lua'

local bizhawk = require('bizhawk')

-- "P1 A": "False"
-- "P1 B": "False"
-- "P1 Down": "False"
-- "P1 L": "False"
-- "P1 Left": "False"
-- "P1 R": "False"
-- "P1 Right": "False"
-- "P1 Select": "False"
-- "P1 Start": "False"
-- "P1 Up": "False"
-- "P1 X": "False"
-- "P1 Y": "False"
-- "P2 A": "False"
-- "P2 B": "False"
-- "P2 Down": "False"
-- "P2 L": "False"
-- "P2 Left": "False"
-- "P2 R": "False"
-- "P2 Right": "False"
-- "P2 Select": "False"
-- "P2 Start": "False"
-- "P2 Up": "False"
-- "P2 X": "False"
-- "P2 Y": "False"
-- "Power": "False"
-- "Reset": "False"


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "SNES"
    this.ROM = os.getenv("SNES_PATH")
    this.HASH = ""
    this.ACTION = {
        "bool", -- A
        "bool", -- B
        "bool", -- X
        "bool", -- Y
        "bool", -- L
        "bool", -- R
        "bool", -- Down
        "bool", -- Left
        "bool", -- Right
        "bool", -- Up
        "bool", -- Select
        "bool", -- Start
    }
    this.OBSERVATION = "int"

    this.init = function(self, env, py_init_str)
        print(joypad.get())
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
        buttons["P1 X"] = action[3]
        buttons["P1 Y"] = action[4]
        buttons["P1 L"] = action[5]
        buttons["P1 R"] = action[6]
        buttons["P1 Down"] = action[7]
        buttons["P1 Left"] = action[8]
        buttons["P1 Right"] = action[9]
        buttons["P1 Up"] = action[10]
        buttons["P1 Select"] = action[11]
        buttons["P1 Start"] = action[12]
        joypad.set(buttons)
        emu.frameadvance()
        return 0, false
    end

    return this
end


---- main
local env = bizhawk.new("_snes.log")
env:run(EnvProcessor.new())
