# peach_v2 原生全局监听与注入实验线

一加 13 的硬件是 `peach_v2`。本线使用高通 `QDF_GLOBAL_MONITOR_MODE`
（`con_mode=4`）及原生 `wlan0` monitor vdev。sam 的 `kiwi_v2` 实现仅作为
输入解析、队列与资源管理的参考；其 helper STA 注入结果不能证明本线的固件支持。

## 应用与统一编译

源码基线为 `4d69a3ed9a176152e85580352723c308f29cbfcb`。在内核仓库根目录：

```sh
git apply /root/pt/oplus/补丁/qca_inject/0001-add-qcacldko.patch
git apply /root/pt/oplus/补丁/native_global/0001-peach-v2-native-global-monitor.patch
RECOMPILE_KERNEL=1 ./kernel_platform/oplus/build/oplus_build_kernel.sh sun perf
```

第一项只接入 `prepare_vendor.sh` 的 WLAN 统一构建，必需保留。第二项是当前
原生全局实现的合并 diff。不要叠加旧 `qca_inject/0002-0017`。

也可以从同一基线按 `exported/series` 顺序使用 `git am` 应用四个邮件补丁。
这与上面的两项应用方式二选一。对应源码提交：

- `d20c69af`：WLAN 统一构建接入。
- `2fa5ca62`：原生全局 monitor TX 初版。
- `f5bb38df`：实验性 PMF TX flag。
- `8e21acf0`：Radiotap、队列、回调竞态和 DMA 生命周期保护。

构建日志必须包含 kernel、WLAN platform、WLAN qcacld、Installing WLAN modules
及 DT 合并完成阶段；外层脚本退出码不能单独证明内部成功。

KSU 固定流程：统一构建 → 从 `kernel_platform/out/msm-kernel-sun-perf/dist/`
取 `cfg80211.ko`、`mac80211.ko`、`qca_cld3_peach_v2.ko` → 副本执行
`llvm-strip --strip-debug` → 放入 `vendor_dlkm/lib/modules/` → 打包 → 真机调试。
CNSS 只作为构建依赖，包内不放 CNSS 模块。校验记录见包内 `docs/BUILD_INFO.txt`。

## 已实现与验证边界

- 全局 monitor 的 RX 及退出后 managed/con_mode=0 已在旧 v2 包真机确认。
  当时 Wi-Fi 已启用但未确认重新关联，热点/P2P 恢复也未验收。
- 注入入口必须是 Radiotap + 24–2048 字节管理帧；支持剥除显式 FCS，拒绝
  DATAPAD、损坏头和控制/数据帧。其他 Radiotap 字段不设置固件速率或重试参数。
- 64 槽队列搜索空闲槽；满环停止队列，完成时唤醒。锁频成功后也按剩余容量恢复队列。
- 处理完成事件早于 send 返回的竞态，以 generation 字段区分重用槽的旧 descriptor。
- WMA 关闭时若存在漏 completion，保留 DMA 缓冲和模块引用、禁止后续注入。
  这是有界保留策略，目前仍需重启恢复；自动恢复尚未实现。
- `MGMT_TX_USE_INCORRECT_KEY` 的效果需要在本机测量。`[submit]` 只证明提交，
  `status=0` 只是固件报告，空口发送还需要独立接收端确认。

源码中的 `tests/test_monitor_radiotap.py` 使用本内核真实 Radiotap 解析器；
`tests/test_native_injection.py` 对真实 TX/回调代码注入分配失败、发送失败、
提前/重复/丢失完成事件。两者均使用 ASan/UBSan，不能代替固件与空口测试。

当前新包尚未热切：ADB 无设备连接。此前 Kali chroot 调用失败的原因未确认，
不能据此断定是 SELinux 或 namespace 限制。恢复连接后应通过设备脚本进入
`/data/local/nhsystem/kalifs`，用锁定信道的管理帧测试验证提交、完成和空口。
