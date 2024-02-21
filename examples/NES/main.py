import logging
import os

import gymnasium as gym

from gymbizhawk import bizhawk  # noqa F401 # load GymBizhawk env

logging.basicConfig(level=logging.INFO)


def main():
    env = gym.make(
        "BizHawk-v0",
        bizhawk_dir=os.environ["BIZHAWK_DIR"],
        lua_file=os.path.join(os.path.dirname(__file__), "nes.lua"),
        lua_init_str="1",  # load slot
    )
    env.reset()

    # 無限に続くのでstep上限を決める
    for step in range(2000):
        action = env.action_space.sample()
        observation, reward, terminated, truncated, info = env.step(action)
        done = terminated or truncated
        print(f"--- step {step} ---")
        print(f"action     : {action}")
        print(f"observation: {observation.shape}")  # image
        print(f"reward     : {reward}")
        print(f"done       : {done}")
    env.close()


if __name__ == "__main__":
    main()
