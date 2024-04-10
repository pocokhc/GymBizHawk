package.path = package.path .. ';../../gymbizhawk/bizhawk.lua'
local bizhawk = require('bizhawk')

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


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "moon"
    this.ROM = bizhawk.getenv_safe("MOON_PATH")
    this.HASH = "BF5383C5" -- first ROM version
    this.ACTION = { "bool" }
    this.OBSERVATION = "int"

    this.setup = function(self, env, setup_str)
        self.env = env
    end

    this.reset = function(self)
        savestate.loadslot(9)

        -- rand
        local r = math.random(1, 100)
        for i = 1, r do
            emu.frameadvance()
        end

        self.env:setKey("P1 ○")
        emu.frameadvance()
        for i = 1, 600 do
            emu.frameadvance()
        end

        self:skip_start()
        self.prev_lv = mainmemory.readbyte(0x1119EE)
    end

    this.skip_start = function(self)
        local state = mainmemory.read_s8(0x111801)
        while state ~= 28 do
            emu.frameadvance()
            state = mainmemory.read_s8(0x111801)
        end
    end

    this.step = function(self, action)
        self.env:setKey(action[1] and "P1 ○" or "")
        emu.frameadvance()

        local lv = mainmemory.readbyte(0x1119EE)
        local y = mainmemory.read_s16_le(0x1119EA)
        local x = mainmemory.read_s16_le(0x1119E8)
        local goal_y = mainmemory.read_s16_le(0x1119EC)

        if lv == 6 then
            return 100, true
        end
        if self.prev_lv + 1 == lv then
            self.prev_lv = lv
            self:skip_start()
            return 100, false
        end

        if y <= 0 then
            return -100, true
        elseif y >= 240 then
            return -100, true
        end
        if x > 240 then
            return -100, true
        end

        if math.abs(goal_y - y) < 5 then
            return 0.1, false
        else
            return 0, false
        end
    end

    this.getObservation = function(self)
        local y = mainmemory.read_s16_le(0x1119EA)
        local goal_y = mainmemory.read_s16_le(0x1119EC)
        local d = {}
        d[#d + 1] = mainmemory.read_s16_le(0x1119E6) -- ay
        --d[#d + 1] = mainmemory.read_s16_le(0x1119E8) -- x
        d[#d + 1] = y
        d[#d + 1] = goal_y - y
        d[#d + 1] = mainmemory.readbyte(0x1119EE) -- lv
        return d
    end

    return this
end


---- main
local env = bizhawk.GymEnv.new("_moon.log")
env:run(EnvProcessor.new())
