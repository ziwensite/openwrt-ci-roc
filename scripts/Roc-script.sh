#!/bin/bash
set -e

# 修改默认IP & 固件名称 & 编译署名和时间
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='nas'/g" package/base-files/files/bin/config_generate

# 设置默认主题为 argon
mkdir -p package/base-files/files/etc/uci-defaults

# 修复 ath11k NSS 补丁与内核 6.18 不兼容的问题
rm -f package/kernel/mac80211/patches/nss/ath11k/235-003-ath11k-add-AP_VLAN-vif-support-for-WDS-offload-in-NSS-offload.patch 2>/dev/null || true
cat > package/base-files/files/etc/uci-defaults/99_set_theme << 'EOF'
#!/bin/sh
uci set luci.main.mediaurlbase=/luci-static/argon
uci commit luci
EOF
chmod +x package/base-files/files/etc/uci-defaults/99_set_theme

# 调整NSS驱动q6_region内存区域预留大小（ipq6018.dtsi默认预留85MB，ipq6018-512m.dtsi默认预留55MB，带WiFi必须至少预留54MB，以下分别是改成预留16MB、32MB、64MB和96MB）
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x01000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x02000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x04000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# 调整NSS驱动q6_region内存区域预留大小（仅修改512m版本，1G设备不需要修改）
if [ -f target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi ]; then
  sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
fi

# 调节IPQ60XX的1.5GHz频率电压(从0.9375V提高到0.95V，过低可能导致不稳定，过高可能增加功耗和发热，具体数值需要根据实际情况调整)
# sed -i 's/opp-microvolt = <937500>;/opp-microvolt = <950000>;/' target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch
# 调节IPQ60XX的1.5GHz频率电压
if [ -f target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch ]; then
  sed -i 's/opp-microvolt = <937500>;/opp-microvolt = <950000>;/' target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch
fi

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-argon-config 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-wechatpush 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-appfilter 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-frpc 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-frps 2>/dev/null || true
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
rm -rf feeds/packages/net/open-app-filter 2>/dev/null || true
rm -rf feeds/packages/net/ariang 2>/dev/null || true
rm -rf feeds/packages/net/frp 2>/dev/null || true
rm -rf feeds/packages/lang/golang 2>/dev/null || true

# Git稀疏克隆函数 - 修复版
git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  shift 2
  local repodir=$(basename "$repourl" .git)
  rm -rf "$repodir" 2>/dev/null || true
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"
  cd "$repodir" && git sparse-checkout set "$@"
  cd ..
  for item in "$@"; do
    [ -d "$repodir/$item" ] && mv -f "$repodir/$item" package/
  done
  rm -rf "$repodir"
  cd ..
}

# 创建必要的目录
mkdir -p package feeds/luci/applications feeds/luci/themes feeds/packages/net feeds/packages/lang

# ariang
rm -rf package/ariang 2>/dev/null || true
git clone --depth=1 -b ariang --single-branch https://github.com/laipeng668/packages package/ariang
[ -d package/ariang/net/ariang ] && mv -f package/ariang/net/ariang feeds/packages/net/
rm -rf package/ariang

# golang
rm -rf package/golang 2>/dev/null || true
git clone --depth=1 -b master --single-branch https://github.com/laipeng668/packages package/golang
[ -d package/golang/lang/golang ] && mv -f package/golang/lang/golang feeds/packages/lang/
rm -rf package/golang

# frp
rm -rf package/frp 2>/dev/null || true
git clone --depth=1 -b frp-binary --single-branch https://github.com/laipeng668/packages package/frp
[ -d package/frp/net/frp ] && mv -f package/frp/net/frp feeds/packages/net/
rm -rf package/frp

# frpc & frps - 已由 feeds update -a 自动安装，跳过独立克隆

# Argon 主题
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config 2>/dev/null || true
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config

# Aurora 主题
rm -rf feeds/luci/themes/luci-theme-aurora 2>/dev/null || true
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
rm -rf feeds/luci/applications/luci-app-aurora-config 2>/dev/null || true
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config

# OpenList2
rm -rf package/openlist2 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist2

# Lucky
rm -rf package/luci-app-lucky 2>/dev/null || true
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
# 检查是否需要单独克隆 lucky 核心程序
if [ -d "package/luci-app-lucky/lucky" ]; then
  mv -f package/luci-app-lucky/lucky feeds/packages/net/
fi

# Wechatpush
rm -rf package/luci-app-wechatpush 2>/dev/null || true
git clone --depth=1 https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush

# OpenAppFilter
rm -rf package/OpenAppFilter 2>/dev/null || true
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter

# Gecoosac
rm -rf package/luci-app-gecoosac 2>/dev/null || true
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac

# Athena LED
rm -rf package/luci-app-athena-led 2>/dev/null || true
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led 2>/dev/null || true
chmod +x package/luci-app-athena-led/root/usr/sbin/athena-led 2>/dev/null || true

### iStore 应用商店 ###
# 使用官方推荐的 feeds 方式
if ! grep -q "src-git istore" feeds.conf.default; then
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
fi

### Dockerman 容器管理 ###
rm -rf package/luci-app-dockerman 2>/dev/null || true
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman
[ -d package/luci-app-dockerman/luci-app-dockerman ] && mv -f package/luci-app-dockerman/luci-app-dockerman feeds/luci/applications/
rm -rf package/luci-app-dockerman

### 从 kenzok8/small-package 获取多个插件 ###
rm -rf small-package 2>/dev/null || true
git clone --depth=1 https://github.com/kenzok8/small-package.git small-package

# EasyTier 网络工具
[ -d small-package/luci-app-easytier ] && mv -f small-package/luci-app-easytier feeds/luci/applications/

# PartExp 潘多拉插件
[ -d small-package/luci-app-partexp ] && mv -f small-package/luci-app-partexp feeds/luci/applications/

# Cloudflared Tunnel
[ -d small-package/luci-app-cloudflared ] && mv -f small-package/luci-app-cloudflared feeds/luci/applications/

# Verysync 微力同步
[ -d small-package/net/verysync ] && mv -f small-package/net/verysync feeds/packages/net/verysync
[ -d small-package/luci-app-verysync ] && mv -f small-package/luci-app-verysync feeds/luci/applications/

# Syncthing 文件同步
rm -rf feeds/luci/applications/luci-app-syncthing 2>/dev/null || true
[ -d small-package/luci-app-syncthing ] && mv -f small-package/luci-app-syncthing feeds/luci/applications/

rm -rf small-package

### AdGuard Home 广告过滤 ###
rm -rf package/luci-app-adguardhome 2>/dev/null || true
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome
[ -d package/luci-app-adguardhome/luci-app-adguardhome ] && mv -f package/luci-app-adguardhome/luci-app-adguardhome feeds/luci/applications/
rm -rf package/luci-app-adguardhome

### CIFS 网络共享挂载 ###
rm -rf package/luci-app-cifs 2>/dev/null || true
git clone --depth=1 https://github.com/openwrt-develop/luci-app-cifs.git package/luci-app-cifs
[ -d package/luci-app-cifs/luci-app-cifs-mount ] && mv -f package/luci-app-cifs/luci-app-cifs-mount feeds/luci/applications/
rm -rf package/luci-app-cifs

### Quickfile 文件管理 ###
rm -rf package/quickfile 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/luci-app-quickfile.git package/quickfile
[ -d package/quickfile/quickfile ] && mv -f package/quickfile/quickfile feeds/packages/net/quickfile
[ -d package/quickfile/luci-app-quickfile ] && mv -f package/quickfile/luci-app-quickfile feeds/luci/applications/
rm -rf package/quickfile

### Verysync 微力同步 - luci界面 ###
rm -rf package/luci-verysync 2>/dev/null || true
git clone --depth=1 https://github.com/coolsnowwolf/luci.git package/luci-verysync
[ -d package/luci-verysync/applications/luci-app-verysync ] && mv -f package/luci-verysync/applications/luci-app-verysync feeds/luci/applications/
rm -rf package/luci-verysync

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null || true

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-openclash 2>/dev/null || true

# PassWall & OpenClash
rm -rf package/passwall-packages package/luci-app-passwall package/luci-app-passwall2 package/luci-app-openclash 2>/dev/null || true
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/luci-app-passwall2
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/luci-app-openclash

# 清理 PassWall 的 chnlist 规则文件
[ -f package/luci-app-passwall/root/usr/share/passwall/rules/chnlist ] && echo "baidu.com" > package/luci-app-passwall/root/usr/share/passwall/rules/chnlist

./scripts/feeds update -a
./scripts/feeds install -a

# 安装 istore 相关包
./scripts/feeds install -d y -p istore luci-app-store luci-app-unishare luci-lib-taskd luci-lib-xterm

# 安装缺失的包 - Verysync 微力同步核心程序
if [ ! -d "package/verysync" ]; then
  rm -rf package/verysync 2>/dev/null || true
  git clone --depth=1 --single-branch https://github.com/coolsnowwolf/packages.git package/verysync_tmp
  if [ -d "package/verysync_tmp/net/verysync" ]; then
    mv -f package/verysync_tmp/net/verysync package/verysync
  fi
  rm -rf package/verysync_tmp
fi

# 确保 unishare 在 feeds 安装后存在于 package 目录
if [ -d "feeds/packages/net/unishare" ] && [ ! -d "package/unishare" ]; then
  cp -r feeds/packages/net/unishare package/
fi