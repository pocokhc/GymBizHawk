import os

import gymnasium as gym
import moon  # noqa F401  # load env

from gymbizhawk.utils import print_logger, remove_lua_log

print_logger()


def main():
    remove_lua_log(os.path.dirname(__file__))  # 古いlogを削除
    env = gym.make(
        "moon-v0",
        # mode="debug",
    )

    done = False
    step = 0
    env.reset()
    while not done:
        step += 1
        action = env.action_space.sample()
        observation, reward, terminated, truncated, info = env.step(action)
        done = terminated or truncated
        print(f"--- step {step} ---")
        print(f"action     : {action}")
        print(f"observation: {observation}")
        print(f"reward     : {reward}")
        print(f"done       : {done}")
    env.close()


if __name__ == "__main__":
    main()
