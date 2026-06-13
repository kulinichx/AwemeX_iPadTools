# AwemeX V10.2 DYYYScale

## 这版解决什么

V9 的右侧缩放使用 UIWindow 遍历猜容器，容易命中顶部栏或更大的播放页父容器，导致：

- 顶部“推荐/关注”附近图标错位；
- 右侧栏整列漂移；
- 缩放 slider 偶尔不生效。

V10 改为参考 DYYY 的成熟方式：hook `AWEElementStackView`，只在 `AWEPlayInteractionViewController` 内识别右侧 Stack 后执行 transform。

## 右侧功能覆盖

右侧透明度和识别已重点考虑：

- 头像 / 用户头像；
- 点赞 / digg / like；
- 评论；
- 收藏 / favorite / collect；
- 分享 / forward / share；
- 音乐 / music / cover / disk / disc / sound。

右侧缩放使用 AwemeX 自己的设置 key：

```objc
ax_right_buttons_scale
```

不是 DYYY 的：

```objc
DYYYElementScale
```

## 核心判断

右侧缩放命中条件：

- 当前 view 所属 VC 是 `AWEPlayInteractionViewController`；
- `accessibilityLabel == @"right"`；或
- 包含 `AWEPlayInteractionUserAvatarView`；或
- 子元素 `elementClassName` 命中头像/点赞/评论/收藏/分享/音乐相关元素。

## 测试建议

安装后杀掉抖音重新打开。

建议依次测试：

1. 右侧缩放 1.0：确认布局恢复原位；
2. 右侧缩放 0.8：确认头像/点赞/评论/收藏/分享/音乐整列一起缩小；
3. 右侧缩放 1.2：确认整列放大但不漂移；
4. 右侧透明度 0.3：确认分享和音乐也一起变化；
5. 切换视频 10 次：确认不会残留 transform。


## V10.2 BuildFix

- 删除未使用的 `AXTopVC()`，修复 GitHub Actions 中 `-Werror,-Wunused-function` 编译失败。


## V10.3 BuildFix

- 新增 `AwemeX.plist` Filter，修复 Theos stage 报错：`missing a filter property list`。
- Filter bundle：`com.ss.iphone.ugc.Aweme`。
