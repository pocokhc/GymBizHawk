import os

import gymnasium.envs.registration

from gymbizhawk.bizhawk import BizHawkEnv

gymnasium.envs.registration.register(
    id="SMB-image-v0",
    entry_point=__name__ + ":SMBImage",
)


class SMBImage(BizHawkEnv):
    def __init__(self, **kwargs):
        assert "BIZHAWK_DIR" in os.environ
        assert "SMB_PATH" in os.environ  # used lua
        super().__init__(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "smb.lua"),
            observation_type="IMAGE",
            display_name="BizHawk-SMB-image",
            **kwargs,
        )


gymnasium.envs.registration.register(
    id="SMB-ram-v0",
    entry_point=__name__ + ":SMBram",
)


class SMBram(BizHawkEnv):
    def __init__(self, **kwargs):
        assert "BIZHAWK_DIR" in os.environ
        assert "SMB_PATH" in os.environ  # used lua
        super().__init__(
            bizhawk_dir=os.environ["BIZHAWK_DIR"],
            lua_file=os.path.join(os.path.dirname(__file__), "smb.lua"),
            observation_type="RAM",
            display_name="BizHawk-SMB-ram",
            **kwargs,
        )
