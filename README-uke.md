# uke-sukisu-kernel

给 **小米平板 7（代号 `uke`）** 编译带 **SukiSU-Ultra + SUSFS** 的内核，用于 GitHub Actions 云编译。

## 为什么要自己编

小米设备的 `vendor_boot` / `vendor_dlkm` 模块是按小米自己的内核 ABI 编译的，
且官方内核开了 `CONFIG_MODVERSIONS=y`（模块符号 CRC 校验）。
直接刷第三方（Google GKI）内核会因为 CRC 不匹配导致模块加载失败、系统起不来。
所以必须**用小米自己的内核源码编译**，CRC 才能对上。

## 本仓库做的三件事

1. 用小米开源内核源码 `MiCode/Xiaomi_Kernel_OpenSource` 的 `uke-v-oss` 分支（Linux 6.1.68）
2. 编译基线用 `configs/uke_gki_defconfig` —— 这是从**官方出厂 boot.img 里提取的完整 .config**
   （内核开了 IKCONFIG，7.5k 行），比通用 `gki_defconfig` 更贴近出厂配置
3. 集成 `SukiSU-Ultra` 的 `builtin` 分支（内核内建 + 自带 SUSFS）

## 用法

Actions → **Build Kernel** → Run workflow → `Config file to build` 填 `config/uke.env`

产物：`AnyKernel3` zip（含 `Image`）以及单独的 `Image`。

## 上游

内核编译框架来自 [xiaoleGun/KernelSU_Action](https://github.com/xiaoleGun/KernelSU_Action)，
本仓库仅增加了 uke 的 profile 与出厂 config。
