import os

import mlflow
import moon  # noqa F401  # load env
import srl
from srl.algorithms import rainbow
from srl.utils import common

from gymbizhawk.utils import remove_lua_log

mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "mlruns"))
base_dir = os.path.dirname(__file__)
common.logger_print()


def _create_runner():
    remove_lua_log(os.path.dirname(__file__))  # 古いlogを削除
    env_config = srl.EnvConfig("moon-v0")

    rl_config = rainbow.Config(
        multisteps=1,
        lr=0.0002,
        discount=0.95,
        window_length=4,
    )
    rl_config.hidden_block.set_dueling_network((256, 256, 256))
    rl_config.memory.warmup_size = 1000
    rl_config.memory.capacity = 100_000
    rl_config.memory.compress = False
    rl_config.memory.set_proportional()

    runner = srl.Runner(env_config, rl_config)
    return runner


def train():
    runner = _create_runner()
    runner.set_progress(env_info=True)
    runner.set_mlflow()
    runner.train(max_train_count=500_000)


def eval():
    runner = _create_runner()
    runner.load_parameter_from_mlflow()
    runner.model_summary()

    # --- eval
    rewards = runner.evaluate(max_episodes=1)
    print(rewards)

    # --- view
    runner.animation_save_gif(
        os.path.join(base_dir, "_moon.gif"),
        # max_steps=770,  # LV1
    )


if __name__ == "__main__":
    train()
    eval()
