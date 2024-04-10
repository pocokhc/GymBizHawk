import os

import gymnasium as gym

from gymbizhawk import bizhawk  # noqa F401  # load GymBizhawk env


def main():
    assert "BIZHAWK_DIR" in os.environ
    assert "SMB_PATH" in os.environ

    env = gym.make(
        "BizHawk-v0",
        bizhawk_dir=os.environ["BIZHAWK_DIR"],
        lua_file=os.path.join(os.path.dirname(__file__), "smb.lua"),
    )
    env.reset()

    done = False
    step = 0
    while not done:
        step += 1
        action = env.action_space.sample()
        observation, reward, terminated, truncated, info = env.step(action)
        done = terminated or truncated
        print(f"--- step {step} ---")
        print(f"action     : {action}")
        print(f"obs({len(observation):6d}): {observation}")
        print(f"reward     : {reward}")
        print(f"done       : {done}")
    env.close()


if __name__ == "__main__":
    main()
