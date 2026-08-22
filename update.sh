#!/bin/bash
# 一键更新 Sileo/Cydia 软件源：扫描 debs/ 生成 Packages + Packages.gz + Release
# 用法：在仓库根目录执行 ./update.sh，然后 git add -A && git commit && git push

set -e
cd "$(dirname "$0")"

# 1. 生成 Packages（扫描 debs/ 下所有 .deb）
echo "==> 生成 Packages..."
rm -f Packages Packages.gz Release

# 用 dpkg-scanpackages 生成（Homebrew: brew install dpkg）
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    dpkg-scanpackages -m debs /dev/null > Packages
else
    echo "错误：未安装 dpkg-scanpackages，请先执行 brew install dpkg" >&2
    exit 1
fi

# 2. 压缩 Packages.gz（-n 去掉时间戳，保证内容不变时压缩结果稳定）
echo "==> 生成 Packages.gz..."
gzip -n -k -9 Packages

# 3. 计算校验和
echo "==> 生成 Release..."
size_pkgs=$(stat -f "%z" Packages)
size_gz=$(stat -f "%z" Packages.gz)
md5_pkgs=$(md5 -q Packages)
md5_gz=$(md5 -q Packages.gz)
sha1_pkgs=$(shasum -a 1 Packages | awk '{print $1}')
sha1_gz=$(shasum -a 1 Packages.gz | awk '{print $1}')
sha256_pkgs=$(shasum -a 256 Packages | awk '{print $1}')
sha256_gz=$(shasum -a 256 Packages.gz | awk '{print $1}')

cat > Release <<EOF
Origin: apt-repo
Label: apt-repo
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: 自用 iOS 越狱插件源，兼容 Sileo
MD5Sum:
 $md5_pkgs $size_pkgs Packages
 $md5_gz $size_gz Packages.gz
SHA1:
 $sha1_pkgs $size_pkgs Packages
 $sha1_gz $size_gz Packages.gz
SHA256:
 $sha256_pkgs $size_pkgs Packages
 $sha256_gz $size_gz Packages.gz

EOF

echo "==> 完成！生成的文件："
ls -lh Packages Packages.gz Release
echo ""
echo "接下来执行："
echo "  git add -A && git commit -m 'update packages' && git push"
