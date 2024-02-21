"""
Sample code running with the reinforcement learning framework SRL
https://github.com/pocokhc/simple_distributed_rl
"""

import os

import numpy as np
import srl
from srl.algorithms import rainbow
from srl.utils import common

from gymbizhawk import bizhawk  # noqa F401  # load GymBizhawk env

base_dir = os.path.dirname(__file__)
checkpoint_dir = os.path.join(base_dir, "_checkpoint")
history_dir = os.path.join(base_dir, "_history")
common.logger_print()


def _create_runner():
    env_config = srl.EnvConfig(
        "BizHawk-v0",
        kwargs=dict(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "moon.lua"),
            mode="train",  # "debug", "train", "eval"
            observation_type="value",  # "image", "value", "both"
        ),
    )
    rl_config = rainbow.Config(multisteps=1)
    rl_config.epsilon.set_linear(500_000, 1.0, 0.01)
    rl_config.dueling_network.set((512, 512), enable=True)
    rl_config.memory.warmup_size = 1000
    rl_config.memory.capacity = 100_000

    runner = srl.Runner(env_config, rl_config)
    runner.model_summary()
    return runner


def train():
    runner = _create_runner()
    runner.set_checkpoint(checkpoint_dir, is_load=False, interval=60 * 5)
    runner.set_history_on_file(history_dir)
    runner.train(max_train_count=1_000_000)


def eval():
    runner = _create_runner()

    # --- view history
    history = runner.load_history(history_dir)
    history.plot()

    # --- eval
    runner.load_checkpoint(checkpoint_dir)

    rewards = runner.evaluate(max_episodes=1)
    print(rewards)
    print(np.mean(rewards))
    runner.animation_save_gif(os.path.join(base_dir, "_moon.gif"))


if __name__ == "__main__":
    train()
    eval()
