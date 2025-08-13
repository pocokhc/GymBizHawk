import os

import gymnasium as gym

from gymbizhawk import bizhawk  # noqa F401 # load GymBizhawk env
from gymbizhawk.utils import print_logger, remove_lua_log

print_logger()


def main():
    assert "BIZHAWK_DIR" in os.environ
    assert "ROM_PATH" in os.environ  # used lua

    # 古いlogを削除
    remove_lua_log(os.path.dirname(__file__))

    env = gym.make(
        "BizHawk-v0",
        bizhawk_dir=os.environ["BIZHAWK_DIR"],
        lua_file=os.path.join(os.path.dirname(__file__), "sample.lua"),
        mode="RUN",  # "RUN", "FAST_RUN", "RECORD", "DEBUG"
        observation_type="IMAGE",  # "VALUE", "IMAGE", "BOTH"
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
