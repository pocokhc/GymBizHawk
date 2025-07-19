import logging
import os
from typing import Union, cast

logger = logging.getLogger(__name__)


def print_logger(level: Union[int, str] = logging.INFO, log_name: str = "") -> None:
    if isinstance(level, str):
        level = cast(int, logging.getLevelName(level.upper()))

    logger = logging.getLogger(log_name)
    logger.setLevel(level)
    fmt = "%(asctime)s %(name)s %(funcName)s %(lineno)d [%(levelname)s] %(message)s"
    formatter = logging.Formatter(fmt)

    h = logging.StreamHandler()
    h.setLevel(level)
    h.setFormatter(formatter)
    logger.addHandler(h)


def remove_lua_log(lua_dir: str, log_file: str = "gymenv.log"):
    path = os.path.join(lua_dir, log_file)
    if os.path.isfile(path):
        logger.info(f"remove log file: {os.path.abspath(path)}")
        os.remove(path)
