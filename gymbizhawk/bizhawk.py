import errno
import logging
import os
import re
import selectors
import socket
import subprocess
import traceback
from typing import List, Literal, Optional, cast

import cv2
import gymnasium as gym
import gymnasium.envs.registration
import numpy as np

logger = logging.getLogger(__name__)


gymnasium.envs.registration.register(
    id="BizHawk-v0",
    entry_point=__name__ + ":BizHawkEnv",
    nondeterministic=True,
)


ModeTypes = Literal["RUN", "FAST_RUN", "RECORD", "DEBUG"]
ObservationTypes = Literal["VALUE", "IMAGE", "BOTH", "RAM"]


class BizHawkError(Exception):
    pass


class ReciveError(BizHawkError):
    pass


class BizHawkSpaces:
    def __init__(self, types_str: str, size: int):
        self.emu_types = [str(x.strip()) for x in types_str.split(",") if x.strip() != ""]
        self._decode_space(size)

    def _decode_space(self, size: int):
        self.gym_spaces: List[gym.spaces.Space] = []
        self.spaces_info: list = []
        space_size = 0
        for t_str in self.emu_types:
            # [N]
            m = re.search(r"\[(\d+)\]", t_str.split(" ")[0])
            if m is None:
                num = 1
            else:
                num = int(m.group(1))

            # *
            if size > 0:
                if "*" in t_str:
                    num = size - space_size

            # space
            if t_str.startswith("bool"):
                for _ in range(num):
                    self.gym_spaces.append(gym.spaces.Discrete(2))
                    self.spaces_info.append({"n": 1, "type": "bool", "space": "Discrete"})
            elif t_str.startswith("int"):
                args = [t.strip() for t in t_str.split(" ") if t.strip() != ""]
                if len(args) == 1:
                    self.gym_spaces.append(gym.spaces.Box(-np.inf, np.inf, (num,), dtype=np.int64))
                    self.spaces_info.append({"n": num, "type": "int", "space": "Box_int"})
                else:
                    low = int(args[1], base=0)
                    high = int(args[2], base=0)
                    space = gym.spaces.Discrete(high - low + 1, start=low)
                    for _ in range(num):
                        self.gym_spaces.append(space)
                        self.spaces_info.append({"n": 1, "type": "int", "space": "Discrete"})
            elif t_str.startswith("float"):
                args = [t.strip() for t in t_str.split(" ") if t.strip() != ""]
                if len(args) == 1:
                    low = -np.inf
                    high = np.inf
                else:
                    low = float(args[1])
                    high = float(args[2])
                self.gym_spaces.append(gym.spaces.Box(low, high, (num,), dtype=np.float32))
                self.spaces_info.append({"n": num, "type": "float", "space": "Box"})
            else:
                raise BizHawkError(t_str)
            space_size += num

    def get_gym_space(self) -> gym.spaces.Space:
        return self.gym_spaces[0] if len(self.gym_spaces) == 1 else gym.spaces.Tuple(self.gym_spaces)

    def decode_obs(self, state_str: str):
        states = []
        idx = 0
        vals_all = state_str.split(" ")
        for info in self.spaces_info:
            vals = vals_all[idx : idx + info["n"]]
            if info["space"] == "Discrete":
                assert len(vals) == 1, str(info)
                states.append(int(vals[0]))
            elif info["space"] == "Box_int":
                states.append(np.array(vals, dtype=np.int64))
            elif info["space"] == "Box":
                states.append(np.array(vals, dtype=np.float32))
            else:
                raise ValueError(info)
            idx += info["n"]
        if len(states) == 1:
            return states[0]
        else:
            return states

    def encode_action(self, acts: list) -> str:
        if len(self.spaces_info) == 1:
            acts = [acts]
        if isinstance(acts, np.ndarray):
            acts = acts.tolist()
        if isinstance(acts, tuple):
            acts = list(acts)

        emu_act = []
        for info, act in zip(self.spaces_info, acts):
            if isinstance(act, np.ndarray):
                act = act.tolist()
            if isinstance(act, tuple):
                act = list(act)

            if info["space"] == "Discrete":
                if isinstance(act, list):
                    act = act[0]
                emu_act.append(str(int(act)))
            elif info["space"] == "Box_int":
                for a in act:
                    emu_act.append(str(int(a)))
            elif info["space"] == "Box":
                for a in act:
                    emu_act.append(str(a))
            else:
                raise ValueError(info)

        return " ".join(emu_act)

    def decode_invalid_actions(self, inv_act_str: str):
        #  アクションセット毎の配列（なので2次元配列）
        # 区切りは"_"と","、最後に_が入る
        # float: 未定義
        invalid_actions = []
        for inv_act_str in inv_act_str.split("_"):
            inv_act_str = inv_act_str.strip()
            if inv_act_str == "":
                continue
            inv_act_str_split = inv_act_str.split(",")
            inv_act = []
            for i, info in enumerate(self.spaces_info):
                val_str = inv_act_str_split[i].strip()
                if info["space"] == "Discrete":
                    inv_act.append(int(val_str, base=0))
                elif info["space"] == "Box_int":
                    inv_act.append(int(val_str, base=0))
                else:
                    pass
            invalid_actions.append(inv_act)
        return invalid_actions


class BizHawkEnv(gym.Env):
    metadata = {"render_modes": ["rgb_array"], "render_fps": 60}

    def __init__(self, render_mode: str | None = None, display_name: str = "", **kwargs):
        self.render_mode = render_mode
        self.display_name = display_name
        self.bizhawk = BizHawk(**kwargs)
        self.metadata["render_fps"] /= kwargs.get("frameskip", 0) + 1

        self.bizhawk.boot()
        self.action_space = self.bizhawk.action_space
        self.observation_space = self.bizhawk.observation_space

        self.backup_count = 0
        self.screen = None

    def close(self):
        self.bizhawk.close()

    def reset(self, seed: Optional[int] = None, options: Optional[dict] = None):
        super().reset(seed=seed)
        state, info = self.bizhawk.reset()
        return state, info

    def step(self, action: list):
        state, reward, terminated, truncated, info = self.bizhawk.step(action)
        info["backup"] = self.backup_count
        return state, reward, terminated, truncated, info

    def render(self):  # super
        if self.render_mode != "rgb_array":
            print("You are calling render method without specifying any render mode.")
            return

        try:
            import pygame
        except ImportError as e:
            raise BizHawkError("pygame is not installed, run `pip install pygame`") from e
        if self.screen is None:
            pygame.init()
            self.screen = pygame.Surface((self.bizhawk.image_shape[1], self.bizhawk.image_shape[0]))

        if self.bizhawk.step_img is None:
            img = self.bizhawk.fetch_image(self.bizhawk.image_shape)
        else:
            img = self.bizhawk.step_img
        img = img.swapaxes(0, 1)
        img = pygame.surfarray.make_surface(img)
        self.screen.blit(img, (0, 0))
        return np.transpose(np.array(pygame.surfarray.pixels3d(self.screen)), axes=(1, 0, 2))

    # ------------------------------------------
    # SRL
    # ------------------------------------------
    def get_display_name(self) -> str:
        if self.display_name == "":
            return ""
        return self.display_name

    def setup(self, training: bool, **kwargs):
        if self.bizhawk.mode not in ["DEBUG", "RECORD"]:
            self.bizhawk.set_mode("FAST_RUN")

    def get_invalid_actions(self):
        return self.bizhawk.get_invalid_actions()

    def backup(self):
        b = self.backup_count
        self.backup_count += 1
        self.bizhawk.send("save " + f"t{b}.dat")
        return b

    def restore(self, dat) -> None:
        self.bizhawk.send("load " + f"t{dat}.dat")


class BizHawk:
    def __init__(
        self,
        bizhawk_dir: str,
        lua_file: str,
        mode: ModeTypes = "RUN",
        observation_type: ObservationTypes = "VALUE",
        frameskip: int = 0,
        silent: bool = True,
        lua_wkdir: str = "lua_wkdir",
        setup_str_for_lua: str = "",
        socket_ip: str = "127.0.0.1",
        socket_port: int = 30000,
        socket_buffer_size: int = 1024 * 1024,
        socket_timeout=None,
        resend_num: int = 5,
    ):
        self.bizhawk_dir = os.path.abspath(bizhawk_dir)
        self.lua_file = os.path.abspath(lua_file)
        self.mode = cast(ModeTypes, mode.upper())
        self.observation_type = cast(ObservationTypes, observation_type.upper())
        self.frameskip = frameskip
        self.silent = silent
        self.resend_num = resend_num

        self.lua_wkdir = lua_wkdir
        if self.lua_wkdir != "":
            self.lua_wkdir = os.path.abspath(self.lua_wkdir)
            self.lua_wkdir = self.lua_wkdir.replace("\\", "/")
            assert "|" not in self.lua_wkdir, f"'|' cannot be used. ({self.lua_wkdir})"
            os.makedirs(self.lua_wkdir, exist_ok=True)
            if self.lua_wkdir[-1] != "/":
                self.lua_wkdir += "/"
            logger.info(f"lua wkdir: {self.lua_wkdir}")

        assert "|" not in setup_str_for_lua, f"'|' cannot be used. ({setup_str_for_lua})"
        self.setup_str_for_lua = setup_str_for_lua

        self._send_count = 0
        self.emu = None
        self.image_shape = (0, 0)
        self.platform = ""

        # -- socket
        self.server = SocketServer(socket_ip, socket_port, socket_buffer_size, socket_timeout)

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self.close()

    def __del__(self):
        self.close()

    def close(self):
        if self.mode in ["DEBUG", "RECORD"]:
            self.send("frameadvance_loop")
            print("GymBizHawk closing. (When the program is terminated, the emu closes, so I stop it for debugging purposes.)")
            input("continue> ")
        self.send("close")
        self.server.close()
        if self.emu is not None:
            logger.info("bizhawk closing.")
            try:
                self.emu.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            finally:
                self.emu.kill()
                self.emu = None

    def boot(self):
        # --- run bizhawk
        os.environ["GYMBIZHAWK"] = "1"
        cmd = os.path.join(self.bizhawk_dir, "EmuHawk.exe")
        cmd += " --luaconsole"
        cmd += " --socket_ip={}".format(self.server.host)
        cmd += " --socket_port={}".format(self.server.port)
        cmd += " --lua={}".format(self.lua_file)
        logger.info(f"bizhawk run: {cmd}")
        self.emu = subprocess.Popen(cmd)

        # --- connect
        if not self.server.connect_wait():
            raise BizHawkError("connection fail.")
        os.environ["GYMBIZHAWK"] = "0"

        # --- 1st send
        s = "a|{}|{}|{}|{}|{}|{}".format(
            self.mode,
            self.observation_type,
            self.frameskip,
            "1" if self.silent else "0",
            "_" if self.lua_wkdir == "" else self.lua_wkdir,
            "_" if self.setup_str_for_lua == "" else self.setup_str_for_lua,
        )
        logger.info(f"1st send data: {s}")
        self.send(s)

        # --- 1st recv
        d = self.recv(enable_split=True)
        if d is None:
            logger.info("1st recv fail.")
            self.close()
            return
        # [0] platform
        self.platform = d[0].strip()
        logger.info(f"platform   : {self.platform}")
        # [1] action_space
        self.action_emu_spaces = BizHawkSpaces(d[1], size=-1)
        logger.info(f"action     : {self.action_emu_spaces.emu_types}")
        self.action_space: gym.spaces.Space = self.action_emu_spaces.get_gym_space()
        if self.observation_type in ["VALUE", "BOTH"]:
            # [2][3] obs_size, obs_space
            obs_size = int(d[2].strip())
            self.obs_emu_spaces = BizHawkSpaces(d[3], size=obs_size)
            logger.info(f"observation: {obs_size}, {self.obs_emu_spaces.emu_types}")
        elif self.observation_type == "RAM":
            # [2] memory_size
            memory_size = int(d[2].strip())

        self.invalid_actions = []

        # 画像情報を取得
        img = self.fetch_image()
        self.image_shape = img.shape
        logger.info(f"image shape: {self.image_shape}]")

        # --- obs space
        if self.observation_type == "VALUE":
            self.observation_space: gym.spaces.Space = self.obs_emu_spaces.get_gym_space()
        elif self.observation_type == "IMAGE":
            self.observation_space: gym.spaces.Space = gym.spaces.Box(0, 255, shape=self.image_shape, dtype=np.uint8)
        elif self.observation_type == "RAM":
            self.observation_space: gym.spaces.Space = gym.spaces.MultiDiscrete([255] * memory_size, dtype=np.uint8)
        elif self.observation_type == "BOTH":
            obs_spaces = self.obs_emu_spaces.gym_spaces[:]
            obs_spaces.insert(0, gym.spaces.Box(0, 255, shape=self.image_shape, dtype=np.uint8))
            self.observation_space: gym.spaces.Space = gym.spaces.Tuple(obs_spaces)
        logger.info(f"action space     : {self.action_space}")
        logger.info(f"observation space: {self.observation_space}]")

    # -----------------------
    # Communication
    # -----------------------
    def send(self, data: str) -> None:
        self._send_count += 1
        # Since BizHawk 2.6.2, all responses must be of the form $"{msg.Length:D} {msg}"
        # i.e. prefixed with the length in base-10 and a space.
        data = f"{len(data)} {data}"
        self.server.send(data)

    def recv(self, enable_split: bool = False):
        data = self.server.recv(enable_decode=True)
        if data is None:
            raise BizHawkError()
        data = str(data).strip()
        if enable_split:
            return [v.strip() for v in data.split("|")]
        return data

    def _recv_screenshot(self, resize_shape=None) -> np.ndarray:
        img_raw = self.server.recv(enable_decode=False)
        if img_raw is None:
            raise BizHawkError("image recv fail")
        img_arr = np.frombuffer(img_raw, dtype=np.uint8)
        img = cv2.imdecode(img_arr, cv2.IMREAD_COLOR)
        if (self.image_shape != (0, 0)) and (img.shape[:1] != self.image_shape[:1]):
            img = cv2.resize(img, (self.image_shape[1], self.image_shape[0]))
        if resize_shape is None or img.shape == resize_shape:
            logger.debug(f"recv img: {img.shape}")
        else:
            old_shape = img.shape
            img = cv2.resize(img, resize_shape[:1])
            logger.debug(f"recv img: {old_shape} -> {img.shape}")
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        return img

    def fetch_image(self, resize_shape=None) -> np.ndarray:
        self.send("screenshot")
        return self._recv_screenshot(resize_shape)

    def _decode_observation(self, obs_str: str):
        img = None
        if self.observation_type == "VALUE" or self.observation_type == "BOTH":
            obs = self.obs_emu_spaces.decode_obs(obs_str)
            logger.debug(f"{self._send_count} obs: {str(obs):100s}")
        elif self.observation_type == "RAM":
            state = self._decode_ram(obs_str)
            logger.debug(f"{self._send_count} obs: {str(state):100s}")

        if self.observation_type == "IMAGE" or self.observation_type == "BOTH":
            # ssを取得する
            img = self.fetch_image(self.image_shape)
            logger.debug(f"{self._send_count} img {img.shape}")

        if self.observation_type == "VALUE":
            state = obs
        elif self.observation_type == "IMAGE":
            state = img
        elif self.observation_type == "BOTH":
            state = [img, obs]
        return state, img

    def _decode_ram(self, ram_str: str):
        mem: List[int] = []
        for bin in ram_str.strip().split(" "):
            try:
                n = int(bin.strip())
            except ValueError:
                logger.debug(f"int fail: {n}")
                n = 0
            mem.append(n)
        return mem

    def _decode_info(self, info_str: str):
        info = {}
        for pair in info_str.strip().split("#"):
            d = pair.strip().split(":")
            if len(d) != 2:
                continue
            try:
                info[d[0]] = float(d[1])
            except ValueError:
                logger.debug(f"float fail: {d}")
                continue
        return info

    # -----------------------------
    # gym
    # -----------------------------
    def reset(self):
        # --- reset
        # send: "r"
        # recv:  invalid_actions "|" observation
        self.send("reset")
        for i in range(self.resend_num):
            try:
                recv_str_list = self.recv(enable_split=True)
                self.invalid_actions = self.action_emu_spaces.decode_invalid_actions(recv_str_list[0])
                state, img = self._decode_observation(recv_str_list[1])
                self.step_img = img
                info = self._decode_info(recv_str_list[2])
                return state, info
            except ReciveError:
                logger.info(f"resend: {i + 1}")
                self.send("resend")
        raise BizHawkError("recv fail.")

    def step(self, action: list):
        act_str = self.action_emu_spaces.encode_action(action)
        self.send(f"step {act_str}")

        # --- 3. recv
        # invalid_actions "|" reward "|" terminated "|" truncated "|" observation
        # reward     : float
        # terminated : "0" or "1"
        # truncated  : "0" or "1"
        for i in range(self.resend_num):
            try:
                recv_str_list = self.recv(enable_split=True)
                self.invalid_actions = self.action_emu_spaces.decode_invalid_actions(recv_str_list[0])
                reward = float(recv_str_list[1])
                terminated = True if recv_str_list[2] == "1" else False
                truncated = True if recv_str_list[3] == "1" else False
                state, img = self._decode_observation(recv_str_list[4])
                self.step_img = img
                info = self._decode_info(recv_str_list[5])
                return state, reward, terminated, truncated, info
            except ReciveError:
                logger.info(f"resend: {i + 1}")
                self.send("resend")
        raise BizHawkError("recv fail.")

    # -----------------------------
    # other
    # -----------------------------
    def get_invalid_actions(self):
        return self.invalid_actions

    def set_mode(self, mode: ModeTypes | str):
        self.mode = cast(ModeTypes, mode.upper())
        self.send(f"mode {self.mode}")


class SocketServer:
    def __init__(
        self,
        host: str,
        port: int,
        buffer_size: int = 1024 * 128,
        timeout: int | None = None,
    ):
        self.host = host
        self.port = port
        self.buffer_size = buffer_size
        self.timeout = timeout
        self.conn = None
        self.selector = None

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        for _ in range(100):
            try:
                self.sock.bind((self.host, self.port))
                break
            except OSError as e:
                if e.errno == errno.EADDRINUSE:
                    self.port += 1
                elif e.errno == errno.WSAEADDRINUSE:
                    self.port += 1
                else:
                    self.close()
                    raise
        logger.info(f"socket wait: {self.host}:{self.port} (timeout: {timeout})")
        self.sock.listen(1)
        self.sock.setblocking(False)

        # timeout処理用
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.sock, selectors.EVENT_READ)

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self.close()

    def __del__(self):
        self.close()

    def close(self) -> None:
        if self.selector is not None:
            logger.debug("selector close.")
            self.selector.close()
            self.selector = None
        if self.conn is not None:
            logger.debug("connection close.")
            self.conn.close()
            self.conn = None
        if self.sock is not None:
            logger.debug("socket close.")
            self.sock.close()
            self.sock = None

    def connect_wait(self) -> bool:
        if self.sock is None:
            return False
        if self.selector is None:
            return False

        while True:
            events = self.selector.select(timeout=self.timeout)
            # timeoutは events=[]

            for key, _ in events:
                if key.fileobj != self.sock:
                    continue

                self.conn, addr = self.sock.accept()
                logger.info("socket connected: {}".format(addr))
                self.conn.setblocking(False)
                self.selector.register(self.conn, selectors.EVENT_READ)
                return True

            return False

    def send(self, data: str) -> bool:
        if self.conn is None:
            return False
        logger.debug("send: {}".format(data))
        self.conn.send(data.encode(encoding="utf-8"))
        return True

    def recv(self, enable_decode: bool) -> str | bytes | None:
        if self.conn is None:
            return None
        if self.selector is None:
            return None

        while True:
            events = self.selector.select(timeout=self.timeout)
            # timeoutは events=[]

            for key, _ in events:
                if key.fileobj != self.conn:
                    continue
                try:
                    # f"{msg.Length:D} {msg}" i.e. prefixed with the length in base-10 and a space.
                    data = b""
                    while True:
                        try:
                            chunk = self.conn.recv(self.buffer_size)
                            if not chunk:
                                break
                            data += chunk
                        except BlockingIOError as e:
                            if e.errno == errno.EWOULDBLOCK:
                                break
                            if e.errno == errno.WSAEWOULDBLOCK:
                                break
                            raise

                    # --- data size check
                    idx = data.find(b" ")
                    if idx != -1:
                        msg_len = -1
                        try:
                            msg_len = int(data[:idx])
                            data = data[idx + 1 :]
                        except ValueError:
                            s = f"Unable to read recv data size number: {data[:1000]}"
                            logger.info(traceback.format_exc())
                            logger.warning(s)
                            raise ReciveError(s)
                        if msg_len > 0 and len(data) != msg_len:
                            s = f"recv data size is different: recv size {len(data)}!={msg_len}, {data[:1000]}"
                            logger.info(traceback.format_exc())
                            logger.warning(s)
                            raise ReciveError(s)
                    logger.debug("recv: {} {}".format(msg_len, data[:100]))

                    # --- close/error別処理
                    if len(data) < 10:
                        dat = data.decode("utf-8", "ignore").strip()
                        if dat in ["close", "error"]:
                            return None

                    if enable_decode:
                        data = data.decode("utf-8", "ignore")
                    return data
                except ReciveError:
                    raise
                except Exception as e:
                    logger.warning(f"recv data fail: {e}")
                    return None
            return None
