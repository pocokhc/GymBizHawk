
# v0.3.0

**MainUpdates**

1. 安定動作のためにリファクタリング
   - [bizhawk][lua] change: runにpcallを追加し、異常終了時にpy側に通知するように修正
   - [bizhawk] add: 転送に失敗した場合に再送信する機能を追加
   - [bizhawk] change: 安定のためssをまとめて送らずに個別に変更
1. [bizhawk] spaceの仕様を変更
   - [lua] change: ACTION -> ACTION_SPACE, OBSERVATION -> OBSERVATION_SPACEに名前変更
   - [lua] change: OBSERVATION_SPACEを配列型に変更
   - SPACEの定義に配列形式の[N]と最後の項目を表す*を追加
   - [py] change: BizHawkSpacesを作ってencode/decode処理を一か所にまとめた
   - [doc] change: 合わせてドキュメントを修正
1. [bizhawk] new: frameskip機能を追加
1. [bizhawk][lua] change: modeをTRAINからFAST_RUN/RUNにし、emu側のspeedの動作を明確化
   - [py] change: Typesをenum型からLiteral型に変更
   - [py] change: SRL時の動作をtraining関係なくFAST_RUNに統一
1. [lua] change: logを削除しないようにし、utilsにremove_lua_logを追加、手動で削除するように変更
1. [examples] update: SMBは簡単なeasy環境と画像のみの環境を作成

**OtherUpdates**

1. [bizhawk][py] add: SRL用にdisplay_nameを実装
1. [utils] new: print_loggerを追加


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

