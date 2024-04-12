"""
Sample code running with the reinforcement learning framework SRL
v0.15.2
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
    assert "BIZHAWK_DIR" in os.environ
    assert "SMB_PATH" in os.environ

    env_config = srl.EnvConfig(
        "BizHawk-v0",
        kwargs=dict(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "smb.lua"),
        ),
        frameskip=5,
    )
    rl_config = rainbow.Config(multisteps=1, lr=0.0002, discount=0.99, epsilon=0.05)
    rl_config.hidden_block.set_dueling_network((256, 256, 256))
    rl_config.memory.set_proportional_memory()
    rl_config.memory.warmup_size = 1000
    rl_config.memory.capacity = 100_000
    rl_config.window_length = 8
    rl_config.memory_compress = False

    runner = srl.Runner(env_config, rl_config)
    runner.model_summary()
    return runner


def train():
    runner = _create_runner()
    runner.set_checkpoint(checkpoint_dir, is_load=False)
    runner.set_history_on_file(history_dir)
    # runner.train(max_train_count=100_000)
    runner.train_mp(actor_num=1, max_train_count=1_000_000)


def eval():
    runner = _create_runner()

    # --- eval
    runner.load_checkpoint(checkpoint_dir)

    rewards = runner.evaluate(max_episodes=1)
    print(rewards)
    print(np.mean(rewards))
    runner.animation_save_gif(os.path.join(base_dir, "_smb.gif"))

    # --- view history
    history = runner.load_history(history_dir)
    history.plot()


if __name__ == "__main__":
    train()
    eval()
