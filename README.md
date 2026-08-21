# SimpleMCPBridge_Godot — Godot MCP 桥接插件

Godot 侧 MCP 桥接插件，对齐 [SimpleMcpServer](https://github.com/redcool/SimpleMCPServer) 的 wire protocol。
**本仓库根目录即插件本体**（独立插件仓库）：clone 进任意 Godot 工程的 `addons/simple_mcp_bridge/` 即可使用，随仓库 git 提交/拉取升级，无需手动拷贝文件。

```
AI Agent ⇄ (MCP stdio) ⇄ SimpleMcpServer(Node.js) ⇄ (WebSocket ws://ip:45678) ⇄ 本插件（Godot）
```

## 安装（宿主工程）

```bash
cd <你的Godot工程>
git clone https://github.com/redcool/SimpleMCPBridge_Godot.git addons/simple_mcp_bridge
```

在 `project.godot` 的 `[autoload]` 增加：

```
MCPBridge="*res://addons/simple_mcp_bridge/MCPBridge.gd"
```

（可选）首次使用生成本地配置（`bridge-config.json` 已在仓库 .gitignore 中，各工程可安全保留私有值，`git pull` 不会覆盖）：

```powershell
# PowerShell
Copy-Item addons\simple_mcp_bridge\bridge-config.json.temp addons\simple_mcp_bridge\bridge-config.json
```
```bash
# bash
cp addons/simple_mcp_bridge/bridge-config.json.temp addons/simple_mcp_bridge/bridge-config.json
```

字段说明（JSON 不支持注释，说明在此）：

| 字段 | 说明 |
|---|---|
| `serverIp` / `serverPort` | SimpleMcpServer 监听地址，默认 `127.0.0.1:45678` |
| `encryptionKey` | 与 server 的 config.json `encryptionKey` 对齐后开启 `#ENC#` AES-256-CBC 加密；留空 = 明文 |
| `projectName` | 桥 ID 中段 `<engine>-<project>-<guid>`；**多工程共连同一服务器时用它区分路由**（如 `team` / `rpg`），配合 `bridge.list` 按前缀判别；留空则回退引擎项目名 |

> 不复制配置文件也能跑：缺省时使用内置默认值（`projectName` 空 ⇒ 引擎项目名做 slug）。

启动顺序：先启动 SimpleMcpServer，再启动游戏；桥自动重连（3s 间隔）。
验证：服务端日志出现 `Registered N tool(s) from bridge`。

## 更新插件

```bash
git -C addons/simple_mcp_bridge pull
```

## 目录结构

- 根目录 = 插件本体：`MCPBridge.gd`（入口/autoload）、`ToolRegistry.gd`、`CryptoHelper.gd`、`bridge-config.json.temp`（配置模板，见上）、`Handlers/`（工具处理器）；`bridge-config.json` 由各工程自行从模板复制、不入库
- `examples/` = 可选冒烟演示（BridgeStatus 场景 + 脚本），不是插件运行必需

## 开发

插件在**宿主工程内**开发冒烟：编辑 `addons/simple_mcp_bridge/`（即本仓库的 clone），在宿主工程跑
`Godot --headless --path . --quit-after 60` 看 `bridge_id / ws_state / tools` 日志，改完 push 回 GitHub，其他工程 `git pull` 即升级。

## 架构与报文（骨架 v0.1，透传模式）

- 连接后服务端发 `server_info` / `request_tools`；桥回 `register_tools`（带 `bridgeId` 与工具列表）
- 工具调用：服务端发 `{id, method, paramsJson}`；桥回 `{id, result}` 或 `{id, error}`
- 可选 AES-256-CBC 载荷加密（`#ENC#` 前缀）——骨架阶段仅透传，`encryptionKey` 留空

## 首批工具（9 个）

| 工具 | 说明 |
|---|---|
| `core.get_status` | 引擎版本/FPS/当前场景/节点数/桥 ID |
| `core.get_hierarchy` | 场景树（上限 200 节点） |
| `core.get_objects` | 按名称/分组查节点路径 |
| `game.get_state` | GameState 快照（关卡/物资/成员/击杀） |
| `game.get_entities` | 读 `enemies`/`squad` 组实体 hp/位置/行为 |
| `input.key` | 模拟按键 tap/hold/release（Input.parse_input_event） |
| `input.action` | 直接操作 InputMap 动作 press/release |
| `input.get_state` | 当前按下的动作列表 |
| `data.get_table` / `data.get_by_id` | 只读 DataManager 数据表 |

## 注意事项

- 插件内部用 `res://addons/simple_mcp_bridge/...` 绝对路径 preload，**必须安装在 `addons/simple_mcp_bridge/`** 这一固定位置。
- 本仓库是插件包，不是独立可运行工程（无 `project.godot`）；单独冒烟请在宿主工程内进行。

## Roadmap（下一步）

- [ ] 加密对齐（`#ENC#` AES-256-CBC，crypto.ts 实现）
- [ ] `ui.*`：扫 Label/Button 文本 + 点击
- [ ] `input.mouse`：warp_mouse + 点击
- [ ] `input.gamepad`：合成摇杆/按键
- [ ] `game.do_sequence`：多步输入序列（AI 试玩）
- [ ] `camera.screenshot`：viewport 截图 PNG
- [ ] `scene.*`：节点创建/属性设置/方法调用（带黑名单）
- [ ] EditorPlugin + `@tool` 编辑器态工具
- [ ] 心跳/ping 对齐（服务端 ~30s 心跳）