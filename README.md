[README in English](README-en.md)

[![(latest) release | GitHub](https://img.shields.io/github/release/pocokhc/GymBizHawk.svg?logo=github&style=popout)](https://github.com/pocokhc/GymBizHawk/releases/latest)

# GymBizhawk

これはマルチシステムエミュレータである[BizHawk](https://github.com/TASEmulators/BizHawk)と強化学習用の標準APIを提供する[Gymnasium(Gym)](https://github.com/Farama-Foundation/Gymnasium/tree/main)の連携ライブラリです。  
GymのAPI上でBizHawkを動かすことを目的としています。

# 1. インストール
## 1-1. BizHawkのインストール

[BizHawk](https://github.com/TASEmulators/BizHawk) よりインストールしてください。
（動作確認バージョン: 2.9.1）

## 1-2. 本ライブラリのインストール

``` bash
git clone https://github.com/pocokhc/GymBizHawk.git
cd GymBizHawk
pip install -r requirements.txt  # 必要ライブラリのインストール
pip install .                    # GymBizHawkのインストール
```

（動作確認バージョン: Python 3.12.3）

## 1-3. 実行例

``` bash
# 環境変数の設定
> SET BIZHAWK_DIR="BizHawkへのディレクトリパス"
> SET ROM_PATH="ROMのパス"
# 実行
> python examples/main.py
```

# 2. カスタマイズ

+ [オリジナル環境の作り方](https://pocokhc.github.io/GymBizHawk/pages/custom.html)

## サンプル

+ とりあえず動かしてみたい
    + examples/main.py
+ Lua側を作って動かしてみる
    + examples/PS_moon/
    + examples/NES_SMB/
+ 1stepの挙動も細かく制御して作成したい
    + examples/NES_DrMario/


# 3. Overview

![](diagrams/overview.drawio.png)


# 4. 開発環境

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
