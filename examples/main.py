import logging
import os

import gymnasium as gym

from gymbizhawk import bizhawk  # noqa F401 # load GymBizhawk env

logging.basicConfig(level=logging.INFO)


def main():
    assert "BIZHAWK_DIR" in os.environ
    assert "ROM_PATH" in os.environ

    env = gym.make(
        "BizHawk-v0",
        bizhawk_dir=os.environ["BIZHAWK_DIR"],
        lua_file=os.path.join(os.path.dirname(__file__), "../gymbizhawk/sample.lua"),
        mode="run",  # "run", "train", "debug"
        observation_type="image",  # "image", "value", "both"
        setup_str_for_lua="1",  # option
    )
    env.reset()

    # 無限に続くのでstep上限を決める
    for step in range(1000):
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
