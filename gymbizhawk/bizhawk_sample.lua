package.path = package.path .. ';../gymbizhawk/bizhawk.lua'

local bizhawk = require('bizhawk')


local SampleEnv = {}
SampleEnv.new = function()
    this = {}
    this.NAME = "sample"
    this.ROM = "Bizhawk load rom path"
    this.HASH = "RomHash(option)"
    this.ACTION = {"bool"}  -- TODO

    this.init = function(self, env, py_init_str)
        self.env = env
        self.py_init_str = py_init_str
    end

    this.reset = function(self)
        -- Define initial state
        -- (BizHawk's QL is also assumed, so it's quite vague (TODO))

        -- savestate.loadslot(1)
    end
    
    this.step = function(self, action)
        -- Explanatory text TODO
        -- コントローラを設定し、報酬と終了を返す
        return reward, done
    end

    this.getObservation = function(self)
        -- Explanatory text TODO
        local d = {}
        d[#d+1] = mainmemory.read_s16_le(0x1119E6)  -- ay
        d[#d+1] = mainmemory.read_s16_le(0x1119E8)  -- x
        d[#d+1] = mainmemory.read_s16_le(0x1119EA)  -- y
        d[#d+1] = mainmemory.read_s16_le(0x1119EC)  -- goal y
        d[#d+1] = mainmemory.readbyte(0x1119EE)  -- LV
        return d
    end
    
    ---------------------------------
    -- valid actions(super)
    -- return list[action_shape]
    ---------------------------------
    this.getValidActions = function(self)
        -- Explanatory text TODO
        self.emu:search_valid_pos(false)

        local d = {}
        for i=1, #self.emu.valid_pos do
            local v = self.emu.valid_pos[i]
            local r = 0  -- right
            if v[3] == "up" then
                r = 1
            end

            print(v)
            a = bit.lshift(v[1]-1, 6)
            a = a + bit.lshift(v[2]-1, 2)
            a = a + bit.lshift(r, 1)

            d[#d+1] = a + bit.lshift(0, 1)
            d[#d+1] = a + bit.lshift(1, 1)
        end
        return d
    end
    
    return this
end


------------------------------------
-- main
------------------------------------
local env = bizhawk.new("_sample.log")
env:run(SampleEnv.new())
