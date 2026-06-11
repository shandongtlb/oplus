# Peach_v2 Firmware Reverse Engineering - Deauth Injection 限制分析

> 目标：找到固件如何检查并 DISCARD deauth/disassoc 帧，寻找绕过方法
> 日期：2026-06-08（原始计划）/ 2026-06-10（更新结论）
> 平台：SM8750 (骁龙 8 Elite), peach_v2 chipset
> **本文对应全程实战记录 §11.5.5「单播突破方向四：固件逆向工程」**

> ⚠️ **重要更新（2026-06-10）**：
> - **广播 deauth 已突破**（不需要逆向，用 WMI test flag `tx_flags=0x00000001`，补丁 0013）。本文针对的是**单播** deauth。
> - **单播失败的根因已由 r10/r11 在驱动层确定**：固件检查**发送 vdev 的类型**（monitor vdev 只能发广播），**不是**本文 1.2 推断的"关联状态检查"。r11 用真正关联的合法 peer 测单播仍 DISCARD 已证明。
> - 因此固件逆向（本文方向四）的目标应修正为：找到并 patch 掉"monitor vdev 单播过滤"，而非"关联状态检查"。
> - 此方向**受固件签名校验阻挡**（见 §8.1），成功率约 5%，是 5 个方向里优先级最低的。

---

## 1. 现状总结

### 1.1 已知事实
- ✅ **普通管理帧注入成功**：beacon/probe request/probe response 等帧 → `status=0 COMPLETE_OK`
- ✅ **广播 deauth 已突破**：`tx_flags=0x00000001` → `status=0`（2.4G+5G，补丁 0013）
- ❌ **单播 Deauth/Disassoc 注入失败**：→ `status=1 WMI_MGMT_TX_COMP_TYPE_DISCARD`
- ✅ **Helper vdev 机制有效**：WMI_VDEV_TYPE_STA 可以发送普通管理帧
- ❌ **MAC 伪造无效 / 动态建 peer 无效 / 真实关联无效**：r10/r11 全部验证过，单播照样 DISCARD

### 1.2 固件层检查（r10/r11 验证后的正确结论）
**真正的限制**：固件按**发送 vdev 的类型**过滤——monitor vdev 只允许广播帧，单播一律 DISCARD。

~~关联状态检查~~（已证伪）：r11 让 STA vdev 真正关联目标 AP，对其 client 发单播仍 DISCARD，证明与关联状态无关。

逆向时应聚焦的真正检查点：
1. **vdev 类型门控**：`if (vdev->type == MONITOR && da != BROADCAST) DISCARD` —— 这是要 patch 的目标
2. Frame Control 字段检查：识别 fc=0xc0 (deauth) / 0xa0 (disassoc)（次要）

---

## 2. WMI 接口分析

### 2.1 WMI_MGMT_TX_SEND_CMDID 结构体
路径：`/root/pt/new/vendor/qcom/opensource/wlan/fw-api/fw/wmi_unified.h:7765`

```c
typedef struct {
    A_UINT32 tlv_header;
    A_UINT32 vdev_id;           // 🔍 关键：固件根据此 vdev 检查关联状态
    A_UINT32 desc_id;           // 驱动侧 ID，completion 时回显
    A_UINT32 chanfreq;          // 信道频率 (MHz)
    A_UINT32 paddr_lo;          // 物理地址低32位（pass by reference）
    A_UINT32 paddr_hi;          // 物理地址高32位
    A_UINT32 frame_len;         // 帧长度
    A_UINT32 buf_len;           // 缓冲区长度
    A_UINT32 tx_params_valid;   // 🔍 关键：如果设置，表示 RAW 帧（non-pause TID）
    A_UINT32 tx_flags;          // 额外标志（WMI_TX_SEND_FLAG_xxx）
    A_INT32  peer_rssi;         // 对端 RSSI（仅用于初始认证/关联）
} wmi_mgmt_tx_send_cmd_fixed_param;
```

**关键字段**：
- `vdev_id`：固件用它查询 vdev 上下文（关联状态、BSSID、peer 列表）
- `tx_params_valid`：标记为 RAW 帧，可能绕过某些检查
- `tx_flags`：可能有"强制发送"标志（需进一步查找定义）

### 2.2 WMI_MGMT_TX_COMP_STATUS_TYPE 枚举
路径：`/root/pt/new/vendor/qcom/opensource/wlan/fw-api/fw/wmi_unified.h:10440`

```c
typedef enum {
    WMI_MGMT_TX_COMP_TYPE_COMPLETE_OK = 0,     // 成功发送
    WMI_MGMT_TX_COMP_TYPE_DISCARD,             // 🚫 被固件丢弃（我们遇到的）
    WMI_MGMT_TX_COMP_TYPE_INSPECT,             // 需要进一步检查？
    WMI_MGMT_TX_COMP_TYPE_COMPLETE_NO_ACK,     // 发送但无 ACK
    WMI_MGMT_TX_COMP_TYPE_MAX,
} WMI_MGMT_TX_COMP_STATUS_TYPE;
```

**关键问题**：
- `DISCARD` 是在哪个阶段决定的？（队列入口？MAC 层？PHY 层？）
- `INSPECT` 类型是否与安全检查有关？

---

## 3. 逆向目标与方法

### 3.1 短期目标（1-2天）
1. ✅ **查找 WMI tx_flags 定义**：是否有"bypass security check"之类的标志
2. ✅ **分析 tx_params_valid RAW 模式**：这条路是否能绕过关联检查
3. ✅ **查找固件日志/调试接口**：是否能获取固件侧 DISCARD 的详细原因
4. ⬜ **查找 WMI offchan data TX**：offchan_data_tx_send_cmd 是否不检查关联状态

### 3.2 中期目标（3-7天）
5. ⬜ **提取固件二进制**：从设备 dump wlanmdsp.mbn / bdwlan*.bin
6. ⬜ **固件符号分析**：使用 Ghidra/IDA Pro 查找 mgmt_tx_send handler
7. ⬜ **查找 vdev 类型门控函数**：定位 `vdev->type == MONITOR && da != BROADCAST → DISCARD` 的检查（r10/r11 确认的真正限制点，非"关联状态检查"）
8. ⬜ **寻找绕过点**：
   - Option A：找到"raw inject"接口（不经过 mgmt_tx_send）
   - Option B：找到可修改的固件参数（通过 WMI config 命令）
   - Option C：找到可利用的固件 bug（状态机漏洞）

### 3.3 长期目标（1-2周，成功率低）
9. ⬜ **固件补丁**：如果找到检查点，尝试 patch 固件 binary
10. ⬜ **固件重编译**：如果高通泄露了固件源码（不太可能）

---

## 4. 立即行动：查找 WMI tx_flags 定义

让我先查找 `WMI_TX_SEND_FLAG_` 相关定义，看是否有可用的标志位。

### 4.1 查找 tx_flags 定义
```bash
grep -rn "WMI_TX_SEND_FLAG" /root/pt/new/vendor/qcom/opensource/wlan/fw-api/fw/wmi_unified.h
```

### 4.2 查找 tx_params_valid 的使用
```bash
grep -rn "tx_params_valid" /root/pt/new/vendor/qcom/opensource/wlan/qcacld-3.0 --include="*.c"
```

### 4.3 查找 offchan_data_tx_send 的使用场景
```bash
grep -rn "offchan_data_tx_send" /root/pt/new/vendor/qcom/opensource/wlan/qcacld-3.0 --include="*.c"
```

---

## 5. 固件文件定位

### 5.1 固件加载路径
典型高通平台固件位置：
- `/vendor/firmware/wlan/qca_cld/` - 主固件目录
- `/vendor/firmware/bdwlan*.bin` - Board Data（射频参数）
- `/vendor/firmware/wlanmdsp.mbn` - WLAN DSP 固件

### 5.2 从设备提取固件
```bash
adb pull /vendor/firmware/wlan/ ./firmware_dump/
adb pull /vendor/firmware/bdwlan* ./firmware_dump/
```

### 5.3 固件格式识别
- `.mbn`：Qualcomm Multi-Boot Image（需要解包）
- `.bin`：ELF 或原始二进制（需要 binwalk 分析）
- `.tlv`：TLV 格式配置文件

---

## 6. 可能的绕过方案（优先级排序）

### 方案 A：使用 RAW 模式 + tx_params_valid（优先级：⭐⭐⭐⭐）
**原理**：WMI 注释说"RAW frame will be tx'ed on non-pause tid"，可能绕过正常管理帧的检查。

**实现**：
1. 设置 `tx_params_valid = 1`
2. 填充 `wmi_tx_send_params` 结构体（指定 TID、MCS、power 等）
3. 测试是否能发送 deauth

**风险**：可能需要额外的 TLV 参数，驱动侧支持不完整。

### 方案 B：使用 offchan_data_tx_send（优先级：⭐⭐⭐）
**原理**：offchan data TX 可能用于 P2P action frame，检查较松。

**实现**：
1. 构造 `wmi_offchan_data_tx_send_cmd_fixed_param`
2. 伪装 deauth 为 data frame（修改 frame type bits）
3. 在接收方看来仍是管理帧（802.11 header 不变）

**风险**：固件可能仍检查 frame control 字段。

### 方案 C：伪造完整关联状态 ❌ 已验证失败（r10/r11）
> r10 实现了动态建 peer + 试图伪造关联，r11 实现了 STA vdev 真正关联——
> 两者对单播 deauth 都无效（仍 DISCARD）。证明限制在 vdev 类型，伪造/真实关联都没用。
> 本方案方向已证伪，以下为历史记录。

**原理（已证伪）**：让 helper vdev 真的"关联"到目标 AP（但不完成握手）。

### 方案 D：利用 monitor vdev + raw inject（优先级：⭐）
**原理**：寻找固件的"真·原始注入"接口，完全绕过 mgmt_tx_send。

**实现**：
1. 查找是否有 `WMI_PDEV_PARAM_RAW_TX_ENABLE` 之类的参数
2. 尝试通过 HTT (Host Target Transport) 直接注入
3. 可能需要修改 DP (Data Path) 层代码

**风险**：
- 需要深入理解 HTT 协议
- 可能根本不存在这样的接口

---

## 7. 下一步行动检查清单

- [ ] 查找 WMI_TX_SEND_FLAG 定义
- [ ] 分析 tx_params_valid 在驱动中的使用
- [ ] 查找 offchan_data_tx_send 使用场景
- [ ] 从设备提取固件文件
- [ ] 使用 binwalk 分析固件格式
- [ ] 测试方案 A（RAW 模式）
- [ ] 测试方案 B（offchan data TX）
- [ ] 如果前面都失败，进入固件逆向阶段（Ghidra）

---

## 8. 已知限制与风险评估

### 8.1 技术限制
- **固件闭源**：高通不开放 WLAN 固件源码
- **签名验证（确认受阻）**：高通固件有签名 + secure boot，修改后无法加载。这是固件逆向方向（方向四）的致命障碍，也是它成功率仅约 5% 的根本原因。
- **硬件限制**：某些检查可能在硬件 MAC 层，驱动/固件都改不了

### 8.2 成功率评估（实验后更新）
- ✅ **WMI test flag（→广播 deauth）**：已成功（补丁 0013）
- ❌ **方案 C 伪造/真实关联（=r10/r11）**：已验证失败（限制在 vdev 类型）
- **方案 D（固件逆向 + patch）= 方向四**：成功率约 5%（受签名校验阻挡）

### 8.3 单播突破的现实选择（§11.5）
- **最有希望**：方向一 STA helper vdev 伪装目标 AP（30-40%，纯软件）
- **100% 可用**：方向五 外置 USB 网卡（rtl8187/zd1211rw SoftMAC，不受固件限制）
- **本文方向四（固件逆向）**：优先级最低，受签名阻挡，仅学习目的值得

---

## 9. 参考资料

### 9.1 相关文档
- [op13_monitor_injection_全程实战记录.md](op13_monitor_injection_全程实战记录.md) - 当前实现细节
- [injection_limitation_summary.md](injection_limitation_summary.md) - 功能限制总结

### 9.2 固件逆向工具
- **Ghidra**：NSA 开源逆向工具，支持 ARM/Hexagon DSP
- **IDA Pro**：商业逆向工具（$$$）
- **binwalk**：固件解包工具
- **QcomExtractor**：高通固件提取工具（GitHub）

### 9.3 参考案例
- **Nexmon 项目**（Broadcom 固件 patch）：证明固件 patch 可行
- **SEEMOO Lab 研究**：802.11 固件安全分析
- **高通 WLAN 文档**：部分 WMI 接口文档（泄露版）

---

## 10. 日志与进展记录

### 2026-06-08 - 项目启动
- ✅ 确认逆向目标：绕过 deauth DISCARD 限制
- ✅ 定位 WMI 固件 API 头文件：`fw-api/fw/wmi_unified.h`
- ✅ 分析 WMI_MGMT_TX_SEND_CMDID 结构体

### 2026-06-08 ~ 06-10 - 实验完成（无需进入固件逆向）
- ✅ **广播 deauth 突破**：`tx_flags=0x00000001`（补丁 0013），纯软件，未动固件
- ✅ **单播根因在驱动层定位完毕**：r10/r11 确认是 monitor vdev 类型限制，非关联状态
- 📌 **固件逆向（本文）降级为方向四**：受签名校验阻挡，成功率约 5%，暂不推进

---

**结论更新**：原"最终目标"（找到纯软件方法发 deauth，或证明不可能）**已部分达成**：
- 广播 deauth 的纯软件方法已找到（WMI test flag）
- 单播 deauth 已证明在 monitor vdev 上不可行（vdev 类型限制），但**未证明全平台不可能**——
  换 vdev 类型（方向一/二）或外置网卡（方向五）仍有路。固件逆向（本文方向四）是受签名阻挡的兜底选项。
- 完整方向规划见全程实战记录 §11.5。
