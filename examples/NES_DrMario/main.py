import os
import random
from typing import cast

import drmario  # noqa F401 # load drmario env
import gymnasium as gym

from gymbizhawk.utils import print_logger, remove_lua_log

DEBUG = False
print_logger("debug" if DEBUG else "info")


def main():
    remove_lua_log(os.path.dirname(__file__))  # 古いlogを削除
    env = gym.make(
        "DrMario-v0",
        level=0,
        mode=("DEBUG" if DEBUG else "RUN"),
    )
    env.reset()

    drmario_env = cast(drmario.DrMarioEnv, env.unwrapped)

    done = False
    step = 0
    while not done:
        step += 1

        # --- 有効なアクションをランダムに作る
        valid_actions = drmario_env.get_valid_actions()
        assert len(valid_actions) > 0
        action = random.choice(valid_actions)
        # ---

        print(f"--- step {step} ---")
        print(f"action     : {action}")
        observation, reward, terminated, truncated, info = env.step(action)
        done = terminated or truncated
        print(f"observation: {observation.shape}")
        print(f"reward     : {reward}")
        print(f"done       : {done}")

    env.close()


if __name__ == "__main__":
    main()
