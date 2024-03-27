package.path = package.path .. ';bizhawk.lua'
local bizhawk = require('bizhawk')


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "ROM"
    this.ROM = bizhawk.getenv_safe("ROM_PATH")
    this.HASH = ""
    this.ACTION = {}
    this.OBSERVATION = "int"

    this.setup = function(self, env, setup_str)
        self.env = env
        if env.platform == "NES" then
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
            self.ACTION = {
                "bool", -- A
                "bool", -- B
                "bool", -- Down
                "bool", -- Left
                "bool", -- Right
                "bool", -- Up
                "bool", -- Select
                "bool", -- Start
            }
        elseif env.platform == "SNES" then
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
            self.ACTION = {
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
        elseif env.platform == "PSX" then
            -- "Close Tray": "False"
            -- "Disk Index": "False"
            -- "Open Tray": "False"
            -- "P1 □": "False"
            -- "P1 △": "False"
            -- "P1 ○": "False"
            -- "P1 Analog": "False"
            -- "P1 D-Pad Down": "False"
            -- "P1 D-Pad Left": "False"
            -- "P1 D-Pad Right": "False"
            -- "P1 D-Pad Up": "False"
            -- "P1 L1": "False"
            -- "P1 L2": "False"
            -- "P1 Left Stick Left / Right": "False"
            -- "P1 Left Stick Up / Down": "False"
            -- "P1 Left Stick, Button": "False"
            -- "P1 R1": "False"
            -- "P1 R2": "False"
            -- "P1 Right Stick Left / Right": "False"
            -- "P1 Right Stick Up / Down": "False"
            -- "P1 Right Stick, Button": "False"
            -- "P1 Select": "False"
            -- "P1 Start": "False"
            -- "P1 X": "False"
            -- "Power": "False"
            -- "Reset": "False"
            self.ACTION = {
                "bool", -- square
                "bool", -- triangle
                "bool", -- circle
                "bool", -- x
                "bool", -- L TODO
                "bool", -- R
                "bool", -- Down
                "bool", -- Left
                "bool", -- Right
                "bool", -- Up
                "bool", -- Select
                "bool", -- Start
            }
        else
            assert(nil, "NotImplementedError: platform=" .. env.platform)
        end

        if setup_str == "" then
            self.loadslot = -1
        else
            self.loadslot = tonumber(setup_str)
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
        if self.env.platform == "NES" then
            buttons["P1 A"] = action[1]
            buttons["P1 B"] = action[2]
            buttons["P1 Down"] = action[3]
            buttons["P1 Left"] = action[4]
            buttons["P1 Right"] = action[5]
            buttons["P1 Up"] = action[6]
            buttons["P1 Select"] = action[7]
            buttons["P1 Start"] = action[8]
        elseif self.env.platform == "SNES" then
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
        elseif self.env.platform == "PSX" then
            -- TODO
        end
        joypad.set(buttons)
        emu.frameadvance()
        return 0, false
    end

    return this
end


---- main
local env = bizhawk.GymEnv.new("_rom.log")
env:run(EnvProcessor.new())
