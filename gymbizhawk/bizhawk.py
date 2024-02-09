import enum
import errno
import logging
import os
import selectors
import socket
import subprocess
from typing import List, Optional, Union

import cv2
import gymnasium as gym
import gymnasium.envs.registration
import numpy as np

logger = logging.getLogger(__name__)


gymnasium.envs.registration.register(
    id="BizHawk-v0",
    entry_point=__name__ + ":BizHawk",
)


class SpeedTypes(enum.Enum):
    NORMAL = enum.auto()
    FAST = enum.auto()
    DEBUG = enum.auto()

    @staticmethod
    def get_names() -> List[str]:
        return [i.name for i in SpeedTypes]

    @staticmethod
    def from_str(mode: Union[str, "SpeedTypes"]) -> "SpeedTypes":
        if isinstance(mode, str):
            mode = mode.upper()
            names = SpeedTypes.get_names()
            assert mode in names, "Unknown type '{}'. type list is [{}].".format(
                mode,
                ",".join(names),
            )
            mode = SpeedTypes[mode]
        return mode


class ObservationTypes(enum.Enum):
    VALUE = enum.auto()
    IMAGE = enum.auto()
    BOTH = enum.auto()

    @staticmethod
    def get_names() -> List[str]:
        return [i.name for i in ObservationTypes]

    @staticmethod
    def from_str(mode: Union[str, "ObservationTypes"]) -> "ObservationTypes":
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


class BizHawk(gym.Env):
    metadata = {"render_modes": ["rgb_array"]}

    def __init__(
        self,
        bizhawk_dir: str,
        lua_path: str,
        speed: Union[SpeedTypes, str] = SpeedTypes.DEBUG,
        observation_type: Union[ObservationTypes, str] = ObservationTypes.IMAGE,
        lua_init_str: str = "",
        socket_ip: str = "127.0.0.1",
        socket_port: int = 30000,
        socket_buffer_size: int = 1024 * 1024,
        socket_timeout=None,
        render_mode: Optional[str] = None,  # super
    ):
        super().__init__()
        self.speed = SpeedTypes.from_str(speed)
        self.observation_type = ObservationTypes.from_str(observation_type)
        self.lua_init_str = lua_init_str
        self.render_mode = render_mode
        self.screen = None

        self._send_count = 0
        self.bizhawk = None

        # -- init
        self.server = SocketServer(socket_ip, socket_port, socket_buffer_size, socket_timeout)
        self._boot_emulator(bizhawk_dir, lua_path, socket_ip, self.server.port)
        if not self.server.connect_wait():
            raise BizHawkError("connection fail.")
        self._1st_communication()

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self.close()

    def __del__(self):
        self.close()

    def close(self):
        if self.speed == SpeedTypes.DEBUG:
            self._send("frameadvance")
            input("closing. continue>")
        self._send("close")
        self.server.close()
        if self.bizhawk is not None:
            logger.info("bizhawk closing.")
            try:
                self.bizhawk.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            finally:
                self.bizhawk.kill()
                self.bizhawk = None

    def _boot_emulator(
        self,
        bizhawk_dir: str,
        lua_path: str,
        socket_ip,
        socket_port,
    ):
        bizhawk_dir = os.path.abspath(bizhawk_dir)
        lua_path = os.path.abspath(lua_path)

        # --- path
        bizhawk_exe_path = os.path.join(bizhawk_dir, "EmuHawk.exe")

        # --- run bizhawk
        cmd = bizhawk_exe_path
        cmd += " --luaconsole"
        cmd += " --socket_ip={}".format(socket_ip)
        cmd += " --socket_port={}".format(socket_port)
        cmd += " --lua={}".format(lua_path)
        logger.debug("bizhawk run: {}".format(cmd))
        self.bizhawk = subprocess.Popen(cmd)

    # -----------------------
    # Communication
    # -----------------------
    def _1st_communication(self):

        # --- 1st send
        s = "a {} {} {} {}".format(
            self.speed.name,
            self.observation_type.name,
            "_" if self.lua_init_str == "" else self.lua_init_str,
            "_",
        )
        self._send(s)

        # --- 1st recv
        d = self.server.recv(enable_decode=True)
        if d is None:
            logger.info("1st recv fail.")
            self.close()
            return
        self.base_img_shape = ()
        self.used_img = False
        if self.observation_type in [ObservationTypes.IMAGE, ObservationTypes.BOTH]:
            img = self._recv_image()
            self.base_img_shape = img.shape
            self.used_img = True

        d = str(d)
        d = d.split("|")
        self.action_types = [str(x) for x in d[0].split(",") if x.strip() != ""]
        logger.info(f"action      : {self.action_types}")
        if self.observation_type in [ObservationTypes.VALUE, ObservationTypes.BOTH]:
            obs = [int(x) for x in d[1].split(",") if x.strip() != ""]
            obs_size = obs[0]
            obs_low = obs[1]
            obs_high = obs[2]
            logger.info(f"observation : {obs_size} [{obs_low},{obs_high}]")

        # --- space
        acts = []
        for a in self.action_types:
            if a == "bool":
                acts.append(gym.spaces.Discrete(2))
            elif a.startswith("int"):
                s = a.split(" ")
                acts.append(gym.spaces.Box(int(s[0]), int(s[1]), (1,), dtype=np.int32))
            elif a.startswith("float"):
                s = a.split(" ")
                acts.append(gym.spaces.Box(float(s[0]), float(s[1]), (1,), dtype=np.float32))
            else:
                raise BizHawkError(a)
        self.action_space = gym.spaces.Tuple(acts)
        if self.observation_type == ObservationTypes.VALUE:
            self.observation_space = gym.spaces.Box(obs_low, obs_high, shape=(obs_size,))
        elif self.observation_type == ObservationTypes.IMAGE:
            self.observation_space = gym.spaces.Box(0, 255, shape=self.base_img_shape, dtype=np.uint8)
        elif self.observation_type == ObservationTypes.BOTH:
            self.observation_space = gym.spaces.Tuple(
                [
                    gym.spaces.Box(0, 255, shape=self.base_img_shape, dtype=np.uint8),
                    gym.spaces.Box(obs_low, obs_high, shape=(obs_size,)),
                ]
            )
        logger.info(f"action     : {self.action_space}")
        logger.info(f"observation: {self.observation_space}]")

        # --- render
        if self.render_mode == "rgb_array":
            if not self.used_img:
                self._send("image")
                img = self._recv_image()
                self.used_img = True
                self.base_img_shape = img.shape

        return

    def _send(self, data: str) -> None:
        self._send_count += 1
        # Since BizHawk 2.6.2, all responses must be of the form $"{msg.Length:D} {msg}"
        # i.e. prefixed with the length in base-10 and a space.
        data = f"{len(data)} {data}"
        self.server.send(data)

    def _recv(self) -> list[str]:
        data = self.server.recv(enable_decode=True)
        if data is None:
            raise BizHawkError()
        data = str(data).strip()
        return [v.strip() for v in data.split("|") if v.strip() != ""]

    def _recv_image(self, resize_shape=None) -> np.ndarray:
        img_raw = self.server.recv(enable_decode=False)
        if img_raw is None:
            raise BizHawkError("image recv fail")
        img_arr = np.frombuffer(img_raw, dtype=np.uint8)
        img = cv2.imdecode(img_arr, cv2.IMREAD_COLOR)
        if resize_shape is None or img.shape == resize_shape:
            logger.debug(f"recv img: {img.shape}")
        else:
            old_shape = img.shape
            img = cv2.resize(img, resize_shape[:1])
            logger.debug(f"recv img: {old_shape} -> {img.shape}")
        return img

    def _convert_observation(self, obs_str: str) -> np.ndarray:
        return np.array([float(o) for o in obs_str.split(" ")])

    # -----------------------------
    # gym
    # -----------------------------
    def reset(self):  # super
        self.step_img = None
        if self.observation_type == ObservationTypes.VALUE:
            self._send("rv")
            obs_str = self._recv()[0]
            state = self._convert_observation(obs_str)
            logger.debug(f"{self._send_count} state {state.shape}: {str(state):100s}")
        elif self.observation_type == ObservationTypes.IMAGE:
            self._send("ri")
            state = self.step_img = self._recv_image(self.base_img_shape)
            logger.debug(f"{self._send_count} state {state.shape}")
        elif self.observation_type == ObservationTypes.BOTH:
            self._send("rb")
            obs_str = self._recv()[0]
            obs = self._convert_observation(obs_str)
            self.step_img = self._recv_image(self.base_img_shape)
            state = [self.step_img, obs]
            logger.debug(f"{self._send_count} state [{self.step_img.shape}, {obs.shape}: {str(obs):100s}]")
        else:
            raise BizHawkError(self.observation_type)

        return state, {}

    def step(self, action: list):  # super
        if isinstance(action, np.ndarray):
            action = action.tolist()
        if isinstance(action, tuple):
            action = list(action)
        for i, t in enumerate(self.action_types):
            if t == "bool":
                action[i] = str(action[i])
            elif t.startswith("int"):
                action[i] = str(action[i])
            elif t.startswith("float"):
                action[i] = str(action[i])
            else:
                action[i] = str(action[i])

        act_str = " ".join(action)
        if self.observation_type == ObservationTypes.VALUE:
            self._send(f"sv {act_str}")
        elif self.observation_type == ObservationTypes.IMAGE:
            self._send(f"si {act_str}")
        elif self.observation_type == ObservationTypes.BOTH:
            self._send(f"sb {act_str}")
        else:
            raise BizHawkError(self.observation_type)

        # --- recv
        vals = self._recv()
        reward = float(vals[0])
        done = True if vals[1] == "1" else False

        self.step_img = None
        if self.observation_type == ObservationTypes.VALUE:
            state = self._convert_observation(vals[2])
            logger.debug(f"{self._send_count} state {state.shape}: {str(state):100s}")
        elif self.observation_type == ObservationTypes.IMAGE:
            state = self.step_img = self._recv_image(self.base_img_shape)
            logger.debug(f"{self._send_count} state {state.shape}")
        elif self.observation_type == ObservationTypes.BOTH:
            obs = self._convert_observation(vals[2])
            self.step_img = self._recv_image(self.base_img_shape)
            state = [self.step_img, obs]
            logger.debug(f"{self._send_count} state [{self.step_img.shape}, {obs.shape}: {str(obs):100s}]")
        else:
            raise BizHawkError(self.observation_type)

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
            self.screen = pygame.Surface((self.base_img_shape[1], self.base_img_shape[0]))
            self.clock = pygame.time.Clock()

        if self.step_img is None:
            self._send("image")
            self.step_img = self._recv_image(self.base_img_shape)
        img = cv2.cvtColor(self.step_img, cv2.COLOR_BGR2RGB)
        img = img.swapaxes(0, 1)
        img = pygame.surfarray.make_surface(img)
        self.screen.blit(img, (0, 0))
        return np.transpose(np.array(pygame.surfarray.pixels3d(self.screen)), axes=(1, 0, 2))

    def get_valid_actions(self):
        return self.valid_actions


class SocketServer:
    def __init__(
        self,
        host: str,
        port: int,
        buffer_size: int = 1024 * 128,
        timeout: Optional[int] = None,
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

    def recv(self, enable_decode: bool) -> Union[None, str, bytes]:
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
