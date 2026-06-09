# 驱动层面优化：减少helper vdev重建开销

## 当前问题

### 现象
airodump-ng多次运行后AP递减，最终搜不到AP

### 根本原因（驱动层面）

**当前实现** (`wma_mgmt.c:3335-3338`)：
```c
if (g_inj_tx_vdev.created) {
    if (g_inj_tx_vdev.chanfreq == chanfreq)
        return QDF_STATUS_SUCCESS;  // 信道未变，复用
    wma_inject_destroy_tx_vdev();   // 信道变了 -> 完全销毁重建
}
```

**问题链**：
1. airodump-ng跳频（2.4G: 1-14, 5G: 36-165）每秒切换多次
2. 每次信道切换触发 `iw dev wlan0mon set freq` 
3. 调用 `wma_inject_ensure_tx_vdev(mon_vdev_id, new_freq)`
4. 检测到信道变化 → **完全销毁旧vdev + 创建新vdev**
5. 销毁流程：`peer_delete → vdev_stop → vdev_delete`（3个WMI命令 + 300ms sleep）
6. 创建流程：`vdev_create → vdev_start → peer_create`（3个WMI命令 + 350ms sleep）
7. **总耗时 ~650ms/次，每秒可能执行10+次**

**状态残留**：
- WMI command queue堆积（固件处理速度 < 发送速度）
- vdev slot状态不一致（delete还在pending，新create已发出）
- RX ring descriptor未完全清理（monitor vdev的RX与helper vdev的状态有交互）
- peer表残留（固件侧peer delete可能异步完成）

## 驱动层面解决方案

### 方案1: 使用vdev_restart代替destroy+recreate（推荐）

#### 原理
WMI提供了`vdev_restart`命令，可以修改一个已存在vdev的信道，**无需销毁重建**。

**标准流程**（正常BSS切换信道）：
```
vdev_down → vdev_restart (new channel) → vdev_up
```

**helper vdev适配**（无需vdev_up）：
```
vdev_stop → vdev_restart (new channel) → (保持STARTED状态即可)
```

#### 代码修改

**位置**: `core/wma/src/wma_mgmt.c:3335-3338`

**原代码**:
```c
if (g_inj_tx_vdev.created) {
    if (g_inj_tx_vdev.chanfreq == chanfreq)
        return QDF_STATUS_SUCCESS;
    wma_inject_destroy_tx_vdev();  // 完全销毁
}
```

**优化后**:
```c
if (g_inj_tx_vdev.created) {
    if (g_inj_tx_vdev.chanfreq == chanfreq)
        return QDF_STATUS_SUCCESS;
    
    /* Channel changed: restart the helper vdev instead of destroy+recreate */
    return wma_inject_restart_tx_vdev(chanfreq);
}
```

**新函数 `wma_inject_restart_tx_vdev()`**:
```c
static QDF_STATUS wma_inject_restart_tx_vdev(uint32_t new_chanfreq)
{
    tp_wma_handle wma = cds_get_context(QDF_MODULE_ID_WMA);
    struct vdev_stop_params vstop = {0};
    struct vdev_start_params vstart = {0};
    QDF_STATUS status;

    if (wma_validate_handle(wma) || !wma->wmi_handle)
        return QDF_STATUS_E_INVAL;
    if (!g_inj_tx_vdev.created)
        return QDF_STATUS_E_INVAL;

    wma_debug("NETHUNTER-INJ: restarting TX helper vdev=%u freq %u->%u",
              g_inj_tx_vdev.vdev_id, g_inj_tx_vdev.chanfreq, new_chanfreq);

    /* 1. VDEV STOP (graceful, waits for pending TX) */
    vstop.vdev_id = g_inj_tx_vdev.vdev_id;
    status = wmi_unified_vdev_stop_send(wma->wmi_handle, &vstop);
    if (QDF_IS_STATUS_ERROR(status)) {
        wma_err("NETHUNTER-INJ: vdev stop failed %d", status);
        /* Non-fatal: proceed to restart anyway */
    }
    qdf_sleep(50);  // Short settle, much less than full destroy (100ms)

    /* 2. VDEV RESTART on new channel */
    vstart.vdev_id           = g_inj_tx_vdev.vdev_id;
    vstart.beacon_interval   = 0;
    vstart.dtim_period       = 0;
    vstart.channel.mhz       = new_chanfreq;
    vstart.channel.cfreq1    = new_chanfreq;
    vstart.channel.cfreq2    = 0;
    vstart.channel.phy_mode  = (enum wlan_phymode)wmi_host_to_fw_phymode(
            (new_chanfreq < 4000) ? WLAN_PHYMODE_11G : WLAN_PHYMODE_11A);
    vstart.channel.maxpower    = 20;
    vstart.channel.maxregpower = 20;
    vstart.is_restart        = true;  // KEY: tells FW this is a restart, not initial start

    status = wmi_unified_vdev_start_send(wma->wmi_handle, &vstart);
    if (QDF_IS_STATUS_ERROR(status)) {
        wma_err("NETHUNTER-INJ: vdev restart failed %d, destroying", status);
        /* Fallback: if restart fails, do full destroy+recreate */
        wma_inject_destroy_tx_vdev();
        return status;
    }
    qdf_sleep(50);  // Short settle for restart response

    /* Update cached freq */
    g_inj_tx_vdev.chanfreq = new_chanfreq;

    wma_info("NETHUNTER-INJ: TX helper vdev restarted on freq=%u", new_chanfreq);
    return QDF_STATUS_SUCCESS;
}
```

#### 优势

| 项目 | 销毁+重建 | vdev_restart |
|------|-----------|--------------|
| WMI命令数 | 6个 (del 3个 + create 3个) | 2个 (stop + restart) |
| 总耗时 | ~650ms | ~100ms |
| vdev slot | 释放+重新分配（可能失败） | 保持不变 |
| peer表 | 删除+重建 | 保持不变（同一个self-peer） |
| MAC地址 | 可能变化 | 保持不变 |
| 状态残留风险 | 高（delete异步，slot可能泄露） | 低（只是修改参数） |
| 固件开销 | 高（完整lifecycle） | 低（只更新channel） |

**性能提升**：
- 单次切换快 **6.5倍**
- airodump跳频场景（10次/秒）：从6.5秒开销降到1秒
- 状态累积问题几乎消失（不释放资源就不会泄露）

### 方案2: 添加debounce机制（辅助优化）

即使用了vdev_restart，频繁切换信道仍有开销。可以添加debounce：

```c
#define WMA_INJ_CHANNEL_SWITCH_DEBOUNCE_MS  200

static struct {
    qdf_timer_t debounce_timer;
    uint32_t pending_chanfreq;
    bool pending;
} g_inj_ch_debounce;

/* Called by iw set freq (cfg80211 context) */
QDF_STATUS wma_inject_ensure_tx_vdev(uint8_t mon_vdev_id, uint32_t chanfreq)
{
    ...
    if (g_inj_tx_vdev.created && g_inj_tx_vdev.chanfreq != chanfreq) {
        /* Debounce: if another channel switch comes within 200ms, skip this one */
        if (g_inj_ch_debounce.pending) {
            /* Update pending freq, cancel old timer */
            qdf_timer_stop(&g_inj_ch_debounce.debounce_timer);
        }
        g_inj_ch_debounce.pending_chanfreq = chanfreq;
        g_inj_ch_debounce.pending = true;
        qdf_timer_start(&g_inj_ch_debounce.debounce_timer, 
                        WMA_INJ_CHANNEL_SWITCH_DEBOUNCE_MS);
        return QDF_STATUS_SUCCESS;  // Return immediately, switch later
    }
    ...
}

static void wma_inject_debounce_timer_cb(void *ctx)
{
    if (!g_inj_ch_debounce.pending)
        return;
    
    uint32_t freq = g_inj_ch_debounce.pending_chanfreq;
    g_inj_ch_debounce.pending = false;
    
    wma_inject_restart_tx_vdev(freq);
}
```

**效果**：
- airodump快速跳频（ch1→6→11→1→...）时，只切换到**最后停留的信道**
- 如果200ms内跳了5个信道，只执行最后1次切换
- 进一步减少WMI命令数量

### 方案3: 改进销毁时的清理（兜底）

如果必须销毁重建（比如vdev_restart失败），改进清理流程：

```c
void wma_inject_destroy_tx_vdev(void)
{
    ...
    /* 原有的 peer_delete → vdev_stop → vdev_delete */
    pdel.vdev_id = g_inj_tx_vdev.vdev_id;
    wmi_unified_peer_delete_send(wma->wmi_handle, g_inj_tx_vdev.mac_addr, &pdel);
    qdf_sleep(WMA_INJ_PEER_SETTLE_MS);

    vstop.vdev_id = g_inj_tx_vdev.vdev_id;
    wmi_unified_vdev_stop_send(wma->wmi_handle, &vstop);
    qdf_sleep(WMA_INJ_PEER_SETTLE_MS);

    wmi_unified_vdev_delete_send(wma->wmi_handle, g_inj_tx_vdev.vdev_id);
    qdf_sleep(WMA_INJ_PEER_SETTLE_MS);

    /* NEW: 显式清理驱动侧状态 */
    if (wma->interfaces[g_inj_tx_vdev.vdev_id].vdev) {
        /* 如果还有残留的vdev object，清理它 */
        wma->interfaces[g_inj_tx_vdev.vdev_id].vdev = NULL;
    }
    
    /* NEW: flush pending WMI commands for this vdev */
    // wmi_flush_pending_vdev_commands(wma->wmi_handle, g_inj_tx_vdev.vdev_id);
    
    qdf_mem_zero(&g_inj_tx_vdev, sizeof(g_inj_tx_vdev));
    wma_info("NETHUNTER-INJ: TX helper vdev destroyed and cleaned");
}
```

## 推荐实施方案

### 阶段1: vdev_restart优化（高优先级）
- 实现 `wma_inject_restart_tx_vdev()`
- 修改 `wma_inject_ensure_tx_vdev()` 的信道变化逻辑
- **预期效果**：AP递减问题90%解决

### 阶段2: debounce（可选）
- 如果阶段1效果不够理想，添加debounce
- **预期效果**：进一步减少50%的信道切换次数

### 阶段3: 改进清理（兜底）
- 确保destroy时的状态完全清理
- **预期效果**：即使出现异常，也不会累积残留

## 实施文件

需要修改的文件：
1. `core/wma/src/wma_mgmt.c` - 主要修改点
2. `core/wma/inc/wma_internal.h` - 可能需要声明新函数（如果跨文件调用）

## 测试验证

### 测试场景1: 快速跳频
```bash
monstart 1
# 运行airodump-ng（全频段跳频）
airodump-ng wlan0mon
# 持续5分钟，ctrl+c后再次运行
airodump-ng wlan0mon
# 对比AP数量，应该不会递减
```

### 测试场景2: 手动快速切换
```bash
monstart 1
for i in 1 6 11 36 149 1 6 11 36 149; do
    iw dev wlan0mon set freq $(chan_to_freq $i)
    sleep 0.1
done
# 检查dmesg，应该看到restart日志，不是destroy+create
dmesg | grep NETHUNTER-INJ | tail -50
```

### 成功标准
1. airodump-ng多次运行后AP数量保持稳定
2. dmesg中看到 "restarting TX helper vdev" 而非 "destroying/creating"
3. 信道切换延迟 < 150ms（原来650ms）
4. 长时间运行无状态累积（运行1小时后仍正常）

## 风险评估

### 低风险
- vdev_restart是标准WMI API，广泛用于AP信道切换
- 只是复用已有机制，不是hack

### 中风险
- 固件可能对STA类型vdev的restart有特殊处理
- 需要在实际设备验证restart是否支持"未UP的vdev"

### 缓解措施
- 如果restart失败，自动fallback到destroy+recreate
- 代码中已包含error handling

## 总结

| 方案 | 复杂度 | 效果 | 风险 |
|------|--------|------|------|
| monreset（用户空间） | 低 | 70% | 无 |
| vdev_restart（驱动） | 中 | 90% | 低 |
| debounce（驱动） | 中 | 95% | 低 |
| 改进清理（驱动） | 低 | 75% | 无 |

**推荐路径**：
1. **立即可用**：monreset命令（已实现）
2. **长期优化**：驱动层vdev_restart（需要编译测试）

驱动优化可以让问题从根本上消失，用户无需手动干预。
