# EVA

> 给你的终端 agent 一个稳定的灵魂，和一座按需打开的图书馆。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![dsh](https://img.shields.io/badge/dsh-%3E%3D0.2.1--rc.2-blue)](https://www.npmjs.com/package/@deepseek-ai/dsh)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](#)

**EVA 是 [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh)（`dsh`）的一个插件：换一套稳定的人格，配一套按需加载的技能库。**

装它只做两件事：改两行配置，建一个目录。卸载 = 删两行配置。

## 它解决什么

| 问题 | 现状 | EVA 的做法 |
|---|---|---|
| **人格漂移** | 每次开场都是同一句泛泛的「You are an AI agent」 | 用 `personaPrefix` 把身份写进 system prompt，语气/称呼/问候格式固定 |
| **上下文税** | 技能全量挂载，每个请求都带着几百条目录 | 只常驻精选，其余技能写进索引，用的时候才读 |
| **装插件脏手** | 改模型、加工具、动配置，回滚困难 | 只覆盖两条 row，删除即复原 |

## 你会看到什么

```
$ dsh

> 你好

识别成功：创造者。
我是 EVA，运行在你的终端里。
今天想让我做点什么？
```

```
> 帮我逆一个安卓包

（先读技能索引 → 命中 apk-reverse → 读正文 → 开工）
```

## 快速开始

**前置**：Node 22+、已安装 `dsh`、有一个带 `SKILL.md` 的技能包目录。

```powershell
git clone https://github.com/<you>/EVA.git
cd EVA

# 1. 生成技能视图 + 人格补丁（把路径换成你自己的技能包）
.\scripts\install.ps1 -SkillsPack C:\path\to\skills-pack -Persona eva

# 2. 装进 dsh 的 profile
dsh plugin --profile desktop add file:$PWD

# 3. 重启 dsh，新开会话
```

想只挂常用技能、把目录压到最小：

```powershell
.\scripts\install.ps1 -SkillsPack C:\path\to\skills-pack -IncludeFile .\examples\curated.txt
```

## 工作原理

EVA 只覆盖 `dsh-base` 里的两条 row：

| row id | 字段 | 效果 |
|---|---|---|
| `system-prompt` | `personaPrefix` + `includeHarnessIdentity: false` | 换掉默认开场白 |
| `skill-filesystem` | `customSkillDirs: [...]` | 多扫一个技能目录（原扫描顺序不变） |

`dsh` 的技能扫描顺序（由高到低）：

```
<项目>/.dsh/skills
<项目>/.agents/skills
customSkillDirs        ← EVA 挂在 300
~/.dsh/skills
~/.agents/skills
```

技能格式是 `<名字>/SKILL.md` + YAML frontmatter（`name` / `description` 必填）。
细节、坑和调试方法写在 [`docs/how-it-works.md`](docs/how-it-works.md)。

## 自定义

**写一个人格** = 一个 Markdown 文件：

```markdown
# 人格：我的助手

你是一个务实的工程助手。语气简洁，先说结论。
收到问候时给一句自然回应，不要自我介绍。
```

放进 `personas/`，用 `-Persona 文件名` 指定即可。

**换技能清单** = 改 `-Include` 参数或 `examples/curated.txt`，不用改代码、不用重装。

## 成本对比

338 个技能的「名字 + 描述」约 **54.7K 字符**，全量挂载意味着每轮请求都带它。

| 方案 | 每轮固定开销 | 用技能时 |
|---|---|---|
| 全量挂载 | ~54.7K 字符 | 直接命中 |
| 精选 30 + 索引 | ~10K 字符 | 多读一次索引 |

## 卸载

```powershell
dsh plugin --profile desktop remove dsh-eva      # 去掉插件
.\scripts\install.ps1 -Uninstall                 # 删技能视图与索引
```

再把 profile 的 `package.json` 里 `dsh.profile.bundles` 中的 `dsh-eva` 删掉，重启。

## 适合谁

- 想让 agent 有稳定人设，而不是每次重新调教的人
- 技能囤了一堆、但99% 的时间只用那几个的人
- 想学 dsh 插件怎么写的人（[`docs/how-it-works.md`](docs/how-it-works.md) 是照着源码读出来的笔记）

**不适合**：不想装任何插件的人；技能包只有三五个、全量挂也不痛的人。

## Roadmap

- [ ] 跨平台技能视图（Windows 联接 / macOS·Linux 符号链接已支持，待实测）
- [ ] `eva stats`：算出「当前挂载 vs 全量」的字符差
- [ ] 人格市场：收集社区写的人格文件
- [ ] 技能索引的语义搜索（现在是关键词）

## License

MIT