

実行サンプルです。

終了条件は指定していません。(doneは必ずFalseになります)

## 実行方法（環境変数）

1. 環境変数を設定
```
BIZHAWK_DIR: BizHawkのディレクトリを設定
ROM_PATH   : 起動するROMのパスを設定
```

2. "./main.py"をpythonで実行


## 実行方法（直接設定）

1. "./main.py"を書き換え

``` python
bizhawk_dir="BizHawkのディレクトリを設定",
```

2. "nes.lua"を書き換え

``` lua
this.ROM = "起動するROMのパスを設定"
```

3. "./main.py"をpythonで実行

