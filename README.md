# AwemeX AlphaPro V10.5 MenuFix

- 安全命名：生成 `AwemeXAlphaPro.dylib` 和 `AwemeXAlphaPro.plist`，不会覆盖原 `AwemeX.dylib`。
- 修复 AX 菜单不出现：菜单按钮不再只依赖 `applicationDidBecomeActive`，新增 `%ctor` 延迟触发、`UIViewController viewDidAppear`、`UIView didMoveToWindow` 和 1 秒保活检测。
- Filter：`com.ss.iphone.ugc.Aweme`。
