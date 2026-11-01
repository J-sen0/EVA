# dsh 插件与技能机制笔记

> 本文是从 `DeepSeek Harness` 安装目录里的 `app.asar` 和官方包 README 中读出来的，实测版本 `0.2.1-rc.5`。
> 官方没有面向第三方的完整文档，所以把踩过的地方记下来。**版本变化时以实际行为为准。**

## 1. profile 是什么

`dsh` 不是单体程序，而是「按顺序叠 patch 层」的运行时：

```
bundles（组合包，按 package.json 里的顺序）
  → profile 自己的 cordis.patch.yml
    → home 级 $DSH_HOME/cordis.patch.yml
      → --patch 指定的覆盖层
```

最终合成一棵配置树，每一行（row）有 `id` 和 `name`（插件包名）和 `config`。
用户改配置的正确姿势是写 patch，而不是改 bundle。

一个最小的第三方插件长这样：

```json
{
  "name": "my-plugin",
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
```

```yaml
# cordis.patch.yml
- id: system-prompt            # 覆盖已有 row
  config:
    personaPrefix: |
      ...

- insert:                       # 或者插入新 row
    - id: my-row
      name: my-plugin
```

## 2. 人格是怎么注入的

`@deepseek-ai/dsh-system-prompt` 负责组装系统提示，它是 `dsh-base` 里的 `system-prompt` 行：

| 字段 | 默认 | 作用 |
|---|---|---|
| `includeHarnessIdentity` | `true` | 是否带那句固定的 `You are an AI agent powered by DeepSeek Harness.` |
| `personaPrefix` | `''` | 人格前缀，order 0，排在第一方指引之前 |
| `personaSuffix` | `''` | 人格后缀，order 10200，排在之后 |
| `includeRuntimeContext` | `true` | 是否带运行时上下文 |

所以「换人格」= 覆盖 `personaPrefix`，想干净就顺手关掉 `includeHarnessIdentity`。

**注意**：`@deepseek-ai/dsh-persona` 是另一条路，但它只能在 agent scope 里挂，全局挂会和默认 persona 抢同名 section 直接报错。第三方插件用 `system-prompt.personaPrefix` 最稳。

## 3. 技能系统

两个包分工：

- `dsh-skill`：注册表，提供 `ctx.skills`
- `dsh-skill-filesystem`：从磁盘发现技能，把 frontmatter 解析成目录条目，正文按需加载

### 扫描根与优先级

| 优先级 | 来源 | 路径 |
|---|---|---|
| 100 | project-dsh | `<项目根>/.dsh/skills` |
| 200 | project-agents | `<项目根>/.agents/skills` |
| 300 | custom | `Config.customSkillDirs` |
| 400 | user-dsh | `<DSH_HOME>/skills` |
| 500 | user-agents | `<DSH_HOME 的兄弟>/.agents/skills` |
| 600 | bundled | 配置了 `bundledSkillDir` 才有 |

项目根 = 最近一个含 `.git` 的祖先目录；没有就用当前工作目录。

### 技能格式

```
<root>/<name>/SKILL.md      ← 目录式
<root>/<name>.md            ← 平铺式
```

**只扫根目录下一层**，嵌套的 `**/SKILL.md` 不会被发现——这点和很多人的直觉不一样。

frontmatter：

```yaml
---
name: my-skill            # 必填
description: ...          # 必填
whenToUse: ...            # 可选
disable-model-invocation: true   # 可选：不进模型目录
user-invocable: false            # 可选：不进人类命令
---
```

目录条目只带 `name` + `description`，正文在调用时才读。所以**技能数量 = 每轮的固定开销**，这是设计取舍的核心。

## 4. 指令文件（AGENTS.md）

`@deepseek-ai/dsh-agent-instructions` 负责加载：

1. 用户全局链：`$DSH_HOME/AGENTS.md` → `<agentsHome>/AGENTS.md`
2. 项目链：从项目根到会话工作目录，每一层找 `AGENTS.md` / `CLAUDE.md`（以及 `.local.md` 覆盖层）

`maxBytes` 默认 **65536**，超了会截断并给出可见提示（宽的文件先被丢，最具体的文件最后被截）。

**只加载一次**：`read` / `write` / `edit` 触达更深目录后，下一次请求才补上新出现的文件。

## 5. 装插件

桌面版的 profile 由 Electron 独占管理，**npm 版 CLI 会拒绝操作它**：

```
error: profile "desktop" is managed exclusively by the Electron application
```

要用安装目录里自带的命令运行时：

```
<安装目录>\resources\runtime\cli\bin\dsh.cmd plugin --profile desktop add file:D:\path\to\plugin
```

它内置 pnpm（实测 11.28.5），会把包写进 `~/.dsh/profiles/desktop/node_modules`。

### 两个实测坑

1. **`bundles` 不会自动更新**。`pnpm add` 只改 `dependencies`，要手工把包名加进 `dsh.profile.bundles`。
2. **退出码可能非零**。遇到 `ERR_PNPM_IGNORED_BUILDS`（依赖的构建脚本被跳过）时命令会失败，但包其实装好了——看 `package.json` 有没有写进去，别被退出码骗了。

另外：pnpm 继承 `http_proxy` / `https_proxy` 环境变量。代理没开却留着变量，会看到 `ECONNREFUSED 127.0.0.1:7897`，清空变量即可。

## 6. 不启动也能验证补丁

改完 `cordis.patch.yml` 心里没底？拿现成 profile 叠一层，只打印结果：

```powershell
dsh --profile headless --patch D:\path\to\cordis.patch.yml --dump-config
```

退出码 0 且输出里能看到你的 `personaPrefix` 和 `customSkillDirs`，就说明补丁能合成。
`--dump-config` 对 `desktop` profile 是被拒绝的，用别的 profile 验证即可。

## 7. Windows 文件系统注意

技能视图用**目录联接（Junction）**指向真实技能包，不复制内容。几点：

- 删除联接要用 `[IO.Directory]::Delete(path, $false)`，`Remove-Item -Recurse` 在某些情况下会顺着链接删到目标。
- 建联接前先判断 `ReparsePoint` 属性，避免误删真实目录。
- 脚本里所有删除都做一次「路径必须在目标目录下」的前缀校验。

## 8. PowerShell 5.1 的两个小坑

- **`$PSScriptRoot` 在 param 默认值里可能为空**。写成 `[string]$X = ''`，进函数体再 `if (-not $X) { $X = Join-Path $PSScriptRoot ... }`。
- **函数返回数组**：`return @($arr)` 在某些调用形态下会被当成单个对象传给下游参数。稳妥写法是逐条输出（`foreach ($x in $arr) { $x }`）。

## 参考

- `@deepseek-ai/dsh`（launcher）
- `@deepseek-ai/dsh-system-prompt` / `dsh-agent-instructions` / `dsh-skill` / `dsh-skill-filesystem`
- 安装目录：`<DeepSeek Harness>/resources/app.asar`（包 README 都在里面）