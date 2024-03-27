import os
import random

import drmario  # noqa F401 # load drmario env
import gymnasium as gym


def main():
    assert "BIZHAWK_DIR" in os.environ
    assert "DRMARIO_PATH" in os.environ

    env = gym.make(
        "DrMario-v0",
        bizhawk_dir=os.environ["BIZHAWK_DIR"],
        level=0,
        mode="eval",  # "debug", "train", "eval"
        observation_type="value",  # "image", "value", "both"
    )
    env.reset()

    done = False
    step = 0
    while not done:
        step += 1

        # --- 有効なアクションをランダムに作る
        valid_actions = env.unwrapped.get_valid_actions()
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
