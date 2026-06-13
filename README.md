# AwemeX AlphaPro V10.4 SafeFinal

V10.4 重点修复命名冲突：不再生成 AwemeX.dylib / AwemeX.plist，避免覆盖你原来的抖音图层文件。

## 新生成文件名

```text
AwemeXAlphaPro.dylib
AwemeXAlphaPro.plist
```

## 关键修改

```makefile
TWEAK_NAME = AwemeXAlphaPro
AwemeXAlphaPro_FILES = AwemeX_AlphaPro.xm
```

Filter 文件名也同步改为：

```text
AwemeXAlphaPro.plist
```

## 功能

- 顶部推荐/关注透明度
- 右侧按钮透明度
- 右侧按钮缩放
- 隐藏右上角搜索
- 右侧覆盖：头像、点赞、评论、收藏、分享、音乐
- 缩放使用 DYYY 风格 AWEElementStackView 识别方案

## Build fixes

- 添加 Filter plist
- 删除未使用函数
- 避免 deprecated keyWindow 直接调用
- TARGET 使用 iOS 14.0，避免 arm64e/iOS 13 warning
