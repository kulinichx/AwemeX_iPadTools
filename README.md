# AwemeX iPad Tools V1.5.0

## 修复

- 右侧缩放改为 **仅播放页右侧播放面板**。
- 不再缩放设置页、我的页、消息页等普通界面。
- 设置面板分组支持点击展开/收起。
- 增加 PreferenceBundle 骨架，安装 PreferenceLoader 后可在系统设置里显示 AwemeX 入口。

## 注意

- 系统设置入口依赖 `PreferenceLoader`。
- 抖音内仍然可以通过 AX 悬浮按钮或双指长按打开完整设置面板。
- 系统设置里只放基础选项；完整滑条设置仍建议用抖音内 AwemeX 面板。

## 编译

有根：

```bash
make clean package
```

无根：

```bash
make clean package SCHEME=rootless
```
