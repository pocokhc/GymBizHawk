package.path = package.path .. ';../../../gymbizhawk/bizhawk.lua'
local bizhawk = require('bizhawk')


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "SMB"
    this.ROM = bizhawk.getenv_safe("SMB_PATH")
    this.HASH = "EA343F4E445A9050D4B4FBAC2C77D0693B1D0922"
    this.ACTION_SPACE = {
        "bool", -- left
        "bool", -- right
        "bool", -- down
        "bool", -- a
        "bool", -- b
    }
    this.OBSERVATION_SPACE = {}


    this.setup = function(self, env, setup_str)
        self.env = env
        if self.env.observation_type ~= "IMAGE" then
            error("observation_type is IMAGE only")
        end
    end

    this.reset = function(self)
        client.reboot_core()

        -- skip title
        for i = 1, 40 do
            emu.frameadvance()
        end
        self.env:setKey("P1 Start")
        emu.frameadvance()
        for i = 1, 180 do
            emu.frameadvance()
        end

        if self.env.mode ~= "FAST_RUN" then
            self:_displayDraw()
        end
    end


    this._displayDraw = function(self)
        local mario_x = mainmemory.readbyte(0x6D) * 0x100 + mainmemory.readbyte(0x86)
        local mario_y = (mainmemory.readbyte(0xB5) - 1) * 0x100 + mainmemory.readbyte(0xCE)
        local speed_x = mainmemory.read_s8(0x57)
        local speed_y = mainmemory.read_s8(0x9F)

        gui.text(5, 15,
            "mario(" .. mario_x .. "," .. mario_y .. ")" ..
            " a(" .. speed_x .. "," .. speed_y .. ")"
        )
    end


    this.step = function(self, action)
        if action ~= nil then
            self.env:setKeys({
                action[1] and "P1 Left" or "",
                action[2] and "P1 Right" or "",
                action[3] and "P1 Down" or "",
                action[4] and "P1 A" or "",
                action[5] and "P1 B" or "",
            })
        end
        emu.frameadvance()
        if self.env.mode ~= "FAST_RUN" then
            self:_displayDraw()
        end

        -- goal
        if mainmemory.readbyte(0xE) == 0x4 then
            return 100, true, false
        end

        -- dead
        if mainmemory.readbyte(0xE) == 11 then
            return -1, true, false
        end
        local mario_y = (mainmemory.readbyte(0xB5) - 1) * 0x100 + mainmemory.readbyte(0xCE)
        if mario_y > 210 then
            return -1, true, false
        end
        if mainmemory.readbyte(0xE) == 0x0 then
            return -1, true, false
        end

        --- time
        local time = mainmemory.readbyte(0x7F8)*100 + mainmemory.readbyte(0x7F9)*10 + mainmemory.readbyte(0x7FA)
        if time == 0 then
            return -1, true, false
        end

        return 0, false, false
    end

    this.backup = function(self)
        local d = {}
        return d
    end
    this.restore = function(self, d)
    end

    this.getObservation = function(self)
        local d = {}
        return d
    end

    return this
end

-- main
bizhawk.run(EnvProcessor.new())
