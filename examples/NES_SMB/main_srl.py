"""
Sample code running with the reinforcement learning framework SRL
v0.17.0
https://github.com/pocokhc/simple_distributed_rl
"""

import os

import mlflow
import srl
from srl.algorithms import rainbow
from srl.utils import common

from gymbizhawk import bizhawk  # noqa F401  # load GymBizhawk env

mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "mlruns"))
base_dir = os.path.dirname(__file__)
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
    rl_config = rainbow.Config(
        multisteps=1,
        lr=0.0002,
        epsilon=0.1,
        discount=0.999,
        target_model_update_interval=5000,
        memory_warmup_size=5_000,
        memory_capacity=100_000,
        memory_compress=False,
        window_length=8,
    )
    rl_config.hidden_block.set_dueling_network((512, 512, 512))
    rl_config.set_proportional_memory()

    runner = srl.Runner(env_config, rl_config)
    runner.model_summary()
    return runner


def train():
    runner = _create_runner()
    runner.set_progress(env_info=True)
    runner.set_mlflow(experiment_name="BizHawk-SMB")

    # runner.train(max_train_count=100)  # debug
    runner.train_mp(actor_num=1, max_train_count=500_000)


def eval():
    runner = _create_runner()
    runner.load_parameter_from_mlflow(experiment_name="BizHawk-SMB")

    # --- eval
    rewards = runner.evaluate(max_episodes=1)
    print(rewards)

    # --- view
    runner.animation_save_gif(os.path.join(base_dir, "_smb.gif"))


if __name__ == "__main__":
    train()
    eval()
