# AwemeX AlphaPro V10.6 FunctionFix

- 安全命名：生成 AwemeXAlphaPro.dylib / AwemeXAlphaPro.plist，不覆盖原 AwemeX。
- 修复 AX 菜单创建时机。
- 修复右侧按钮缩放：增加 UIView layoutSubviews + 遍历容器双方案。
- 修复隐藏右上搜索：增加更宽松搜索按钮识别。
- 加回“隐藏 AX 悬浮图标”开关。

如果 AX 图标隐藏后想恢复，可清理 App 的 NSUserDefaults 中 `ax_hide_ax_button`，或卸载重装后清缓存。
