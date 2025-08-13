
# SuperMarioBros 1-1

スーパーマリオブラザーズ1-1を実行するサンプルです。


# How to play

1. 環境変数を設定
```
BIZHAWK_DIR: BizHawkのディレクトリを設定
SMB_PATH   : SMBのROMパスを設定
```

2. "./main.py"をpythonで実行


# env

- easy
  - Observation: Value
  - Action: A only (右とBは押しっぱなし)

- image
  - Observation: image
  - Action: all
  - ゴールで100、死亡等で-1、それ以外は0


