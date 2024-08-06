

[![(latest) release | GitHub](https://img.shields.io/github/release/pocokhc/GymBizHawk.svg?logo=github&style=popout)](https://github.com/pocokhc/GymBizHawk/releases/latest)

# GymBizhawk

This is a library that links [BizHawk](https://github.com/TASEmulators/BizHawk), a multi-system emulator, and [Gymnasium(Gym)](https://github.com/Farama-Foundation/Gymnasium/tree/main), which provides a standard API for reinforcement learning.
The purpose is to run BizHawk on the Gym API.

# 1. Install
## 1-1. Installing BizHawk

Please install from [BizHawk](https://github.com/TASEmulators/BizHawk).
(Verified Version: 2.9.1)

## 1-2. Installing this library

``` bash
git clone https://github.com/pocokhc/GymBizHawk.git
cd GymBizHawk
pip install -r requirements.txt  # Installing required libraries

# Installing this library
# ※If you have the python path in the gymbizhawk directory, you can use it without installing it.
pip install .
```

(Verified Version: Python 3.12.3)


## 1-3. Sample Usage

``` bash
# set Environmental Variables
> SET BIZHAWK_DIR="Directory path to BizHawk"
> SET ROM_PATH="ROM path"
# run
> python examples/main.py
```

# 2. Customize

+ [Make Original Environment](https://pocokhc.github.io/GymBizHawk/pages/custom.html)

## Samples

+ I want to move it for now.
    + examples/main.py
+ I want to add the lua side and create it.
    + examples/PS_moon/
    + examples/NES_SMB/
+ I want to control and create the behavior of 1 step.
    + examples/NES_DrMario/


# 3. Overview

![](diagrams/overview.drawio.png)


# 7. Development environment

+ PC1
  + windows11
  + CPUx1: Core i7-8700 3.2GHz
  + GPUx1: NVIDIA GeForce GTX 1060 3GB
  + memory 48GB
+ PC2
  + windows11
  + CPUx1: Core i9-12900 2.4GHz
  + GPUx1: NVIDIA GeForce RTX 3060 12GB
  + memory 32GB
