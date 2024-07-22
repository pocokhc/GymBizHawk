import enum
import errno
import logging
import os
import selectors
import socket
import subprocess

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


class ModeTypes(enum.Enum):
    DEBUG = enum.auto()
    TRAIN = enum.auto()
    RUN = enum.auto()

    @staticmethod
    def get_names() -> list[str]:
        return [i.name for i in ModeTypes]

    @staticmethod
    def from_str(mode: "str | ModeTypes") -> "ModeTypes":
        if isinstance(mode, str):
            mode = mode.upper()
            names = ModeTypes.get_names()
            assert mode in names, "Unknown type '{}'. type list is [{}].".format(
                mode,
                ",".join(names),
            )
            mode = ModeTypes[mode]
        return mode


class ObservationTypes(enum.Enum):
    VALUE = enum.auto()
    IMAGE = enum.auto()
    BOTH = enum.auto()

    @staticmethod
    def get_names() -> list[str]:
        return [i.name for i in ObservationTypes]

    @staticmethod
    def from_str(mode: "str | ObservationTypes") -> "ObservationTypes":
        if isinstance(mode, str):
            mode = mode.upper()
            names = ObservationTypes.get_names()
            assert mode in names, "Unknown type '{}'. type list is [{}].".format(
                mode,
                ",".join(names),
            )
            mode = ObservationTypes[mode]
        return mode


class BizHawkError(Exception):
    pass


class BizHawkEnv(gym.Env):
    metadata = {"render_modes": ["rgb_array"]}

    def __init__(self, render_mode: str | None = None, **kwargs):
        self.bizhawk = BizHawk(**kwargs)
        self.render_mode = render_mode

        self.bizhawk.boot()
        self.action_space = self.bizhawk.action_space
        self.observation_space = self.bizhawk.observation_space

        self.backup_count = 0
        self.screen = None

    def close(self):
        self.bizhawk.close()

    def reset(self):
        state = self.bizhawk.reset()
        return state, {}

    def step(self, action: list):
        state, reward, done = self.bizhawk.step(action)
        return state, reward, done, False, {}

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
            self.clock = pygame.time.Clock()

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
    def setup(self, rendering: bool, **kwargs):
        if not rendering:
            self.bizhawk.set_mode(ModeTypes.TRAIN)

    def get_invalid_actions(self):
        return self.bizhawk.get_invalid_actions()

    def backup(self):
        b = self.backup_count
        self.backup_count += 1
        self.bizhawk.send(f"save _t{b}.dat")
        return b

    def restore(self, data) -> None:
        self.bizhawk.send(f"load _t{data}.dat")


class BizHawk:
    def __init__(
        self,
        bizhawk_dir: str,
        lua_file: str,
        mode: ModeTypes | str = ModeTypes.RUN,
        observation_type: ObservationTypes | str = ObservationTypes.VALUE,
        silent: bool = True,
        setup_str_for_lua: str = "",
        socket_ip: str = "127.0.0.1",
        socket_port: int = 30000,
        socket_buffer_size: int = 1024 * 1024,
        socket_timeout=None,
    ):
        """_summary_

        Args:
            bizhawk_dir (str): _description_
            lua_file (str): _description_
            observation_type (Union[ObservationTypes, str], optional): _description_. Defaults to ObservationTypes.IMAGE.
            setup_str_for_lua (str, optional): _description_. Defaults to "".
            socket_ip (str, optional): _description_. Defaults to "127.0.0.1".
            socket_port (int, optional): _description_. Defaults to 30000.
            socket_buffer_size (int, optional): _description_. Defaults to 1024*1024.
            socket_timeout (_type_, optional): _description_. Defaults to None.

        Raises:
            BizHawkError: _description_
        """
        self.bizhawk_dir = os.path.abspath(bizhawk_dir)
        self.lua_file = os.path.abspath(lua_file)
        self.mode = ModeTypes.from_str(mode)
        self.observation_type = ObservationTypes.from_str(observation_type)
        self.silent = silent
        self.setup_str_for_lua = setup_str_for_lua.replace("|", "")

        self._send_count = 0
        self.emu = None
        self.image_shape = (0, 0)
        self.platform = ""

        # -- init
        self.server = SocketServer(socket_ip, socket_port, socket_buffer_size, socket_timeout)
        self.socket_ip = socket_ip
        self.socket_port = self.server.port

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self.close()

    def __del__(self):
        self.close()

    def close(self):
        if self.mode == ModeTypes.DEBUG:
            self.send("frameadvance")
            input("closing. continue> ")
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
        cmd = os.path.join(self.bizhawk_dir, "EmuHawk.exe")
        cmd += " --luaconsole"
        cmd += " --socket_ip={}".format(self.socket_ip)
        cmd += " --socket_port={}".format(self.socket_port)
        cmd += " --lua={}".format(self.lua_file)
        logger.debug("bizhawk run: {}".format(cmd))
        self.emu = subprocess.Popen(cmd)

        # --- connect
        if not self.server.connect_wait():
            raise BizHawkError("connection fail.")

        # --- 1st send
        s = "a|{}|{}|{}|{}".format(
            self.mode.name,
            self.observation_type.name,
            "1" if self.silent else "0",
            "_" if self.setup_str_for_lua == "" else self.setup_str_for_lua,
        )
        self.send(s)

        # --- 1st recv
        d = self.recv(enable_split=True)
        if d is None:
            logger.info("1st recv fail.")
            self.close()
            return
        img = self._recv_image()
        self.image_shape = img.shape
        logger.info(f"image shape: {self.image_shape}]")

        self.platform = d[0].strip()
        logger.info(f"platform   : {self.platform}")
        self.action_types = [str(x.strip()) for x in d[1].split(",") if x.strip() != ""]
        logger.info(f"action     : {self.action_types}")
        if self.observation_type in [ObservationTypes.VALUE, ObservationTypes.BOTH]:
            d2 = d[2].split(",")
            obs_size = int(d2[0].strip())
            obs_type = d2[1].strip()
            logger.info(f"observation: {obs_size}, {obs_type}")
        self.invalid_actions = []

        # --- action space
        acts = [self._decode_space_type(a) for a in self.action_types]
        self.action_space = gym.spaces.Tuple(acts)

        # --- obs space
        if self.observation_type == ObservationTypes.VALUE:
            self.observation_space = self._decode_space_type(obs_type, shape=(obs_size,))
        elif self.observation_type == ObservationTypes.IMAGE:
            self.observation_space = gym.spaces.Box(0, 255, shape=self.image_shape, dtype=np.uint8)
        elif self.observation_type == ObservationTypes.BOTH:
            self.observation_space = gym.spaces.Tuple(
                [
                    gym.spaces.Box(0, 255, shape=self.image_shape, dtype=np.uint8),
                    self._decode_space_type(obs_type, shape=(obs_size,)),
                ]
            )
        logger.info(f"action space     : {self.action_space}")
        logger.info(f"observation space: {self.observation_space}]")

    def _decode_space_type(self, type_str: str, shape=(1,)) -> gym.spaces.Space:
        if type_str == "bool":  # "bool"
            return gym.spaces.Discrete(2)
        elif type_str.startswith("int"):  # "int 0 255"
            s = type_str.split(" ")
            if len(s) == 1:
                low = -np.inf
                high = np.inf
                return gym.spaces.Box(low, high, shape, dtype=np.int64)
            elif shape == (1,):
                low = int(s[1], 0)
                high = int(s[2], 0)
                return gym.spaces.Discrete(high - low + 1, start=low)
            else:
                low = int(s[1], 0)
                high = int(s[2], 0)
                return gym.spaces.Box(low, high, shape, dtype=np.int64)
        elif type_str.startswith("float"):  # "float 0.0 1.0"
            s = type_str.split(" ")
            if len(s) == 1:
                low = -np.inf
                high = np.inf
            else:
                low = int(s[1], 0)
                high = int(s[2], 0)
            return gym.spaces.Box(low, high, shape, dtype=np.float32)
        else:
            raise BizHawkError(type_str)

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

    def _recv_image(self, resize_shape=None) -> np.ndarray:
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

    def _decode_observation(self, obs_str: str) -> np.ndarray:
        # "s1 s2 s3 s4" スペース区切り
        return np.array([float(o) for o in obs_str.split(" ")])

    def _decode_invalid_actions(self, inv_act_str: str):
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
            for i, t in enumerate(self.action_types):
                val_str = inv_act_str_split[i].strip()
                if t == "bool":
                    inv_act.append(True if val_str == "1" else False)
                elif t.startswith("int"):
                    inv_act.append(int(val_str, 0))
                else:
                    inv_act.append(0)
            invalid_actions.append(inv_act)
        return invalid_actions

    def fetch_image(self, resize_shape=None) -> np.ndarray:
        self.send("image")
        return self._recv_image(resize_shape)

    def _recv_extend_observation(self, obs_str):
        # (recv1): s + observation
        #    sは元で受信する
        #    observationはimageの場合は""
        # recv2: image
        #    imageとbothの場合のみ送信
        img = None
        if self.observation_type == ObservationTypes.VALUE or self.observation_type == ObservationTypes.BOTH:
            obs = self._decode_observation(obs_str)
            logger.debug(f"{self._send_count} obs {obs.shape}: {str(obs):100s}")

        if self.observation_type == ObservationTypes.IMAGE or self.observation_type == ObservationTypes.BOTH:
            img = self._recv_image(self.image_shape)
            logger.debug(f"{self._send_count} img {img.shape}")

        if self.observation_type == ObservationTypes.VALUE:
            state = obs
        elif self.observation_type == ObservationTypes.IMAGE:
            state = img
        elif self.observation_type == ObservationTypes.BOTH:
            state = [img, obs]
        return state, img

    # -----------------------------
    # gym
    # -----------------------------
    def reset(self):
        # --- reset
        # send: "r"
        # recv:  invalid_actions "|" observation
        self.send("reset")
        recv_str_list = self.recv(enable_split=True)
        self.invalid_actions = self._decode_invalid_actions(recv_str_list[0])
        state, img = self._recv_extend_observation(recv_str_list[1])
        self.step_img = img
        return state

    def step(self, action: list):
        # --- 1. send "s act1 act2 act3" スペース区切り
        if isinstance(action, np.ndarray):
            action = action.tolist()
        if isinstance(action, tuple):
            action = list(action)
        _a = []
        for i, t in enumerate(self.action_types):
            a = action[i]
            if isinstance(a, np.ndarray):
                a = a.tolist()
            if isinstance(a, tuple):
                a = list(a)
            if isinstance(a, list):
                a = a[0]
            if t == "bool":
                _a.append("1" if a else "0")
            elif t.startswith("int"):
                _a.append(str(a))
            elif t.startswith("float"):
                _a.append(str(a))
            else:
                _a.append(str(a))

        act_str = " ".join(_a)
        self.send(f"step {act_str}")

        # --- 3. recv
        # invalid_actions "|" reward "|" done "|" observation
        # reward     : float
        # done       : "0" or "1"
        recv_str_list = self.recv(enable_split=True)
        self.invalid_actions = self._decode_invalid_actions(recv_str_list[0])
        reward = float(recv_str_list[1])
        done = True if recv_str_list[2] == "1" else False
        state, img = self._recv_extend_observation(recv_str_list[3])
        self.step_img = img
        return state, reward, done

    # -----------------------------
    # other
    # -----------------------------
    def get_invalid_actions(self):
        return self.invalid_actions

    def set_mode(self, mode: ModeTypes | str):
        self.mode = ModeTypes.from_str(mode)
        self.send(f"mode {self.mode.name}")


class SocketServer:
    def __init__(
        self,
        host: str,
        port: int,
        buffer_size: int = 1024 * 128,
        timeout: int | None = None,
    ):
        self.buffer_size = buffer_size
        self.timeout = timeout
        self.port = port

        self.conn = None
        self.selector = None

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        for _ in range(100):
            try:
                self.sock.bind((host, self.port))
                break
            except OSError as e:
                if e.errno == errno.EADDRINUSE:
                    logger.info(f"{port}port used.")
                    self.port += 1
                elif e.errno == errno.WSAEADDRINUSE:
                    logger.info(f"{port}port used.")
                    self.port += 1
                else:
                    self.close()
                    raise
        logger.info(f"socket wait: {host}:{self.port} (timeout: {timeout})")
        self.sock.listen(1)
        self.sock.setblocking(False)

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
                            logger.warning(f"Unable to read recv data size number: {data[:1000]}")
                        if msg_len > 0 and len(data) != msg_len:
                            logger.warning(
                                f"recv data size is different: recv size {len(data)}!={msg_len}, {data[:1000]}"
                            )
                    logger.debug("recv: {}".format(data[:100]))

                    # --- closeだけ別処理
                    if len(data) < 10 and data.decode("utf-8", "ignore").strip() == "close":
                        return None

                    if enable_decode:
                        data = data.decode("utf-8", "ignore")
                    return data
                except Exception as e:
                    logger.warning(f"recv data fail: {e}")
                    self.close()
                    return None
            return None
