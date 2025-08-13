import os

import gymnasium.envs.registration
import gymnasium.spaces as spaces
import numpy as np

from gymbizhawk.bizhawk import BizHawkEnv

gymnasium.envs.registration.register(
    id="DrMario-v0",
    entry_point=__name__ + ":DrMarioEnv",
    nondeterministic=True,
)


class DrMarioEnv(BizHawkEnv):
    def __init__(self, level: int = 0, render_mode: str | None = None, **kwargs):
        assert "BIZHAWK_DIR" in os.environ
        assert "DRMARIO_PATH" in os.environ  # used lua

        super().__init__(
            render_mode,
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "drmario.lua"),
            setup_str_for_lua=str(level),
            **kwargs,
        )
        self.level = level
        self.W = 8
        self.H = 16
        self.field = [[0 for x in range(self.W)] for y in range(self.H)]

        self.action_space = self.bizhawk.action_space
        self.observation_space = spaces.Box(0, 1, (self.H, self.W, 42), dtype=np.uint8)

    def _create_dummy(self, x: int, y: int, empty: bool) -> dict:
        return {
            "x": x,
            "y": y,
            "empty": empty,
            "color": "",
            "virus": False,
            "direction": "",  # 繋がっている方向
        }

    def reset(self, **kwargs):
        state, info = super().reset(**kwargs)
        state = self._convert_state(state)
        return state, info

    def step(self, action: list):
        state, reward, terminated, truncated, info = super().step(action)
        state = self._convert_state(state)
        return state, reward, terminated, truncated, info

    # --- 状態設計
    # ウイルス層: 1Layer×3 (yellow, red, blue)
    # カプセル層: 9Layer×3 (yellow, red, blue)
    #   0～2: 色
    #   3～8: 隣とつながってるか(up, right, down, left)
    # 今の手(左側): 3Layer(色ごとに全部1か0)
    # 今の手(右側): 3Layer(色ごとに全部1か0)
    # 次の手(左側): 3Layer(色ごとに全部1か0)
    # 次の手(右側): 3Layer(色ごとに全部1か0)
    # 42
    def _convert_state(self, state):
        virus = np.zeros((self.H, self.W, 3))
        capsule = np.zeros((self.H, self.W, 9 * 3))
        for y in range(self.H):
            for x in range(self.W):
                cell = int(state[y * self.W + x])
                if cell == 0xFF:
                    continue

                color = cell & 0x3

                if (cell & 0x80) == 0x80:
                    # ウイルス
                    virus[y][x][color] = 1
                else:
                    # カプセル
                    capsule[y][x][color] = 1
                    # 向き
                    direction = cell & 0x70
                    if direction == 0x40:  # 下と接続
                        capsule[y][x][3] = 1
                    elif direction == 0x50:  # 上と接続
                        capsule[y][x][4] = 1
                    elif direction == 0x60:  # 右と接続
                        capsule[y][x][5] = 1
                    elif direction == 0x70:  # 左と接続
                        capsule[y][x][6] = 1

        hand = []
        for color in [state[0], state[1], state[3], state[4]]:
            if color == 0:
                hand.append(np.ones((self.H, self.W)))
                hand.append(np.zeros((self.H, self.W)))
                hand.append(np.zeros((self.H, self.W)))
            elif color == 1:
                hand.append(np.zeros((self.H, self.W)))
                hand.append(np.ones((self.H, self.W)))
                hand.append(np.zeros((self.H, self.W)))
            else:
                hand.append(np.zeros((self.H, self.W)))
                hand.append(np.zeros((self.H, self.W)))
                hand.append(np.ones((self.H, self.W)))
        hand = np.transpose(hand, (1, 2, 0))  # 元の次元のindex

        state = np.concatenate([virus, capsule, hand], axis=-1)
        return state

    def get_valid_actions(self):
        invalid_actions = self.get_invalid_actions()
        valid_actions = []
        for y in range(16):
            for x in range(8):
                for r in [0, 1]:
                    for c in [0, 1]:
                        f = True
                        for inv in invalid_actions:
                            if str([x + 1, y + 1, r, c]) == str(inv):
                                f = False
                                break
                        if f:
                            valid_actions.append([x + 1, y + 1, r, c])
        return valid_actions
