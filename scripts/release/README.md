# scripts/release/

发布前检查工具（TODO 6.3）。

## 包含内容
- `build_demo_bundle.py`
  - 生成发布演示数据包（capture/knowledge/llm/skills 样例）。
  - 输出 `manifest.json` 与 `README.md` 便于演示交接。
- `run_regression.py`
  - 执行发布回归检查：
    1. LLM 输出样例校验。
    2. 三条 skill 映射 + skill 目录校验。
    3. 测试套件（`scripts/tests/run_all.py`）。
  - 输出结构化回归报告 JSON。

## 推荐命令
```bash
python3 scripts/release/build_demo_bundle.py --out-dir /tmp/openstaff-release-demo --overwrite
python3 scripts/release/run_regression.py --suite all
```

或直接使用根目录 Makefile：

```bash
make release-demo
make release-regression
make release-preflight
```
