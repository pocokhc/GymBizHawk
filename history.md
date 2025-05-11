
# v0.2.2

・SRLv1.1.1に合わせて修正
・gymnasium==1.1.1に合わせて修正
・pypi準備

**Updates**

1. [vscode] change: pypi準備+ruffに対応
1. [gymbizhawk.bizhawk] update: gymnasium==1.1.1に対応
1. [examples] update: SRLv1.1.1に合わせて修正


# v0.2.1

1. [examples] update: SMBとmoonのパラメータを調整
1. [gymbizhawk] new: modeにRECORDを追加

**Bug Fixes**

1. [gymbizhawk] fix: debug時にsetup時のmode指定がおかしかったので修正
1. [gymbizhawk] update: debug時にログを追加と挙動を改善（特に終了時にbizhawk側を操作できるように）


# v0.2.0

・SRLv0.17.0に合わせて修正

**MainUpdates**

1. [bizhawk] update: python(gym)から呼んだ場合とbizhawkで呼んだ場合でluaの挙動を変更
1. [bizhawk] update: luaの作業用ディレクトリ、lua_wkdirを追加(savestateフォルダは削除)
1. [bizhawk] change: doneをterminated, truncatedに分割
1. [bizhawk.lua] rename: rom.luaをsample.luaにし、optionを含めて関数を実装

**OtherUpdates**

1. doc/README更新
1. [examples/NES_SMG] backup/restoreの記載漏れを追加
1. [examples] update: srl v0.17.0に合わせて修正(主にmlflow対応)


# v0.1.2

1. [bizhawk] update: デフォルトで無音にする設定を追加
1. [bizhawk] update: save/loadの保存先をフォルダに変更
1. [bizhawk.lua] fix: save/loadのpathが数字になっていた不具合修正
1. [README] update: 文言を見直して英語版を追加


# v0.1.1

1. [examples.SMB] new: NES_SMBのsampleを追加
1. 初回に2回resetされるのを1回に変更
1. [bizhawk.lua] change: trainでlog_debugの出力なしに変更
1. [bizhawk.py] fix: obsでimageの場合BGRで出力される不具合修正
1. [bizhawk.py] fix: imageのサイズを一定に変更
1. [bizhawk.py] update: resetのspeedを高速に変更
1. [examples.moon] update


# v0.1.0

1st upload

