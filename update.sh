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

# 2. 注入 dpkg-scanpackages 会丢弃的 Sileo 专属字段
#    （它只输出白名单字段，SileoDepiction/SileoIcon/Depiction 等需手工补回）
echo "==> 注入 Sileo 元数据字段..."
python3 - "$PWD" <<'PYEOF'
import re, sys, os, subprocess, glob
repo = sys.argv[1]
pkgs_path = os.path.join(repo, 'Packages')
text = open(pkgs_path, encoding='utf-8').read()

# 收集每个 deb 的额外字段（Sileo 专属字段会被 dpkg-scanpackages 丢弃）
extra = {}   # package+version+arch -> {field: value}
wanted = ('SileoDepiction', 'Depiction', 'SileoIcon', 'ModernDepiction', 'Tag')
for deb in glob.glob(os.path.join(repo, 'debs', '*.deb')):
    out = subprocess.run(['dpkg-deb', '-f', deb], capture_output=True, text=True).stdout
    fields = {}
    for line in out.splitlines():
        if ':' in line and not line.startswith(' '):
            k, v = line.split(':', 1)
            if k.strip() in wanted:
                fields[k.strip()] = v.strip()
    if fields:
        # 用 Package/Version/Architecture 定位对应段落
        meta = subprocess.run(['dpkg-deb', '-f', deb, 'Package', 'Version', 'Architecture'],
                              capture_output=True, text=True).stdout
        m = dict(l.split(':', 1) for l in meta.splitlines() if ':' in l)
        key = (m.get('Package','').strip(), m.get('Version','').strip(), m.get('Architecture','').strip())
        extra[key] = fields

if extra:
    blocks = text.split('\n\n')
    out_blocks = []
    for blk in blocks:
        if not blk.strip():
            continue
        m = dict(re.findall(r'^(\S+): (.*)$', blk, re.M))
        key = (m.get('Package','').strip(), m.get('Version','').strip(), m.get('Architecture','').strip())
        if key in extra:
            # 先剔除同名（忽略大小写）字段，避免与 dpkg-scanpackages 输出重复
            for f in extra[key]:
                blk = re.sub(rf'^{re.escape(f)}: .*\n?', '', blk, flags=re.M | re.I)
            add = '\n'.join(f'{k}: {v}' for k, v in extra[key].items())
            blk = blk.rstrip('\n') + '\n' + add
        out_blocks.append(blk)
    text = '\n\n'.join(out_blocks) + '\n'
    open(pkgs_path, 'w', encoding='utf-8').write(text)
    print(f'    注入 {len(extra)} 个包的 Sileo 字段')
else:
    print('    无额外字段')
PYEOF

# 3. 压缩 Packages.gz（-n 去掉时间戳，保证内容不变时压缩结果稳定）
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
