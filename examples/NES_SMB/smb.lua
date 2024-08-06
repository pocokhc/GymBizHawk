package.path = package.path .. ';../../gymbizhawk/bizhawk.lua'
local bizhawk = require('bizhawk')


local EnvProcessor = {}
EnvProcessor.new = function()
    local this = {}
    this.NAME = "SMB"
    this.ROM = bizhawk.getenv_safe("SMB_PATH")
    this.HASH = "EA343F4E445A9050D4B4FBAC2C77D0693B1D0922"
    this.ACTION = {
        "bool", -- a
    }
    this.OBSERVATION = "int"

    --- define
    this.W_BLOCKS = 16
    this.H_BLOCKS = 13
    this.BLOCK_SIZE = 16
    this.HALF_BLOCK_SIZE = 8
    this.ENEMY = 5

    this.setup = function(self, env, setup_str)
        self.env = env
        self.look_w = 9
        self.look_h = 6
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

        self._max_stage_mario_x = 0
        self._stepout = 0

        self:_read_memory()
        if self.env.mode ~= "TRAIN" then
            self:_displayDraw()
        end
    end

    this._read_memory = function(self)
        self.mario_x = math.floor((mainmemory.readbyte(0x4AC) + mainmemory.readbyte(0x4AE)) / 2)
        self.mario_y = mainmemory.readbyte(0xCE)
        self.stage_mario_x = mainmemory.readbyte(0x6D) * 0x100 + mainmemory.readbyte(0x86)
        self.stage_mario_y = (mainmemory.readbyte(0xB5) - 1) * 0x100 + mainmemory.readbyte(0xCE)
        self.speed_x = mainmemory.read_s8(0x57)
        self.speed_y = mainmemory.read_s8(0x9F)

        self.mario_tile_x = math.floor(self.mario_x / self.BLOCK_SIZE)
        self.mario_tile_y = math.floor(self.mario_y / self.BLOCK_SIZE) - 1

        -- enemy
        self.enemy_view = {}
        self.enemy_x = {}
        self.enemy_y = {}
        self.enemy_tile_x = {}
        self.enemy_tile_y = {}
        for i = 0, self.ENEMY - 1 do
            self.enemy_view[#self.enemy_view + 1] = mainmemory.readbyte(0xF + i)
            self.enemy_x[#self.enemy_x + 1] = math.floor((mainmemory.readbyte(0x4B0 + i * 4) + mainmemory.readbyte(0x4B2 + i * 4)) /
                2)
            self.enemy_y[#self.enemy_y + 1] = mainmemory.readbyte(0xCF + i)
            self.enemy_tile_x[#self.enemy_tile_x + 1] = math.floor(self.enemy_x[i + 1] / self.BLOCK_SIZE)
            self.enemy_tile_y[#self.enemy_tile_y + 1] = math.floor(self.enemy_y[i + 1] / self.BLOCK_SIZE) - 1
        end

        -- tiles
        self.tiles = {}
        for y = 0, self.H_BLOCKS - 1 do
            for x = 0, self.W_BLOCKS - 1 do
                self.tiles[#self.tiles + 1] = self:_getTile(x, y)
            end
        end

        -- look range
        self.look_x = self.mario_tile_x - 1
    end

    this._getTile = function(self, x, y)
        local base_x = math.floor((-8 + self.stage_mario_x - mainmemory.readbyte(0x3AD)) / self.BLOCK_SIZE)
        local dx = (base_x + x + 1) % 0x20
        local page = math.floor(dx / 0x10)
        local addr = 0x500 + page * 13 * 0x10 + y * 0x10 + (dx % 0x10)

        local val = mainmemory.readbyte(addr)
        if val == 194 then   -- coin
            return 0
        elseif val == 0 then -- empty
            return 0
        else
            return 1
        end
    end

    this._displayDraw = function(self)
        local BoxSize = 5
        local dx = 5
        local dy = 5

        -- gb
        gui.drawBox(
            dx, dy,
            dx + BoxSize * self.W_BLOCKS, dy + BoxSize * self.H_BLOCKS,
            0xFF000000, 0x80808080)

        -- block
        for y = 0, self.H_BLOCKS - 1 do
            for x = 0, self.W_BLOCKS - 1 do
                local n = self.tiles[y * self.W_BLOCKS + x + 1]
                if n ~= 0 then
                    self:_drawBlock(x, y, 0xFF000000)
                end
            end
        end
        for i = 1, self.ENEMY do
            if self.enemy_view[i] == 1 then
                self:_drawBlock(self.enemy_tile_x[i], self.enemy_tile_y[i], 0xFFFF0000)
            end
        end
        self:_drawBlock(self.mario_tile_x, self.mario_tile_y, 0xFF00FF00)

        -- look range
        local _x1 = self.mario_tile_x + 1
        local _x2 = _x1 + self.look_w
        local _y2 = self.H_BLOCKS
        local _y1 = _y2 - self.look_h
        gui.drawBox(_x1 * BoxSize, _y1 * BoxSize, _x2 * BoxSize, _y2 * BoxSize, 0xFFFF00FF, 0x00000000)

        -- other info
        local ddrawy = 15
        local drawy = dy + BoxSize * self.H_BLOCKS + ddrawy + 65
        gui.text(dx, drawy, "screen(" .. self.stage_mario_x .. "," .. self.stage_mario_y .. ")")
        drawy = drawy + ddrawy
        gui.text(dx, drawy,
            "mario(" .. self.mario_x .. "," .. self.mario_y .. ")" ..
            "(" .. self.mario_tile_x .. "," .. self.mario_tile_y .. ")" ..
            " a(" .. self.speed_x .. "," .. self.speed_y .. ")"
        )
        drawy = drawy + ddrawy
        for i = 1, self.ENEMY do
            gui.text(dx, drawy,
                "enemy(" .. self.enemy_x[i] .. "," .. self.enemy_y[i] .. ")" ..
                "(" .. self.enemy_tile_x[i] .. "," .. self.enemy_tile_y[i] .. ")"
            )
            drawy = drawy + ddrawy
        end
        gui.text(dx, drawy, "max " .. self._max_stage_mario_x .. ", stepout " .. self._stepout)
    end

    this._drawBlock = function(self, x, y, color)
        local BoxSize = 5
        local dx = 5
        local dy = 5

        local x1 = dx + x * BoxSize
        local y1 = dy + y * BoxSize
        local x2 = dx + (x + 1) * BoxSize
        local y2 = dy + (y + 1) * BoxSize

        gui.drawBox(x1, y1, x2, y2, color, 0x00000000)
    end


    this.step = function(self, action)
        if action ~= nil then
            self.env:setKeys({
                "P1 Right",
                action[1] and "P1 A" or "",
                "P1 B",
            })
        end
        emu.frameadvance()

        self:_read_memory()
        if self.env.mode ~= "TRAIN" then
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
        if self.mario_y > 210 then
            return -1, true, false
        end
        if mainmemory.readbyte(0xE) == 0x0 then
            return -1, true, false
        end

        -- 進んだら
        local reward = -0.01
        if self.stage_mario_x > self._max_stage_mario_x then
            reward = (self.stage_mario_x - self._max_stage_mario_x)/10
            self._max_stage_mario_x = self.stage_mario_x
            self._stepout = 0
        else
            -- 一定時間進まなかったら終わり
            self._stepout = self._stepout + 1
            if self._stepout > 60 * 2 then
                return -1, false, true
            end
        end
        return reward, false, false
    end

    this.backup = function(self)
        local d = {}
        d[#d + 1] = self._max_stage_mario_x
        d[#d + 1] = self._stepout
        return d
    end
    this.restore = function(self, d)
        self._max_stage_mario_x = d[1]
        self._stepout = d[2]
        self:_read_memory()
    end


    this.getObservation = function(self)
        local d = {}
        --d[#d + 1] = self.mario_x
        --d[#d + 1] = self.mario_y
        --d[#d + 1] = self.speed_x
        --d[#d + 1] = self.speed_y
        d[#d + 1] = self._stepout

        ---- mario y
        for y = 1, 10 do
            if y == self.mario_tile_y then
                d[#d + 1] = 1
            else
                d[#d + 1] = 0
            end
        end
        ---- mario y speed
        for y = -4, 4 do
            if y == self.speed_y then
                d[#d + 1] = 1
            else
                d[#d + 1] = 0
            end
        end
        ---- mario x speed
        d[#d + 1] = (self.speed_x <= 0) and 1 or 0
        for x = 1, 40 do
            if x == self.speed_x then
                d[#d + 1] = 1
            else
                d[#d + 1] = 0
            end
        end
        ---- block
        for y = self.H_BLOCKS - 1 - self.look_h, self.H_BLOCKS - 1 - 1 do
            for x = self.mario_tile_x, self.mario_tile_x + self.look_w - 1 do
                local b = self.tiles[y * self.W_BLOCKS + x + 1]
                if b ~= 0 then
                    d[#d + 1] = 1
                else
                    d[#d + 1] = 0
                end
            end
        end
        ---- enemy
        for y = self.H_BLOCKS - 1 - self.look_h, self.H_BLOCKS - 1 - 1 do
            for x = self.mario_tile_x, self.mario_tile_x + self.look_w - 1 do
                local n = 0
                for i = 1, self.ENEMY do
                    if self.enemy_view[i] == 1 then
                        if (self.enemy_tile_x[i] == x) and (self.enemy_tile_y[i] == y) then
                            n = 1
                        end
                    end
                end
                d[#d + 1] = n
            end
        end
        return d
    end

    return this
end

-- main
bizhawk.run(EnvProcessor.new())
