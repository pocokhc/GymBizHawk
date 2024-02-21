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
            lua_file=os.path.join(os.path.dirname(__file__), "snes.lua"),
        ),
    )
    runner = srl.Runner(env_config)
    runner.play_window(
        key_bind={
            "z": (1, True),
            "x": (0, True),
            "a": (3, True),
            "s": (2, True),
            "q": (4, True),
            "w": (5, True),
            pygame.K_UP: (9, True),
            pygame.K_RIGHT: (8, True),
            pygame.K_LEFT: (7, True),
            pygame.K_DOWN: (6, True),
            "c": (10, True),
            "v": (11, True),
        }
    )


if __name__ == "__main__":
    main()
