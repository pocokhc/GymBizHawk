"""
Sample code running with the reinforcement learning framework SRL
https://github.com/pocokhc/simple_distributed_rl
"""

import logging
import os

import pygame
import srl

from gymbizhawk import bizhawk  # noqa F401 # load GymBizhawk env

logging.basicConfig(level=logging.INFO)


def main():
    env_config = srl.EnvConfig(
        "BizHawk-v0",
        kwargs=dict(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "nes.lua"),
        ),
    )
    runner = srl.Runner(env_config)
    runner.play_window(
        key_bind={
            "z": (0, True),
            "x": (1, True),
            pygame.K_UP: (5, True),
            pygame.K_RIGHT: (4, True),
            pygame.K_LEFT: (3, True),
            pygame.K_DOWN: (2, True),
            "c": (6, True),
            "v": (7, True),
        }
    )


if __name__ == "__main__":
    main()
