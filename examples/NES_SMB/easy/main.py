import os

import gymnasium as gym
import smb  # noqa F401  # load env

from gymbizhawk.utils import remove_lua_log


def main():
    remove_lua_log(os.path.dirname(__file__))  # 古いlogを削除
    env = gym.make("SMB-easy-v0")
    env.reset()

    done = False
    step = 0
    while not done:
        step += 1
        action = env.action_space.sample()
        observation, reward, terminated, truncated, info = env.step(action)
        done = terminated or truncated
        print(f"--- step {step} ---")
        print(f"obs({len(observation)}): {observation}")
        print(f"action     : {action}")
        print(f"reward     : {reward}")
        print(f"done       : {done}")
    env.close()


if __name__ == "__main__":
    main()
