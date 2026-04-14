# OP13 Docker / GKI `SYSVIPC` 启用说明

## 结论

如果你的目标是在 OP13 的 OPlus/OnePlus mixed build 里启用 Docker，`CONFIG_SYSVIPC` 不能只改 `msm-kernel` 或 `vendor` fragment，应该改 **GKI/common 树**。

结合现有构建链：

- GKI 侧来自 `kernel_platform/common`
- mixed build 使用的是 `common/build.config.gki.aarch64`
- 真正生成运行内核的是 common/GKI，不是单独的 vendor module 树

所以这类内核基础能力必须落在 common/GKI。

## 最小改动

优先检查并修改：

- `kernel_platform/common/arch/arm64/configs/gki_defconfig`

建议补入：

```config
CONFIG_SYSVIPC=y
CONFIG_SYSVIPC_SYSCTL=y
CONFIG_IPC_NS=y
```

其中：

- `CONFIG_SYSVIPC` 是 System V IPC 主开关
- `CONFIG_SYSVIPC_SYSCTL` 让 `/proc/sys/kernel/msg*`、`shm*`、`sem*` 相关 sysctl 可用
- `CONFIG_IPC_NS` 不是 `SYSVIPC` 本身，但 Docker 默认会用 IPC namespace，建议一起显式打开

## 建议 patch 模板

```diff
diff --git a/kernel_platform/common/arch/arm64/configs/gki_defconfig b/kernel_platform/common/arch/arm64/configs/gki_defconfig
--- a/kernel_platform/common/arch/arm64/configs/gki_defconfig
+++ b/kernel_platform/common/arch/arm64/configs/gki_defconfig
@@
 CONFIG_CGROUP_BPF=y
 CONFIG_NAMESPACES=y
+CONFIG_SYSVIPC=y
+CONFIG_SYSVIPC_SYSCTL=y
+CONFIG_IPC_NS=y
 # CONFIG_PID_NS is not set
```

说明：

- 上面的上下文行只是示意，实际插入位置以你树里的 `gki_defconfig` 为准
- 如果你本地树已经通过别的 fragment 间接打开了 `IPC_NS`，保留显式配置也没问题

## 为什么不能只改 `sun_perf.config`

像下面这种 vendor 侧 fragment：

- `kernel_platform/msm-kernel/arch/arm64/configs/vendor/sun_perf.config`

更适合放：

- vendor 模块功能开关
- 板级驱动
- `vendor_dlkm` 相关配置

但 `SYSVIPC` 这种会直接影响运行内核基础 IPC 能力的选项，如果 common/GKI 没开，最终刷机后很可能还是没有效果。

## 编译与刷机注意点

这类改动生效的前提通常是：

1. 重编 common/GKI 内核
2. 生成对应新的 boot / 内核镜像
3. 刷入与该 GKI 配置匹配的运行内核

如果你只替换：

- `vendor_dlkm.img`
- 单独 `.ko`

那 `CONFIG_SYSVIPC` 这种改动通常**不会**生效。

## 设备侧验收

刷入后建议先检查：

```sh
zcat /proc/config.gz | grep -E 'CONFIG_SYSVIPC|CONFIG_SYSVIPC_SYSCTL|CONFIG_IPC_NS'
```

预期至少看到：

```sh
CONFIG_SYSVIPC=y
CONFIG_SYSVIPC_SYSCTL=y
CONFIG_IPC_NS=y
```

再检查 SysV IPC 接口是否存在：

```sh
cat /proc/sysvipc/msg
cat /proc/sysvipc/sem
cat /proc/sysvipc/shm
```

以及 sysctl：

```sh
sysctl kernel.msgmax
sysctl kernel.shmmax
sysctl kernel.sem
```

## Docker 侧提醒

只开 `SYSVIPC` 往往还不是 Docker 的全部条件，它只是其中一块。

如果后面 `dockerd` 仍起不来，再继续核对：

- namespace 相关能力
- cgroup 相关能力
- overlay / netfilter / veth / bridge
- `iptables` / `nftables` 路径

但就你这一步而言，**把 `SYSVIPC` 放到 common/GKI 打开**，方向是对的。
