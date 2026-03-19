# Learning Bundle Spec

版本：v0  
更新时间：2026-03-19

## 1. 目标

`learning bundle` 用于把 OpenStaff 当前学习层事实源打包成一个可迁移、可校验、可恢复的离线资产。

v0 解决 3 个问题：

1. 把 `turn / evidence / signal / rule / profile / audit` 打成同一份可交付包。
2. 在恢复前先做 payload 校验与 dry-run 预览，而不是直接写盘。
3. 恢复后仍可用现有 `PreferenceProfileBuilder` 重新构建 profile，并保持 rule id 对齐。

## 2. v0 覆盖范围

bundle 至少包含以下 6 类对象：

- `turns`
- `evidence`
- `signals`
- `rules`
- `profiles`
- `audit`

当前不包含：

- `assembly`
- `extractions`
- `needs-review`
- 原始 screenshot / AX / OCR 二进制资产

原因：

- v0 的目标是优先保证学习闭环与偏好治理闭环可迁移。
- `assembly` 更偏运行时解释层，后续可在 v1 追加。
- 大体量原始附件会明显放大 bundle 体积，且当前 `InteractionTurn.observationRef` 已保留引用事实。

## 3. 目录结构

```text
<bundle>/
  manifest.json
  verification.json
  payload/
    turns/
    evidence/
    signals/
    rules/
    profiles/
    audit/
```

说明：

- `manifest.json`：bundle 元数据、对象索引、restore 路径、checksum。
- `verification.json`：导出时即时生成的 payload 校验结果。
- `payload/**`：真实可恢复数据。

## 4. Manifest 约定

`manifest.json` 固定包含：

- `schemaVersion = openstaff.learning.bundle-manifest.v0`
- `bundleSchemaVersion = openstaff.learning.bundle.v0`
- `bundleId`
- `createdAt`
- `source.learningRoot`
- `source.preferencesRoot`
- `source.filters`
- `counts`
- `indexes`
- `artifacts`
- `payloadVerification`

其中：

- `counts`：每类对象的 `files / records` 统计。
- `indexes`：按对象 id 聚合的索引，包含：
  - `turnIds`
  - `evidenceIds`
  - `signalIds`
  - `ruleIds`
  - `profileVersions`
  - `auditIds`
  - `latestProfileVersion`
  - `latestProfileUpdatedAt`
- `artifacts[]`：每个 payload 文件一条记录，固定带：
  - `category`
  - `format`
  - `sourcePath`
  - `sourceRelativePath`
  - `payloadPath`
  - `restorePath`
  - `recordCount`
  - `recordIds`
  - `sha256`
  - `sizeBytes`

## 5. 导出规则

### 5.1 全量导出

未指定过滤条件时，导出当前根目录下所有 bundle 支持对象。

### 5.2 按 session / task / turn 过滤导出

`export_learning_bundle.py` 支持：

- `--session-id`
- `--task-id`
- `--turn-id`

过滤不是简单“只拷匹配文件”，而是做闭环扩张：

1. 先选中命中的 `turn / evidence / signal / rule`。
2. 再补齐这些对象依赖的上游 / 下游对象。
3. 如某个 `profile` 命中已选规则，会自动补齐该 snapshot 引用到的全部 rule。
4. `audit` 只导出与当前闭环相关的行；同一日日志文件允许被裁切成子集。

这样做的目的是保证：

- bundle 可恢复
- profile 引用不残缺
- 同一 bundle 仍能被重新验证与 rebuild

## 6. 校验规则

`verify_learning_bundle.py` v0 固定做 3 层检查：

### 6.1 Manifest 层

- schema version 是否匹配
- `artifacts[]` 是否完整
- `payloadPath / restorePath` 是否安全（禁止绝对路径和 `..`）
- manifest 统计与真实 payload 是否一致

### 6.2 Payload 层

- 文件是否存在
- `sha256` 是否匹配
- 每类记录是否带最小必需字段
- 每条记录的 `schemaVersion` 是否符合当前 v0 约定

### 6.3 关系层

- evidence -> turn
- signal -> turn / evidence
- rule -> signal / turn / evidence
- profile -> rule
- audit -> signal / rule / profile

其中 audit 对缺失引用当前记为 `warning`，不直接 fail：

- 因为裁切 bundle 时，audit 可能只保留与当前恢复闭环直接相关的局部历史。

## 7. 恢复规则

恢复入口统一复用：

- `scripts/learning/verify_learning_bundle.py`

恢复前必须先做 bundle 校验，再给出 restore preview。

### 7.1 Dry-run

指定 `--restore-workspace-root <path>` 且不加 `--apply` 时：

- 只输出将要写入哪些 payload
- 标记每个目标文件是 `create / overwrite / conflict`
- 不真正写盘

### 7.2 Apply

加 `--apply` 后才真正恢复。

默认规则：

- 已存在目标文件时记为 `conflict`
- 有冲突则阻止恢复
- 只有显式传 `--overwrite` 才允许覆盖

### 7.3 恢复落点

payload 会恢复到标准工作区结构：

- `data/learning/turns/**`
- `data/learning/evidence/**`
- `data/preferences/signals/**`
- `data/preferences/rules/**`
- `data/preferences/profiles/**`
- `data/preferences/audit/**`

若 bundle 中存在 `indexes.latestProfileVersion`，恢复时会同步重建：

- `data/preferences/profiles/latest.json`

当前不会主动重建：

- `signals/index/**`
- `rules/index/**`

原因：

- `PreferenceMemoryStore` 在缺失索引时仍可回退到扫描模式。
- v0 先保证恢复正确性，再考虑索引重建提速。

## 8. 闭环验收

v0 要满足：

1. `export -> verify -> restore` 同一 bundle 可跑通。
2. 恢复后执行：

```bash
make preference-profile ARGS="--preferences-root <restored>/data/preferences --rebuild --json"
```

仍能成功输出新的 `PreferenceProfileSnapshot`。

3. rebuilt profile 内引用的 `ruleId` 与 bundle 恢复出来的规则保持一致。

## 9. CLI 示例

### 9.1 导出

```bash
python3 scripts/learning/export_learning_bundle.py \
  --learning-root data/learning \
  --preferences-root data/preferences \
  --output /tmp/openstaff-learning-bundle \
  --session-id session-001 \
  --json
```

### 9.2 校验

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --json
```

### 9.3 恢复前预览

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --restore-workspace-root /tmp/openstaff-restore-preview \
  --json
```

### 9.4 执行恢复

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --restore-workspace-root /tmp/openstaff-restored-workspace \
  --apply \
  --json
```
