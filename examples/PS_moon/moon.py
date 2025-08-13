import os

import gymnasium.envs.registration

from gymbizhawk.bizhawk import BizHawkEnv

gymnasium.envs.registration.register(
    id="moon-v0",
    entry_point=__name__ + ":MoonEnv",
)


class MoonEnv(BizHawkEnv):
    def __init__(self, **kwargs):
        assert "BIZHAWK_DIR" in os.environ
        assert "MOON_PATH" in os.environ  # used lua
        super().__init__(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "moon.lua"),
            display_name="BizHawk-moon",
            **kwargs,
        )
