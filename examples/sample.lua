-- **Set the path to 'bizhawk.lua'**
package.path = package.path .. ';../gymbizhawk/bizhawk.lua'
local bizhawk = require('bizhawk')


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "ROM"
    this.ROM = bizhawk.getenv_safe("ROM_PATH")
    this.HASH = ""
    this.ACTION_SPACE = {}
    this.OBSERVATION_SPACE = {"int"}

    -- implement function
    this.setup = function(self, env, setup_str)
        self.env = env
        self.buttons = joypad.get()
        self.buttons["Power"] = nil
        self.buttons["Reset"] = nil
        for key in pairs(self.buttons) do
            if not string.find(key, "P1") then
                self.buttons[key] = nil
            end
            if string.find(key, "Select") then
                self.buttons[key] = nil
            end
            if string.find(key, "Start") then
                self.buttons[key] = nil
            end
        end

        print("--- button list")
        self.ACTION_SPACE = {}
        for key in pairs(self.buttons) do
            self.ACTION_SPACE[#self.ACTION_SPACE+1] = "bool"
            print(key)
        end

        if setup_str == "" then
            self.loadslot = -1
        else
            self.loadslot = tonumber(setup_str)
        end
    end

    -- implement function
    this.reset = function(self)
        if self.loadslot ~= -1 then
            savestate.loadslot(self.loadslot)
        end
    end

    -- implement function
    --   action: list[bool] (This is what was decided in self.ACTION)
    --   return reward, terminated, truncated
    this.step = function(self, action)
        local buttons = joypad.get()
        for k, val in pairs(buttons) do buttons[k] = false end
        
        local i = 1
        for key in pairs(self.buttons) do
            buttons[key] = action[i]
            i = i + 1
        end

        joypad.set(buttons)
        emu.frameadvance()

        return 0, false, false
    end

    -- option
    --   return observation values(list)
    this.getObservation = function(self)
        local d = {}
        return d
    end

    -- option
    --   return list[self.ACTION_SPACE list]
    this.getInvalidActions = function(self)
        local d = {}
        return d
    end

    -- backup/restore option
    this.backup = function(self)
        local d = {}
        return d
    end
    this.restore = function(self, d)
    end

    return this
end

-- main
bizhawk.run(EnvProcessor.new())
