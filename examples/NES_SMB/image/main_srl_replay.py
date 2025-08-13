import os

import smb  # noqa F401  # load env
import srl

from gymbizhawk.utils import print_logger, remove_lua_log

print_logger()


def main():
    remove_lua_log(os.path.dirname(__file__))  # 古いlogを削除
    env_config = srl.EnvConfig("SMB-image-v0")
    runner = srl.Runner(env_config)
    runner.replay_window()


if __name__ == "__main__":
    main()
